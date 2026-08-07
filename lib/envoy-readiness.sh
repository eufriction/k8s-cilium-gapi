#!/usr/bin/env bash
# envoy-readiness.sh — LB teardown and Cilium Envoy convergence helpers
#
# This file is sourced by verify-helpers.sh and scenario-delete.sh. Every
# function returns a status so callers using set -e can decide whether a
# readiness failure is an infrastructure failure or an expected assertion.

ENVOY_READINESS_NAMESPACE="kube-system"
ENVOY_READINESS_CONTAINER="cilium-agent"
ENVOY_GATEWAY_LABEL="io.x-k8s.cloud-provider-kind.gateway.name"

# envoy_agent_pods
#
# Print the Cilium agent pod names. The agent owns the local cilium-dbg Envoy
# admin client, so querying each agent avoids relying on a single worker.
envoy_agent_pods() {
  kubectl get pods -n "$ENVOY_READINESS_NAMESPACE" \
    -l k8s-app=cilium \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null
}

# envoy_exec <pod> <command...>
#
# Run a cilium-dbg command against the Envoy attached to one Cilium agent.
envoy_exec() {
  local pod="$1"
  shift
  kubectl exec -n "$ENVOY_READINESS_NAMESPACE" "$pod" \
    -c "$ENVOY_READINESS_CONTAINER" -- "$@"
}

