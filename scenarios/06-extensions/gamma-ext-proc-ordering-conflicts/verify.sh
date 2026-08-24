#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "GAMMA ext_proc ordering conflicts require a branch build"

require_crd ciliumenvoyextprocfilters.cilium.io \
  "run against a branch build with ext_proc support"

namespace=ext-proc-gamma
controller=io.cilium/gateway-controller

assert_service_parent() {
  local kind="$1" route="$2" service="$3" expected_status="$4" expected_reason="$5"
  local json
  json=$(kubectl get "$kind/$route" -n "$namespace" -o json 2>/dev/null) || return 1

  if ! jq -e \
    --arg controller "$controller" \
    --arg service "$service" \
    --arg parent_namespace "$namespace" \
    --arg status "$expected_status" \
    --arg reason "$expected_reason" '
      [
        .status.parents[]?
        | select(
            .controllerName == $controller
            and .parentRef.group == ""
            and .parentRef.kind == "Service"
            and .parentRef.name == $service
            and .parentRef.namespace == $parent_namespace
            and .parentRef.port == 80
          )
        | select(
            ([.conditions[]? | select(.type == "Accepted" and .status == $status and .reason == $reason)] | length) == 1
            and ([.conditions[]? | select(.type == "ResolvedRefs" and .status == "True")] | length) == 1
          )
      ]
      | length == 1
    ' <<<"$json" >/dev/null; then
    echo "FAIL: ${kind}/${route} Service/${service}:80 does not have Accepted=${expected_status}/${expected_reason}" >&2
    jq '.status.parents' <<<"$json" >&2
    return 1
  fi

  echo "PASS: ${kind}/${route} Service/${service}:80 has Accepted=${expected_status}/${expected_reason} and ResolvedRefs=True"
}

restore_route_precedence() {
  local run_status=$? restore_status=0
  trap - EXIT

  if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
    exit "$run_status"
  fi

  echo "--- Restoring staged GAMMA routes ---"
  if ! {
    kubectl delete \
      -f 20-foundation-route.yaml \
      -f 21-multi-parent-routes.yaml \
      --ignore-not-found --wait=true --timeout=60s >/dev/null &&
      sleep 1 &&
      kubectl apply -f 20-foundation-route.yaml >/dev/null &&
      sleep 1 &&
      kubectl apply -f 21-multi-parent-routes.yaml >/dev/null
  }; then
    restore_status=1
    echo "FAIL: could not restore staged GAMMA routes" >&2
  fi

  if ((run_status == 0 && restore_status != 0)); then
    run_status=$restore_status
  fi
  exit "$run_status"
}

foundation_timestamp=$(kubectl get httproute/00-source-a-foundation -n "$namespace" -o jsonpath='{.metadata.creationTimestamp}')
conflict_timestamp=$(kubectl get httproute/http-multi-parent-conflict -n "$namespace" -o jsonpath='{.metadata.creationTimestamp}')
if ! [[ "$foundation_timestamp" < "$conflict_timestamp" ]]; then
  echo "FAIL: source-a foundation route is not older than the multi-parent routes" >&2
  printf '  foundation=%s\n  conflict=%s\n' "$foundation_timestamp" "$conflict_timestamp" >&2
  exit 1
fi
echo "PASS: source-a foundation route has precedence over multi-parent routes"

# source-a has A<B from the older route, so both newer B<A declarations lose.
# source-b sees only the two compatible B<A declarations.
retry_until 30 assert_cec_ext_proc_order source-a "$namespace" "$namespace" order-a order-b
retry_until 30 assert_cec_ext_proc_order source-b "$namespace" "$namespace" order-b order-a
retry_until 30 assert_service_parent httproute 00-source-a-foundation source-a True Accepted

for kind_route in \
  'httproute http-multi-parent-conflict' \
  'grpcroute grpc-multi-parent-conflict'; do
  read -r kind route <<<"$kind_route"
  retry_until 30 assert_service_parent "$kind" "$route" source-a False OrderingConflict
  retry_until 30 assert_service_parent "$kind" "$route" source-b True Accepted
done

echo "PASS: multi-parent HTTPRoute and GRPCRoute status is scoped per source Service"

# Removing source-a's winning declaration must clear only its stale conflict
# status; both source-Service CECs then independently select B,A. Restore the
# staged inputs afterward so standalone :verify remains repeatable.
trap restore_route_precedence EXIT
kubectl delete -f 20-foundation-route.yaml --wait=true --timeout=60s >/dev/null
for kind_route in \
  'httproute http-multi-parent-conflict' \
  'grpcroute grpc-multi-parent-conflict'; do
  read -r kind route <<<"$kind_route"
  retry_until 30 assert_service_parent "$kind" "$route" source-a True Accepted
  retry_until 30 assert_service_parent "$kind" "$route" source-b True Accepted
done
retry_until 30 assert_cec_ext_proc_order source-a "$namespace" "$namespace" order-b order-a
retry_until 30 assert_cec_ext_proc_order source-b "$namespace" "$namespace" order-b order-a

echo "PASS: stale GAMMA OrderingConflict reasons clear independently"
