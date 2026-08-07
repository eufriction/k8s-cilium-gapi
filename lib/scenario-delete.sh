#!/usr/bin/env bash
# scenario-delete.sh — delete scenario resources with statedb-safe convergence
set -euo pipefail

SCENARIO_DELETE_DIR="$(CDPATH="" cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/envoy-readiness.sh
source "${SCENARIO_DELETE_DIR}/envoy-readiness.sh"

echo "--- Deleting scenario resources ---"

# Pre-delete: ensure cilium has fully reconciled the scenario's resources.
# The statedb panic ("delete did not find old object") is triggered when the
# K8s reflector processes a delete event for an object whose index entry
# hasn't been fully written yet. We use two gates:
#
# 1. Wait for Gateway Programmed=True — the strongest external signal that
#    the data plane (Envoy + BPF LB) has been fully configured.
# 2. A small settle buffer for statedb internal indexing to quiesce.
#
# Together these give the agent time to finish before we hit it with deletes.
if [ "${FIXTURE_DEPLOYED:-}" = "true" ] && [ -d gateway ]; then
  # In gateway-only mode, wait for all gateways to be Programmed.
  gateways=$(kubectl get gateway -n gateway-system -o name 2>/dev/null || true)
  while IFS= read -r gw; do
    [ -n "$gw" ] || continue
    kubectl wait "$gw" -n gateway-system \
      --for='jsonpath={.status.conditions[?(@.type=="Programmed")].status}=True' \
      --timeout=30s 2>/dev/null || true
  done <<<"$gateways"
fi
sleep "${PRE_DELETE_SLEEP:-5}"

if ! kubectl rollout status daemonset/cilium -n kube-system --timeout=15s >/dev/null 2>&1; then
  echo "  ⚠ Cilium not stable — waiting for recovery before delete..."
  kubectl rollout status daemonset/cilium -n kube-system --timeout=90s >/dev/null
  sleep 5
fi

# Capture the Gateway identities before deletion. The generated Service, CEC,
# kindccm container, and Envoy resources are named from this identity.
if [ "${FIXTURE_DEPLOYED:-}" = "true" ] && [ -d gateway ]; then
  MANIFESTS=$(kubectl kustomize gateway/ --load-restrictor=LoadRestrictionsNone)
else
  MANIFESTS=$(kubectl kustomize . 2>/dev/null || true)
fi
GATEWAYS=$(printf '%s\n' "$MANIFESTS" |
  kubectl get -f - --no-headers \
    -o custom-columns='KIND:.kind,NAMESPACE:.metadata.namespace,NAME:.metadata.name' 2>/dev/null |
  awk '$1 == "Gateway" { print $2 "/" $3 }' || true)

if [ "${FIXTURE_DEPLOYED:-}" = "true" ] && [ -d gateway ]; then
  # Ordered deletion: remove routes first, then gateway + certs.
  # This reduces reconciliation pressure on the cilium-agent and operator
  # by letting them process route removal before the gateway disappears.
  ROUTES=$(echo "$MANIFESTS" | kubectl get -f - -o name 2>/dev/null | grep -E "httproute|grpcroute|tlsroute" || true)
  if [ -n "$ROUTES" ]; then
    echo "$ROUTES" | xargs kubectl delete --ignore-not-found
    sleep 2
  fi
  # Now delete the remaining resources (gateway, certificates, issuers).
  echo "$MANIFESTS" | kubectl delete --ignore-not-found -f -
else
  kubectl delete -k . --ignore-not-found
fi

# Wait for the entire LB/Envoy resource chain to disappear before the next
# scenario can create a Gateway with the same listener and ports.
while IFS= read -r gateway; do
  [ -n "$gateway" ] || continue
  gateway_namespace=${gateway%%/*}
  gateway_name=${gateway#*/}
  envoy_wait_gateway_resources_gone "$gateway_name" "$gateway_namespace"
done <<EOF
$GATEWAYS
EOF

# Keep an explicit override as a bounded emergency fallback, but do not sleep
# by default now that deletion is guarded by observable convergence gates.
if [ "${POST_DELETE_SLEEP:-0}" -gt 0 ]; then
  echo "Sleeping ${POST_DELETE_SLEEP}s after delete (POST_DELETE_SLEEP override)..."
  sleep "$POST_DELETE_SLEEP"
fi

# Post-delete: wait for Cilium to be stable after deletion.
# The statedb panic ("delete did not find old object") is triggered by the
# K8s reflector processing delete events. The crash happens DURING deletion,
# so the pre-delete check above passes fine. We must verify the agent survived
# the delete before proceeding to the next scenario.
if ! kubectl rollout status daemonset/cilium -n kube-system --timeout=5s >/dev/null 2>&1; then
  echo "  ⚠ Cilium crashed during delete — waiting for recovery..."
  kubectl rollout status daemonset/cilium -n kube-system --timeout=120s >/dev/null
  echo "  ✓ Cilium recovered — waiting ${LISTENER_READY_TIMEOUT:-45}s for Envoy re-init..."
  sleep "${LISTENER_READY_TIMEOUT:-45}"
fi