# envoy_ingress_ips <pod>
#
# Return the local endpoint IPs carrying the reserved:ingress identity.
envoy_ingress_ips() {
  local pod="$1"
  envoy_exec "$pod" cilium-dbg endpoint list -o json 2>/dev/null |
    jq -r '.[]
      | select((.status.labels."security-relevant" // []) | index("reserved:ingress"))
      | .status.networking.addressing[]?.ipv4 // empty' 2>/dev/null
}

# envoy_listener_ready <pod> <gateway> <namespace>
#
# Verify that the Gateway listener exists and is no longer warming.
envoy_listener_ready() {
  local pod="$1" gw="$2" ns="$3"
  local qualified="${ns}/cilium-gateway-${gw}"
  local listeners

  listeners=$(envoy_exec "$pod" cilium-dbg envoy admin listeners -o json 2>/dev/null) || return 1
  printf '%s\n' "$listeners" | jq -e --arg needle "$qualified" '
    [.. | objects | select((.name? // "") | strings | contains($needle))] as $matches
    | ($matches | length) > 0
    and ($matches | all(.[]; (has("warming_state") | not)))
  ' >/dev/null 2>&1
}

# envoy_route_ready <pod> <gateway> <namespace>
#
# Cilium names Gateway-generated route resources with the namespace and
# gateway service name. The config response is intentionally checked as text
# because the cilium-dbg config command has changed its JSON envelope between
# releases.
envoy_route_ready() {
  local pod="$1" gw="$2" ns="$3"
  local routes qualified
  qualified="${ns}/cilium-gateway-${gw}/"

  routes=$(envoy_exec "$pod" cilium-dbg envoy admin config routes \
    2>/dev/null) || return 1
  if [ -n "$routes" ] && {
    printf '%s\n' "$routes" | grep -F "$qualified" >/dev/null ||
      printf '%s\n' "$routes" | grep -F "cilium-gateway-${gw}" >/dev/null
  }; then
    return 0
  fi

  # TLS passthrough listeners use Envoy TCP proxy clusters and do not create
  # an HTTP RouteConfiguration. Only require a route table when the Gateway
  # declares an HTTP or HTTPS listener.
  kubectl get gateway "$gw" -n "$ns" -o json 2>/dev/null |
    jq -e '[.spec.listeners[] | select(.protocol == "HTTP" or .protocol == "HTTPS")] | length == 0' \
      >/dev/null 2>&1
}

# envoy_policy_ready <pod>
#
# Every worker that has a local reserved:ingress endpoint must publish that
# endpoint IP in Envoy's NetworkPoliciesConfigDump before it can receive
# Gateway traffic. With externalTrafficPolicy: Local, other workers are not
# traffic targets and legitimately have no local ingress policy.
envoy_policy_ready() {
  local pod="$1"
  local ingress_ips policies ip

  ingress_ips=$(envoy_ingress_ips "$pod")
  # externalTrafficPolicy: Local only sends traffic to nodes with a local
  # ingress endpoint. Agents without one do not need an Envoy policy entry.
  [ -n "$ingress_ips" ] || return 0
  policies=$(envoy_exec "$pod" cilium-dbg envoy admin config networkpolicies 2>/dev/null) || return 1
  [ -n "$policies" ] || return 1

  while IFS= read -r ip; do
    [ -n "$ip" ] || continue
    if ! printf '%s\n' "$policies" | grep -F "$ip" >/dev/null; then
      return 1
    fi
  done <<EOF
$ingress_ips
EOF
}

# envoy_gateway_probe <pod> <gateway> <namespace>
#
# Run all convergence checks for one agent and return a short reason through
# the global ENVOY_READINESS_REASON variable for timeout diagnostics.
envoy_gateway_probe() {
  local pod="$1" gw="$2" ns="$3"
  ENVOY_READINESS_REASON=""

  if ! envoy_listener_ready "$pod" "$gw" "$ns"; then
    ENVOY_READINESS_REASON="listener missing or warming"
    return 1
  fi
  if ! envoy_route_ready "$pod" "$gw" "$ns"; then
    ENVOY_READINESS_REASON="route configuration missing"
    return 1
  fi
  if ! envoy_policy_ready "$pod"; then
    ENVOY_READINESS_REASON="reserved:ingress policy missing"
    return 1
  fi
  return 0
}

# envoy_readiness_diagnostics <gateway> <namespace>
#
# Print the state needed to distinguish publication, route, and policy races.
envoy_readiness_diagnostics() {
  local gw="$1" ns="$2"
  local service="cilium-gateway-${gw}"
  local gateway_label="${KIND_CLUSTER_NAME:-k8s-cilium-gapi}/${ns}/${gw}"
  local pod node ingress_ips

  echo "--- Envoy readiness diagnostics ---" >&2
  kubectl get svc "$service" -n "$ns" -o yaml >&2 2>&1 || true
  kubectl get cec "$service" -n "$ns" -o yaml >&2 2>&1 || true
  docker ps -a --filter "label=${ENVOY_GATEWAY_LABEL}=${gateway_label}" \
    --format 'container={{.ID}} name={{.Names}} status={{.Status}} ports={{.Ports}}' >&2 2>&1 || true

  while IFS= read -r pod; do
    [ -n "$pod" ] || continue
    node=$(kubectl get pod "$pod" -n "$ENVOY_READINESS_NAMESPACE" \
      -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
    ingress_ips=$(envoy_ingress_ips "$pod" | tr '\n' ' ' || true)
    echo "--- pod=${pod} node=${node:-unknown} local_ingress_ips=${ingress_ips:-none} ---" >&2
    envoy_exec "$pod" cilium-dbg envoy admin listeners -o json >&2 2>&1 || true
    envoy_exec "$pod" cilium-dbg envoy admin config routes \
      -n "$service" >&2 2>&1 || true
    envoy_exec "$pod" cilium-dbg envoy admin config networkpolicies >&2 2>&1 || true
    envoy_exec "$pod" cilium-dbg envoy admin metrics \
      --filter 'envoy_cilium_access_denied' >&2 2>&1 || true
  done <<EOF
$(envoy_agent_pods || true)
EOF
}

# envoy_gateway_ready <gateway> <namespace> [timeout_seconds]
#
# Wait for every Cilium agent to converge on the Gateway listener, route, and
# ingress policy. Returns 2 so a caller can report the result as INFRA.
envoy_gateway_ready() {
  local gw="$1" ns="$2" timeout="${3:-${ENVOY_READY_TIMEOUT:-30}}"
  local deadline=$((SECONDS + timeout))
  local pods pod node reason="" recovery_attempted=0

  if ! command -v jq >/dev/null 2>&1; then
    echo "INFRA: Envoy readiness requires jq" >&2
    return 2
  fi

  while :; do
    while ((SECONDS < deadline)); do
      pods=$(envoy_agent_pods || true)
      if [ -z "$pods" ]; then
        reason="no Cilium agent pods found"
      else
        reason=""
        while IFS= read -r pod; do
          [ -n "$pod" ] || continue
          if ! envoy_gateway_probe "$pod" "$gw" "$ns"; then
            node=$(kubectl get pod "$pod" -n "$ENVOY_READINESS_NAMESPACE" \
              -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
            reason="${pod} (${node:-unknown}): ${ENVOY_READINESS_REASON}"
            break
          fi
        done <<EOF
$pods
EOF
      fi

      if [ -z "$reason" ]; then
        echo "PASS: Envoy Gateway ${ns}/${gw} listener, route, and ingress policy are ready"
        return 0
      fi
      echo "  Envoy not ready, retrying in 1s (${reason})..." >&2
      sleep 1
    done

    if [ "${AUTO_RECOVER_CILIUM_ENVOY:-0}" = "1" ] && [ "$recovery_attempted" -eq 0 ]; then
      recovery_attempted=1
      echo "WARN: Envoy readiness timed out; restarting cilium-envoy once for local recovery" >&2
      if kubectl rollout restart daemonset/cilium-envoy -n "$ENVOY_READINESS_NAMESPACE" &&
        kubectl rollout status daemonset/cilium-envoy -n "$ENVOY_READINESS_NAMESPACE" \
          --timeout="${ENVOY_RECOVERY_TIMEOUT:-120}s"; then
        deadline=$((SECONDS + timeout))
        continue
      fi
      echo "INFRA: cilium-envoy recovery rollout failed" >&2
    fi

    echo "INFRA: Envoy Gateway ${ns}/${gw} did not converge after ${timeout}s (${reason})" >&2
    envoy_readiness_diagnostics "$gw" "$ns"
    return 2
  done
}

# envoy_gateway_resources_gone <gateway> <namespace>
#
# Return success only when generated Kubernetes resources, the cloud-provider-
# kind proxy, and Envoy's qualified listener/route names are all gone.
envoy_gateway_resources_gone() {
  local gw="$1" ns="$2"
  local service="cilium-gateway-${gw}"
  local gateway_label="${KIND_CLUSTER_NAME:-k8s-cilium-gapi}/${ns}/${gw}"
  local pod listeners routes

  if kubectl get svc "$service" -n "$ns" >/dev/null 2>&1; then
    return 1
  fi
  if kubectl get cec "$service" -n "$ns" >/dev/null 2>&1; then
    return 1
  fi
  if docker ps -aq --filter "label=${ENVOY_GATEWAY_LABEL}=${gateway_label}" | grep -q .; then
    return 1
  fi

  while IFS= read -r pod; do
    [ -n "$pod" ] || continue
    listeners=$(envoy_exec "$pod" cilium-dbg envoy admin listeners -o json 2>/dev/null) || return 1
    if printf '%s\n' "$listeners" | grep -F "cilium-gateway-${gw}" >/dev/null; then
      return 1
    fi
    routes=$(envoy_exec "$pod" cilium-dbg envoy admin config routes \
      -n "$service" 2>/dev/null) || return 1
    if printf '%s\n' "$routes" | grep -F "cilium-gateway-${gw}" >/dev/null; then
      return 1
    fi
  done <<EOF
$(envoy_agent_pods || true)
EOF

  return 0
}

# envoy_wait_gateway_resources_gone <gateway> <namespace> [timeout_seconds]
envoy_wait_gateway_resources_gone() {
  local gw="$1" ns="$2" timeout="${3:-${ENVOY_TEARDOWN_TIMEOUT:-30}}"
  local deadline=$((SECONDS + timeout))

  while ((SECONDS < deadline)); do
    if envoy_gateway_resources_gone "$gw" "$ns"; then
      echo "PASS: Gateway ${ns}/${gw} resources and Envoy state are gone"
      return 0
    fi
    echo "  Gateway ${ns}/${gw} teardown not converged, retrying in 1s..." >&2
    sleep 1
  done

  echo "INFRA: Gateway ${ns}/${gw} teardown did not converge after ${timeout}s" >&2
  envoy_readiness_diagnostics "$gw" "$ns"
  return 2
}

# envoy_assert_http_failure_class <url> <actual_status> <expected_status>
#
# Emit an actionable category for the common failure modes while preserving
# the caller's existing assertion semantics.
envoy_assert_http_failure_class() {
  local url="$1" actual="$2" expected="$3"
  local category

  case "$actual" in
  000) category="CONNECTION/PUBLICATION" ;;
  403) category="CILIUM POLICY" ;;
  404) category="ROUTE" ;;
  503) category="BACKEND" ;;
  *) category="HTTP" ;;
  esac
  echo "FAIL: ${category}: ${url} → HTTP ${actual} (expected ${expected})" >&2
}
