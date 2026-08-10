#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "split-port gRPC bug — not yet fixed upstream"
gateway_ports https-grpc-multi-namespace-gateway gateway-system 443 50051
# Tier 1: pods + certs in parallel
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/grpc-api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/grpc-api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "certificate/https-grpc-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s"
# Tier 2: gateway
wait_gateway https-grpc-multi-namespace-gateway gateway-system
# Tier 3: routes in parallel
wait_route httproute backend-a-https-route backend-a &
wait_route httproute backend-b-https-route backend-b &
wait_route grpcroute backend-a-grpc-route backend-a &
wait_route grpcroute backend-b-grpc-route backend-b &
wait

# --- Listener status assertions ---
assert_listener_status https-grpc-multi-namespace-gateway gateway-system https 2 HTTPRoute GRPCRoute
assert_listener_status https-grpc-multi-namespace-gateway gateway-system grpcs 2 HTTPRoute GRPCRoute

echo "--- HTTPS smoke checks (port 443) ---"
retry_until 10 assert_http "https://https-a.example.test:${PORT_443}/headers" 200 -k --resolve "https-a.example.test:${PORT_443}:127.0.0.1"
echo "PASS: HTTPS backend-a on port 443"
assert_http "https://https-b.example.test:${PORT_443}/headers" 200 -k --resolve "https-b.example.test:${PORT_443}:127.0.0.1"
echo "PASS: HTTPS backend-b on port 443"

GRPC_ITERATIONS=10

echo "--- gRPC affinity checks (port 50051) ---"
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
http_status=$(curl -kso /dev/null -w '%{http_code}' --resolve "https-a.example.test:${PORT_50051}:127.0.0.1" https://https-a.example.test:"${PORT_50051}"/headers || true)
if [ "$http_status" = "404" ]; then
  echo "PASS: HTTP hostname correctly returns 404 on gRPC port (per-port isolation)"
else
  echo "FAIL: HTTP hostname returned HTTP ${http_status} on gRPC port 50051 (expected 404) — listener collapse leaks routes across ports" >&2
  exit 1
fi
