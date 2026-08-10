#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "separate-port allowedRoutes.kinds bug — HTTPRoute not accepted (not yet fixed upstream)"
gateway_ports allowed-routes-gateway gateway-system 443 50051
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/grpc-api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/grpc-api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "certificate/allowed-routes-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s"
wait_gateway allowed-routes-gateway gateway-system
wait_route httproute backend-a-https-route backend-a &
wait_route httproute backend-b-https-route backend-b &
wait_route grpcroute backend-a-grpc-route backend-a &
wait_route grpcroute backend-b-grpc-route backend-b &
wait

# --- Listener status assertions ---
# Explicit allowedRoutes.kinds on split ports — assert counts and kinds.
assert_listener_status allowed-routes-gateway gateway-system https 2 HTTPRoute
assert_listener_status allowed-routes-gateway gateway-system grpcs 2 GRPCRoute
echo "PASS: Per-listener attachedRoutes and supportedKinds correct"

echo "--- HTTPS checks (port 443, kind-restricted to HTTPRoute) ---"
retry_until 10 curl -kfsS --resolve "https-a.example.test:${PORT_443}:127.0.0.1" https://https-a.example.test:"${PORT_443}"/headers >/dev/null
echo "PASS: HTTPS backend-a on port 443"
curl -kfsS --resolve "https-b.example.test:${PORT_443}:127.0.0.1" https://https-b.example.test:"${PORT_443}"/headers >/dev/null
echo "PASS: HTTPS backend-b on port 443"

GRPC_ITERATIONS=10

echo "--- gRPC affinity checks (port 50051, kind-restricted to GRPCRoute) ---"
retry_until 10 grpc_call grpc-a.example.test "$PORT_50051" >/dev/null
echo "gRPC listener warm-up complete"

# grpc-a.example.test must always route to backend-a
assert_grpc grpc-a.example.test "$PORT_50051" backend-a

# grpc-b.example.test must always route to backend-b
assert_grpc grpc-b.example.test "$PORT_50051" backend-b

# --- Negative: per-port listener isolation ---
# HTTP hostnames (sectionName: https, port 443) must NOT be accessible on
# the gRPC port (50051).  When Cilium collapses multi-port HTTPS listeners
# into a single envoy listener, routes leak across ports.
assert_http "https://https-a.example.test:${PORT_50051}/headers" 404 \
  -k --resolve "https-a.example.test:${PORT_50051}:127.0.0.1"

# cilium/cilium#43881 — GRPCRoute Accepted message
msg=$(kubectl get grpcroute/backend-a-grpc-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_GRPCROUTE_ACCEPTED_MSG" "backend-a-grpc-route"

msg=$(kubectl get grpcroute/backend-b-grpc-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_GRPCROUTE_ACCEPTED_MSG" "backend-b-grpc-route"
