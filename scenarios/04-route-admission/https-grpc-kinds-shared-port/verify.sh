#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "shared-port allowedRoutes.kinds bug — GRPCRoute excluded from Envoy config (fixed in 1.19.3)"
gateway_ports shared-port-allowed-routes-gateway gateway-system 443
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/grpc-api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/grpc-api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "certificate/shared-port-allowed-routes-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s"
wait_gateway shared-port-allowed-routes-gateway gateway-system

echo "--- Checking route attachment (allowedRoutes.kinds: HTTPRoute + GRPCRoute) ---"
echo "NOTE: Cilium does not support multiple allowedRoutes.kinds entries on a"
echo "  single listener. Only the first kind is honoured; routes of other kinds"
echo "  are rejected with NotAllowedByListeners."
echo "  Workaround: omit allowedRoutes.kinds (scenario 21) or use separate"
echo "  listeners on different ports (scenario 22)."
echo ""

route_fail=0

if ! wait_route httproute backend-a-https-route backend-a 2>/dev/null; then
  echo "FAIL: HTTPRoute backend-a NOT accepted by https listener"
  echo "  reason: $(kubectl get httproute backend-a-https-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].reason}')"
  echo "  message: $(kubectl get httproute backend-a-https-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')"
  route_fail=1
else
  echo "PASS: HTTPRoute backend-a accepted by https listener"
fi

if ! wait_route httproute backend-b-https-route backend-b 2>/dev/null; then
  echo "FAIL: HTTPRoute backend-b NOT accepted by https listener"
  echo "  reason: $(kubectl get httproute backend-b-https-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].reason}')"
  echo "  message: $(kubectl get httproute backend-b-https-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')"
  route_fail=1
else
  echo "PASS: HTTPRoute backend-b accepted by https listener"
fi

if ! wait_route grpcroute backend-a-grpc-route backend-a 2>/dev/null; then
  echo "FAIL: GRPCRoute backend-a NOT accepted by https listener"
  echo "  reason: $(kubectl get grpcroute backend-a-grpc-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].reason}')"
  echo "  message: $(kubectl get grpcroute backend-a-grpc-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')"
  route_fail=1
else
  echo "PASS: GRPCRoute backend-a accepted by https listener"
fi

if ! wait_route grpcroute backend-b-grpc-route backend-b 2>/dev/null; then
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

# --- Listener status assertions ---
assert_listener_status shared-port-allowed-routes-gateway gateway-system https 4 GRPCRoute HTTPRoute

GRPC_ITERATIONS=10

echo "--- gRPC affinity checks (shared port 443) ---"
retry_until 10 grpc_call backend-grpc.example.test "$PORT_443" >/dev/null
echo "gRPC listener warm-up complete"

# backend-grpc.example.test must always route to backend-a
assert_grpc backend-grpc.example.test "$PORT_443" backend-a

# backend-grpc-b.example.test must always route to backend-b
assert_grpc backend-grpc-b.example.test "$PORT_443" backend-b

echo "--- HTTPS checks (shared port 443) ---"
retry_until 10 curl -kfsS --resolve "backend.example.test:${PORT_443}:127.0.0.1" https://backend.example.test:"${PORT_443}"/headers >/dev/null
echo "PASS: HTTPS backend-a on port 443"
curl -kfsS --resolve "backend-b.example.test:${PORT_443}:127.0.0.1" https://backend-b.example.test:"${PORT_443}"/headers >/dev/null
echo "PASS: HTTPS backend-b on port 443"

# cilium/cilium#43881 — GRPCRoute Accepted message
msg=$(kubectl get grpcroute/backend-a-grpc-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_GRPCROUTE_ACCEPTED_MSG" "backend-a-grpc-route"

msg=$(kubectl get grpcroute/backend-b-grpc-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_GRPCROUTE_ACCEPTED_MSG" "backend-b-grpc-route"
