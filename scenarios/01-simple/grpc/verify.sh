#!/usr/bin/env bash
set -euo pipefail
kubectl wait pod/grpc-api -n grpc-backend-a --for=condition=Ready --timeout=60s
kubectl wait pod/grpc-api -n grpc-backend-b --for=condition=Ready --timeout=60s
kubectl wait certificate/grpc-multi-namespace-gateway-certificate -n gateway-system --for=condition=Ready --timeout=180s
kubectl wait gateway/grpc-multi-namespace-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
kubectl wait grpcroute/grpc-backend-a-route -n grpc-backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
kubectl wait grpcroute/grpc-backend-b-route -n grpc-backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s

REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
GRPC_IMPORT_PATH="${REPO_ROOT}/apps/backend-grpc/proto"
GRPC_PROTO=grpc/testing/testservice.proto
GRPC_REQ='{"response_size":32,"fill_server_id":true}'
GRPC_METHOD=grpc.testing.TestService/UnaryCall
ITERATIONS=10

echo "--- gRPC affinity checks (port 443) ---"

misrouted=0
for i in $(seq 1 $ITERATIONS); do
  server_id=$(grpcurl -insecure \
    -authority grpc-a.example.test \
    -import-path "$GRPC_IMPORT_PATH" \
    -proto "$GRPC_PROTO" \
    -d "$GRPC_REQ" \
    localhost:443 \
    "$GRPC_METHOD" | jq -r '.serverId')
  if [ "$server_id" != "grpc-backend-a" ]; then
    echo "  iteration $i: grpc-a routed to '$server_id' (expected grpc-backend-a)" >&2
    misrouted=$((misrouted + 1))
  fi
done
[ "$misrouted" -eq 0 ] || { echo "FAIL: grpc-a mis-routed $misrouted/$ITERATIONS" >&2; exit 1; }
echo "PASS: grpc-a.example.test — all $ITERATIONS requests routed to grpc-backend-a"

misrouted=0
for i in $(seq 1 $ITERATIONS); do
  server_id=$(grpcurl -insecure \
    -authority grpc-b.example.test \
    -import-path "$GRPC_IMPORT_PATH" \
    -proto "$GRPC_PROTO" \
    -d "$GRPC_REQ" \
    localhost:443 \
    "$GRPC_METHOD" | jq -r '.serverId')
  if [ "$server_id" != "grpc-backend-b" ]; then
    echo "  iteration $i: grpc-b routed to '$server_id' (expected grpc-backend-b)" >&2
    misrouted=$((misrouted + 1))
  fi
done
[ "$misrouted" -eq 0 ] || { echo "FAIL: grpc-b mis-routed $misrouted/$ITERATIONS" >&2; exit 1; }
echo "PASS: grpc-b.example.test — all $ITERATIONS requests routed to grpc-backend-b"

# cilium/cilium#43881 — GRPCRoute reports "Accepted HTTPRoute" on <= 1.19.x
msg=$(kubectl get grpcroute/grpc-backend-a-route -n grpc-backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_GRPCROUTE_ACCEPTED_MSG" "grpc-backend-a-route"

msg=$(kubectl get grpcroute/grpc-backend-b-route -n grpc-backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_GRPCROUTE_ACCEPTED_MSG" "grpc-backend-b-route"
