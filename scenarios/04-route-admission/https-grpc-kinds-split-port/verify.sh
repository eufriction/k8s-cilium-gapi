#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_on_versions "1.19.1 1.19.3 1.20.0-pre.1" "separate-port allowedRoutes.kinds bug — HTTPRoute not accepted (not yet fixed upstream)"
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

GRPC_IMPORT_PATH="${REPO_ROOT}/apps/backend-grpc/proto"
GRPC_PROTO=grpc/testing/testservice.proto
GRPC_REQ='{"response_size":32,"fill_server_id":true}'
GRPC_METHOD=grpc.testing.TestService/UnaryCall
ITERATIONS=10

echo "--- gRPC affinity checks (port 50051, kind-restricted to GRPCRoute) ---"
retry_until 10 grpcurl -insecure \
  -authority grpc-a.example.test \
  -import-path "$GRPC_IMPORT_PATH" \
  -proto "$GRPC_PROTO" \
  -d "$GRPC_REQ" \
  localhost:"${PORT_50051}" \
  "$GRPC_METHOD" >/dev/null
echo "gRPC listener warm-up complete"

# grpc-a.example.test must always route to backend-a
misrouted=0
for i in $(seq 1 $ITERATIONS); do
  server_id=$(grpcurl -insecure \
    -authority grpc-a.example.test \
    -import-path "$GRPC_IMPORT_PATH" \
    -proto "$GRPC_PROTO" \
    -d "$GRPC_REQ" \
    localhost:"${PORT_50051}" \
    "$GRPC_METHOD" | jq -r '.serverId')
  if [ "$server_id" != "backend-a" ]; then
    echo "  iteration $i: grpc-a.example.test routed to '$server_id' (expected backend-a)" >&2
    misrouted=$((misrouted + 1))
  fi
done
if [ "$misrouted" -gt 0 ]; then
  echo "FAIL: grpc-a.example.test mis-routed $misrouted/$ITERATIONS requests" >&2
  exit 1
fi
echo "PASS: grpc-a.example.test — all $ITERATIONS requests routed to backend-a"

# grpc-b.example.test must always route to backend-b
misrouted=0
for i in $(seq 1 $ITERATIONS); do
  server_id=$(grpcurl -insecure \
    -authority grpc-b.example.test \
    -import-path "$GRPC_IMPORT_PATH" \
    -proto "$GRPC_PROTO" \
    -d "$GRPC_REQ" \
    localhost:"${PORT_50051}" \
    "$GRPC_METHOD" | jq -r '.serverId')
  if [ "$server_id" != "backend-b" ]; then
    echo "  iteration $i: grpc-b.example.test routed to '$server_id' (expected backend-b)" >&2
    misrouted=$((misrouted + 1))
  fi
done
if [ "$misrouted" -gt 0 ]; then
  echo "FAIL: grpc-b.example.test mis-routed $misrouted/$ITERATIONS requests" >&2
  exit 1
fi
echo "PASS: grpc-b.example.test — all $ITERATIONS requests routed to backend-b"

# --- Negative: per-port listener isolation ---
# HTTP hostnames (sectionName: https, port 443) must NOT be accessible on
# the gRPC port (50051).  When Cilium collapses multi-port HTTPS listeners
# into a single envoy listener, routes leak across ports.
assert_http "https://https-a.example.test:${PORT_50051}/headers" 404 \
  -k --resolve "https-a.example.test:${PORT_50051}:127.0.0.1"
