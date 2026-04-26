#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
# Tier 1: pods + certs in parallel
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=60s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=60s" \
  "pod/grpc-api -n backend-a --for=condition=Ready --timeout=60s" \
  "pod/grpc-api -n backend-b --for=condition=Ready --timeout=60s" \
  "pod/netshoot-client -n client --for=condition=Ready --timeout=60s" \
  "certificate/shared-port-gateway-certificate -n gateway-system --for=condition=Ready --timeout=180s"
# Tier 2: gateway
kubectl wait gateway/shared-port-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
# Tier 3: routes in parallel
kubectl wait httproute/backend-a-https-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s &
kubectl wait httproute/backend-b-https-route -n backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s &
kubectl wait grpcroute/backend-a-grpc-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s &
kubectl wait grpcroute/backend-b-grpc-route -n backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s &
wait

GRPC_IMPORT_PATH="${REPO_ROOT}/apps/backend-grpc/proto"
GRPC_PROTO=grpc/testing/testservice.proto
GRPC_REQ='{"response_size":32,"fill_server_id":true}'
GRPC_METHOD=grpc.testing.TestService/UnaryCall
ITERATIONS=10

echo "--- gRPC affinity checks (shared port 443) ---"

# backend-grpc.example.test must always route to backend-a
misrouted=0
for i in $(seq 1 $ITERATIONS); do
  server_id=$(grpcurl -insecure \
    -authority backend-grpc.example.test \
    -import-path "$GRPC_IMPORT_PATH" \
    -proto "$GRPC_PROTO" \
    -d "$GRPC_REQ" \
    localhost:443 \
    "$GRPC_METHOD" | jq -r '.serverId')
  if [ "$server_id" != "backend-a" ]; then
    echo "  iteration $i: backend-grpc.example.test routed to '$server_id' (expected backend-a)" >&2
    misrouted=$((misrouted + 1))
  fi
done
if [ "$misrouted" -gt 0 ]; then
  echo "FAIL: backend-grpc.example.test mis-routed $misrouted/$ITERATIONS requests" >&2
  exit 1
fi
echo "PASS: backend-grpc.example.test — all $ITERATIONS requests routed to backend-a"

# backend-grpc-b.example.test must always route to backend-b
misrouted=0
for i in $(seq 1 $ITERATIONS); do
  server_id=$(grpcurl -insecure \
    -authority backend-grpc-b.example.test \
    -import-path "$GRPC_IMPORT_PATH" \
    -proto "$GRPC_PROTO" \
    -d "$GRPC_REQ" \
    localhost:443 \
    "$GRPC_METHOD" | jq -r '.serverId')
  if [ "$server_id" != "backend-b" ]; then
    echo "  iteration $i: backend-grpc-b.example.test routed to '$server_id' (expected backend-b)" >&2
    misrouted=$((misrouted + 1))
  fi
done
if [ "$misrouted" -gt 0 ]; then
  echo "FAIL: backend-grpc-b.example.test mis-routed $misrouted/$ITERATIONS requests" >&2
  exit 1
fi
echo "PASS: backend-grpc-b.example.test — all $ITERATIONS requests routed to backend-b"

echo "--- HTTPS checks (shared port 443) ---"
retry_until 5 curl -kfsS --resolve "backend.example.test:443:127.0.0.1" https://backend.example.test/headers >/dev/null
echo "PASS: HTTPS backend-a on port 443"
curl -kfsS --resolve "backend-b.example.test:443:127.0.0.1" https://backend-b.example.test/headers >/dev/null
echo "PASS: HTTPS backend-b on port 443"
