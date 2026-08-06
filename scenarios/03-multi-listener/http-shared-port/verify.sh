#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
gateway_ports http-shared-port-gateway gateway-system 80

# Tier 1: pods in parallel
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s"

# Tier 2: gateway
wait_gateway http-shared-port-gateway gateway-system

# Tier 3: routes in parallel
wait_route httproute backend-a-route backend-a &
wait_route httproute backend-b-route backend-b &
wait

# --- Listener status assertions ---
assert_listener_status http-shared-port-gateway gateway-system http-a 1 HTTPRoute GRPCRoute
assert_listener_status http-shared-port-gateway gateway-system http-b 1 HTTPRoute GRPCRoute

retry_until 10 assert_http "http://localhost:${PORT_80}/headers" 200 -H 'Host: api-a.example.test'
echo "PASS: api-a HTTP"
assert_http "http://localhost:${PORT_80}/headers" 200 -H 'Host: api-b.example.test'
echo "PASS: api-b HTTP"

msg=$(kubectl get httproute/backend-a-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
[ "$msg" = "Accepted HTTPRoute" ] || {
  echo "FAIL: backend-a-route message='$msg'" >&2
  exit 1
}
echo "PASS: backend-a-route Accepted message = '$msg'"

msg=$(kubectl get httproute/backend-b-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
[ "$msg" = "Accepted HTTPRoute" ] || {
  echo "FAIL: backend-b-route message='$msg'" >&2
  exit 1
}
echo "PASS: backend-b-route Accepted message = '$msg'"
