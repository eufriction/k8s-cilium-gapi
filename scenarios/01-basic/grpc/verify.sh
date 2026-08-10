#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
gateway_ports grpc-multi-namespace-gateway gateway-system 443

# Tier 1: pods + certs in parallel
wait_parallel \
  "pod/grpc-api -n grpc-backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/grpc-api -n grpc-backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "certificate/grpc-multi-namespace-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s"

# Tier 2: gateway
wait_gateway grpc-multi-namespace-gateway gateway-system

# Tier 3: routes in parallel
wait_route grpcroute grpc-backend-a-route grpc-backend-a &
wait_route grpcroute grpc-backend-b-route grpc-backend-b &
wait

# --- Listener status assertions ---
assert_listener_status grpc-multi-namespace-gateway gateway-system grpcs 2 HTTPRoute GRPCRoute

GRPC_ITERATIONS=10

echo "--- gRPC affinity checks (port 443) ---"
retry_until 10 grpc_call grpc-a.example.test "$PORT_443" >/dev/null
echo "gRPC listener warm-up complete"

assert_grpc grpc-a.example.test "$PORT_443" grpc-backend-a

assert_grpc grpc-b.example.test "$PORT_443" grpc-backend-b

# cilium/cilium#43881 — pre-1.19.6 releases report "Accepted HTTPRoute"
msg=$(kubectl get grpcroute/grpc-backend-a-route -n grpc-backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_GRPCROUTE_ACCEPTED_MSG" "grpc-backend-a-route"

msg=$(kubectl get grpcroute/grpc-backend-b-route -n grpc-backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_GRPCROUTE_ACCEPTED_MSG" "grpc-backend-b-route"
