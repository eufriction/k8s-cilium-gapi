#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_if X_ALLOWED_ROUTES_SHARED_PORT_BROKEN "shared-port allowedRoutes.kinds bug — GRPCRoute excluded from Envoy config (fixed in 1.19.3)"
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=60s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=60s" \
  "pod/grpc-api -n backend-a --for=condition=Ready --timeout=60s" \
  "pod/grpc-api -n backend-b --for=condition=Ready --timeout=60s" \
  "certificate/shared-port-allowed-routes-gateway-certificate -n gateway-system --for=condition=Ready --timeout=180s"
kubectl wait gateway/shared-port-allowed-routes-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=120s

echo "--- Checking route attachment (allowedRoutes.kinds: HTTPRoute + GRPCRoute) ---"
echo "NOTE: Cilium does not support multiple allowedRoutes.kinds entries on a"
echo "  single listener. Only the first kind is honoured; routes of other kinds"
echo "  are rejected with NotAllowedByListeners."
echo "  Workaround: omit allowedRoutes.kinds (scenario 21) or use separate"
echo "  listeners on different ports (scenario 22)."
echo ""

route_fail=0

if ! kubectl wait httproute/backend-a-https-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s 2>/dev/null; then
  echo "FAIL: HTTPRoute backend-a NOT accepted by https listener"
  echo "  reason: $(kubectl get httproute backend-a-https-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].reason}')"
  echo "  message: $(kubectl get httproute backend-a-https-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')"
  route_fail=1
else
  echo "PASS: HTTPRoute backend-a accepted by https listener"
fi

if ! kubectl wait httproute/backend-b-https-route -n backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s 2>/dev/null; then
  echo "FAIL: HTTPRoute backend-b NOT accepted by https listener"
  echo "  reason: $(kubectl get httproute backend-b-https-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].reason}')"
  echo "  message: $(kubectl get httproute backend-b-https-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')"
  route_fail=1
else
  echo "PASS: HTTPRoute backend-b accepted by https listener"
fi

if ! kubectl wait grpcroute/backend-a-grpc-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s 2>/dev/null; then
  echo "FAIL: GRPCRoute backend-a NOT accepted by https listener"
  echo "  reason: $(kubectl get grpcroute backend-a-grpc-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].reason}')"
  echo "  message: $(kubectl get grpcroute backend-a-grpc-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')"
  route_fail=1
else
  echo "PASS: GRPCRoute backend-a accepted by https listener"
fi

if ! kubectl wait grpcroute/backend-b-grpc-route -n backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s 2>/dev/null; then
  echo "FAIL: GRPCRoute backend-b NOT accepted by https listener"
  echo "  reason: $(kubectl get grpcroute backend-b-grpc-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].reason}')"
  echo "  message: $(kubectl get grpcroute backend-b-grpc-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')"
  route_fail=1
else
  echo "PASS: GRPCRoute backend-b accepted by https listener"
fi

if [ "$route_fail" -eq 1 ]; then
  echo ""
  echo "--- Diagnostic: Gateway listener supportedKinds ---"
  kubectl get gateway shared-port-allowed-routes-gateway -n gateway-system -o jsonpath='{range .status.listeners[*]}listener={.name}  attachedRoutes={.attachedRoutes}  supportedKinds={.supportedKinds[*].kind}{"\n"}{end}'
  echo ""
  echo "One or more routes failed to attach. This is a known Cilium bug:"
  echo "  Cilium only honours the first kind in allowedRoutes.kinds for a single listener."
  echo ""
  echo "Workaround: use scenario 21 (omit allowedRoutes.kinds) or scenario 22 (separate ports)."
  exit 1
fi

GRPC_IMPORT_PATH="${REPO_ROOT}/apps/backend-grpc/proto"
GRPC_PROTO=grpc/testing/testservice.proto
GRPC_REQ='{"response_size":32,"fill_server_id":true}'
GRPC_METHOD=grpc.testing.TestService/UnaryCall
ITERATIONS=10

echo "--- gRPC affinity checks (shared port 443) ---"
retry_until 10 grpcurl -insecure \
  -authority backend-grpc.example.test \
  -import-path "$GRPC_IMPORT_PATH" \
  -proto "$GRPC_PROTO" \
  -d "$GRPC_REQ" \
  localhost:443 \
  "$GRPC_METHOD" >/dev/null
echo "gRPC listener warm-up complete"

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
retry_until 10 curl -kfsS --resolve "backend.example.test:443:127.0.0.1" https://backend.example.test/headers >/dev/null
echo "PASS: HTTPS backend-a on port 443"
curl -kfsS --resolve "backend-b.example.test:443:127.0.0.1" https://backend-b.example.test/headers >/dev/null
echo "PASS: HTTPS backend-b on port 443"
