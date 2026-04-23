#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_if X_SPLIT_PORT_GRPC_BROKEN "same-hostname split-port gRPC bug — not yet fixed upstream"
kubectl wait pod/api -n backend-a --for=condition=Ready --timeout=60s
kubectl wait pod/api -n backend-b --for=condition=Ready --timeout=60s
kubectl wait pod/grpc-api -n backend-a --for=condition=Ready --timeout=60s
kubectl wait pod/grpc-api -n backend-b --for=condition=Ready --timeout=60s
kubectl wait pod/netshoot-client -n client --for=condition=Ready --timeout=60s
kubectl wait certificate/same-hostname-split-ports-gateway-certificate -n gateway-system --for=condition=Ready --timeout=180s
kubectl wait gateway/same-hostname-split-ports-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
kubectl wait httproute/backend-a-https-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
kubectl wait httproute/backend-b-https-route -n backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
kubectl wait grpcroute/backend-a-grpc-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
kubectl wait grpcroute/backend-b-grpc-route -n backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s

echo "--- HTTPS checks (port 443, hostname api.example.test) ---"
retry 5 2 curl -kfsS --resolve "api.example.test:443:127.0.0.1" https://api.example.test/headers >/dev/null
echo "PASS: HTTPS backend-a on port 443"
curl -kfsS --resolve "api.example.test:443:127.0.0.1" https://api.example.test/b/headers >/dev/null
echo "PASS: HTTPS backend-b on port 443 (path /b)"

GRPC_IMPORT_PATH="${REPO_ROOT}/apps/backend-grpc/proto"
GRPC_PROTO=grpc/testing/testservice.proto
GRPC_REQ='{"response_size":32,"fill_server_id":true}'
GRPC_METHOD=grpc.testing.TestService/UnaryCall
ITERATIONS=20

echo "--- gRPC distribution check (port 50051, same hostname api.example.test) ---"
echo "Two GRPCRoutes share the same hostname — traffic must reach BOTH backends."

seen_a=0
seen_b=0
for i in $(seq 1 $ITERATIONS); do
  server_id=$(grpcurl -insecure \
    -authority api.example.test \
    -import-path "$GRPC_IMPORT_PATH" \
    -proto "$GRPC_PROTO" \
    -d "$GRPC_REQ" \
    localhost:50051 \
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
