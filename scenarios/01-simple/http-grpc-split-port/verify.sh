#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
# Tier 1: pods + certs in parallel
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=5s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=5s" \
  "pod/grpc-api -n backend-a --for=condition=Ready --timeout=5s" \
  "pod/grpc-api -n backend-b --for=condition=Ready --timeout=5s" \
  "certificate/https-grpc-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s"
# Tier 2: gateway
kubectl wait gateway/https-grpc-multi-namespace-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=5s
# Tier 3: routes in parallel
kubectl wait httproute/backend-a-https-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=5s &
kubectl wait httproute/backend-b-https-route -n backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=5s &
kubectl wait grpcroute/backend-a-grpc-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=5s &
kubectl wait grpcroute/backend-b-grpc-route -n backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=5s &
wait

echo "--- HTTPS smoke checks (port 443) ---"
retry_until 10 curl -kfsS --resolve "https-a.example.test:443:127.0.0.1" https://https-a.example.test/headers >/dev/null
echo "PASS: HTTPS backend-a on port 443"
curl -kfsS --resolve "https-b.example.test:443:127.0.0.1" https://https-b.example.test/headers >/dev/null
echo "PASS: HTTPS backend-b on port 443"

GRPC_IMPORT_PATH="${REPO_ROOT}/apps/backend-grpc/proto"
GRPC_PROTO=grpc/testing/testservice.proto
GRPC_REQ='{"response_size":32,"fill_server_id":true}'
GRPC_METHOD=grpc.testing.TestService/UnaryCall
ITERATIONS=10

echo "--- gRPC affinity checks (port 50051) ---"
retry_until 10 grpcurl -insecure \
  -authority grpc-a.example.test \
  -import-path "$GRPC_IMPORT_PATH" \
  -proto "$GRPC_PROTO" \
  -d "$GRPC_REQ" \
  localhost:50051 \
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
    localhost:50051 \
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
    localhost:50051 \
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
http_status=$(curl -kso /dev/null -w '%{http_code}' --resolve "https-a.example.test:50051:127.0.0.1" https://https-a.example.test:50051/headers || true)
if [ "$http_status" = "404" ]; then
  echo "PASS: HTTP hostname correctly returns 404 on gRPC port (per-port isolation)"
else
  echo "FAIL: HTTP hostname returned HTTP ${http_status} on gRPC port 50051 (expected 404) — listener collapse leaks routes across ports" >&2
  exit 1
fi
