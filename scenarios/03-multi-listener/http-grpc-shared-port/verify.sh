#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
gateway_ports shared-port-gateway gateway-system 443
# Tier 1: pods + certs in parallel
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/grpc-api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/grpc-api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "certificate/shared-port-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s"
# Tier 2: gateway
wait_gateway shared-port-gateway gateway-system
# Tier 3: routes in parallel
wait_route httproute backend-a-https-route backend-a &
wait_route httproute backend-b-https-route backend-b &
wait_route grpcroute backend-a-grpc-route backend-a &
wait_route grpcroute backend-b-grpc-route backend-b &
wait

# --- Listener status assertions ---
assert_listener_status shared-port-gateway gateway-system https 4 HTTPRoute GRPCRoute

GRPC_ITERATIONS=10

echo "--- gRPC affinity checks (shared port 443) ---"
retry_until 10 grpc_call backend-grpc.example.test "$PORT_443" >/dev/null
echo "gRPC listener warm-up complete"

# backend-grpc.example.test must always route to backend-a
assert_grpc backend-grpc.example.test "$PORT_443" backend-a

# backend-grpc-b.example.test must always route to backend-b
assert_grpc backend-grpc-b.example.test "$PORT_443" backend-b

echo "--- HTTPS checks (shared port 443) ---"
retry_until 10 assert_http "https://backend.example.test:${PORT_443}/headers" 200 -k --resolve "backend.example.test:${PORT_443}:127.0.0.1"
echo "PASS: HTTPS backend-a on port 443"
assert_http "https://backend-b.example.test:${PORT_443}/headers" 200 -k --resolve "backend-b.example.test:${PORT_443}:127.0.0.1"
echo "PASS: HTTPS backend-b on port 443"

# cilium/cilium#43881 — GRPCRoute Accepted message
msg=$(kubectl get grpcroute/backend-a-grpc-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_GRPCROUTE_ACCEPTED_MSG" "backend-a-grpc-route"

msg=$(kubectl get grpcroute/backend-b-grpc-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_GRPCROUTE_ACCEPTED_MSG" "backend-b-grpc-route"
