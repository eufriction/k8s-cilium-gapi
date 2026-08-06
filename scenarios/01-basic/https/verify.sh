#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
gateway_ports https-multi-namespace-gateway gateway-system 443
# Tier 1: pods + certs in parallel
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "certificate/https-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s"
# Tier 2: gateway
wait_gateway https-multi-namespace-gateway gateway-system
# Tier 3: routes in parallel
wait_route httproute backend-a-https-route backend-a &
wait_route httproute backend-b-https-route backend-b &
wait

# --- Listener status assertions ---
assert_listener_status https-multi-namespace-gateway gateway-system https 2 HTTPRoute GRPCRoute

retry_until 10 assert_http "https://https-a.example.test:${PORT_443}/headers" 200 \
  -k --resolve "https-a.example.test:${PORT_443}:127.0.0.1"
assert_http "https://https-b.example.test:${PORT_443}/headers" 200 \
  -k --resolve "https-b.example.test:${PORT_443}:127.0.0.1"

# cilium/cilium#43881
msg=$(kubectl get httproute/backend-a-https-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
[ "$msg" = "Accepted HTTPRoute" ] || {
  echo "FAIL: backend-a-https-route message='$msg'" >&2
  exit 1
}
echo "PASS: backend-a-https-route Accepted message = '$msg'"

msg=$(kubectl get httproute/backend-b-https-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
[ "$msg" = "Accepted HTTPRoute" ] || {
  echo "FAIL: backend-b-https-route message='$msg'" >&2
  exit 1
}
echo "PASS: backend-b-https-route Accepted message = '$msg'"
