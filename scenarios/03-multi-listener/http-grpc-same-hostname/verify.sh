#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "same-hostname split-port gRPC bug — not yet fixed upstream"
gateway_ports same-hostname-split-ports-gateway gateway-system 443 50051
# Tier 1 — pods & certificates (parallel)
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/grpc-api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/grpc-api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "certificate/same-hostname-split-ports-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s"

# Tier 2 — gateway
wait_gateway same-hostname-split-ports-gateway gateway-system

# Tier 3 — routes (parallel, manual & + wait)
wait_route httproute backend-a-https-route backend-a &
wait_route httproute backend-b-https-route backend-b &
wait_route grpcroute backend-a-grpc-route backend-a &
wait_route grpcroute backend-b-grpc-route backend-b &
wait

# --- Listener status assertions ---
assert_listener_status same-hostname-split-ports-gateway gateway-system https 2 HTTPRoute GRPCRoute
assert_listener_status same-hostname-split-ports-gateway gateway-system grpcs 2 HTTPRoute GRPCRoute

echo "--- HTTPS checks (port 443, hostname api.example.test) ---"
retry_until 10 assert_http "https://api.example.test:${PORT_443}/headers" 200 -k --resolve "api.example.test:${PORT_443}:127.0.0.1"
echo "PASS: HTTPS backend-a on port 443"
assert_http "https://api.example.test:${PORT_443}/b/headers" 200 -k --resolve "api.example.test:${PORT_443}:127.0.0.1"
echo "PASS: HTTPS backend-b on port 443 (path /b)"

GRPC_IMPORT_PATH="${REPO_ROOT}/apps/backend-grpc/proto"
GRPC_PROTO=grpc/testing/testservice.proto
GRPC_REQ='{"response_size":32,"fill_server_id":true}'
GRPC_METHOD=grpc.testing.TestService/UnaryCall
ITERATIONS=20

echo "--- gRPC distribution check (port 50051, same hostname api.example.test) ---"
echo "Two GRPCRoutes share the same hostname — traffic must reach BOTH backends."

retry_until 10 grpcurl -insecure \
  -authority api.example.test \
  -import-path "$GRPC_IMPORT_PATH" \
  -proto "$GRPC_PROTO" \
  -d "$GRPC_REQ" \
  localhost:"${PORT_50051}" \
  "$GRPC_METHOD" >/dev/null
echo "gRPC listener warm-up complete"

seen_a=0
seen_b=0
for i in $(seq 1 $ITERATIONS); do
  server_id=$(grpcurl -insecure \
    -authority api.example.test \
    -import-path "$GRPC_IMPORT_PATH" \
    -proto "$GRPC_PROTO" \
    -d "$GRPC_REQ" \
    localhost:"${PORT_50051}" \
    "$GRPC_METHOD" | jq -r '.serverId')
  case "$server_id" in
  backend-a) seen_a=$((seen_a + 1)) ;;
  backend-b) seen_b=$((seen_b + 1)) ;;
  *) echo "  iteration $i: unexpected server_id '$server_id'" >&2 ;;
  esac
done

echo "  backend-a: $seen_a/$ITERATIONS    backend-b: $seen_b/$ITERATIONS"
if [ "$seen_a" -eq 0 ] || [ "$seen_b" -eq 0 ]; then
  echo "FAIL: gRPC traffic not distributed — one backend received 0 requests" >&2
  echo "  This indicates route merging or a routing bug." >&2
  exit 1
fi
echo "PASS: gRPC traffic distributed across both backends ($seen_a/$seen_b split)"

# --- Negative: per-port listener isolation ---
# The HTTPRoutes (sectionName: https, port 443) define path-prefix routes like
# "/" and "/b".  These must NOT be accessible on the gRPC port (50051), which
# should only serve GRPCRoute method paths.  When Cilium collapses multi-port
# HTTPS listeners into a single envoy listener, the HTTPRoute path prefixes
# leak onto the gRPC port and return 200 (served by the HTTP backend).
#
# With correct per-port routing:
#   404 = no route matched (ideal)
#   415 = gRPC backend's catch-all prefix "/" matched, but rejected the
#         non-gRPC content-type (proves HTTPRoute /b did NOT leak)
#   200 = FAIL — the HTTP backend served the request, meaning the HTTPRoute
#         leaked from port 443 to port 50051 (listener collapse)
http_status=$(curl -kso /dev/null -w '%{http_code}' --resolve "api.example.test:${PORT_50051}:127.0.0.1" https://api.example.test:"${PORT_50051}"/b/headers || true)
if [ "$http_status" = "404" ] || [ "$http_status" = "415" ]; then
  echo "PASS: HTTP path /b returned ${http_status} on gRPC port (per-port isolation — HTTPRoute did not leak)"
elif [ "$http_status" = "200" ]; then
  echo "FAIL: HTTP path /b returned 200 on gRPC port 50051 — listener collapse leaks HTTPRoutes across ports" >&2
  exit 1
else
  echo "FAIL: HTTP path /b returned unexpected HTTP ${http_status} on gRPC port 50051" >&2
  exit 1
fi
