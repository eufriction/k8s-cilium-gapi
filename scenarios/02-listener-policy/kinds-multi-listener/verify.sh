#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
kubectl wait pod/api -n backend-a --for=condition=Ready --timeout=60s
kubectl wait pod/api -n backend-b --for=condition=Ready --timeout=60s
kubectl wait pod/grpc-api -n backend-a --for=condition=Ready --timeout=60s
kubectl wait pod/grpc-api -n backend-b --for=condition=Ready --timeout=60s
kubectl wait pod/backend-mtls -n backend-a --for=condition=Ready --timeout=60s
kubectl wait pod/netshoot-client -n client --for=condition=Ready --timeout=60s
kubectl wait certificate/kind-restricted-gateway-certificate -n gateway-system --for=condition=Ready --timeout=180s
kubectl wait certificate/backend-a-mtls-ca -n backend-a --for=condition=Ready --timeout=180s
kubectl wait certificate/backend-a-mtls-server -n backend-a --for=condition=Ready --timeout=180s
kubectl wait certificate/backend-a-mtls-client -n backend-a --for=condition=Ready --timeout=180s
kubectl wait gateway/kind-restricted-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=120s

echo "--- Checking route acceptance (4 listeners, per-listener kind restrictions) ---"

route_fail=0

if ! kubectl wait httproute/http-redirect -n gateway-system --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s 2>/dev/null; then
  echo "FAIL: HTTPRoute http-redirect NOT accepted by http listener"
  echo "  reason: $(kubectl get httproute http-redirect -n gateway-system -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].reason}')"
  echo "  message: $(kubectl get httproute http-redirect -n gateway-system -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')"
  route_fail=1
else
  echo "PASS: HTTPRoute http-redirect accepted by http listener"
fi

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
  echo "FAIL: GRPCRoute backend-a NOT accepted by grpcs listener"
  echo "  reason: $(kubectl get grpcroute backend-a-grpc-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].reason}')"
  echo "  message: $(kubectl get grpcroute backend-a-grpc-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')"
  route_fail=1
else
  echo "PASS: GRPCRoute backend-a accepted by grpcs listener"
fi

if ! kubectl wait grpcroute/backend-b-grpc-route -n backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s 2>/dev/null; then
  echo "FAIL: GRPCRoute backend-b NOT accepted by grpcs listener"
  echo "  reason: $(kubectl get grpcroute backend-b-grpc-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].reason}')"
  echo "  message: $(kubectl get grpcroute backend-b-grpc-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')"
  route_fail=1
else
  echo "PASS: GRPCRoute backend-b accepted by grpcs listener"
fi

if ! kubectl wait tlsroute/backend-a-tls-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s 2>/dev/null; then
  echo "FAIL: TLSRoute backend-a NOT accepted by tls-passthrough listener"
  echo "  reason: $(kubectl get tlsroute backend-a-tls-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].reason}')"
  echo "  message: $(kubectl get tlsroute backend-a-tls-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')"
  route_fail=1
else
  echo "PASS: TLSRoute backend-a accepted by tls-passthrough listener"
fi

if [ "$route_fail" -eq 1 ]; then
  echo ""
  echo "--- Diagnostic: Gateway listener status ---"
  kubectl get gateway kind-restricted-gateway -n gateway-system -o jsonpath='{range .status.listeners[*]}listener={.name}  attachedRoutes={.attachedRoutes}  supportedKinds={.supportedKinds[*].kind}{"\n"}{end}'
  echo ""
  echo "One or more routes failed to attach. This is caused by"
  echo "  CheckGatewayRouteKindAllowed evaluating all listeners globally"
  echo "  instead of only the listener targeted by sectionName."
  echo "  The tls-passthrough listener (last, kinds=[TLSRoute]) overwrites"
  echo "  the Accepted condition for all other route types."
  echo "  See: https://github.com/cilium/cilium/issues/45559"
  exit 1
fi

echo "--- HTTPS checks (port 443, https listener — HTTPRoute only) ---"
retry 5 2 curl -kfsS --resolve "http-a.http.example.test:443:127.0.0.1" https://http-a.http.example.test/headers >/dev/null
echo "PASS: HTTPS backend-a on port 443"
curl -kfsS --resolve "http-b.http.example.test:443:127.0.0.1" https://http-b.http.example.test/headers >/dev/null
echo "PASS: HTTPS backend-b on port 443"

GRPC_IMPORT_PATH="${REPO_ROOT}/apps/backend-grpc/proto"
GRPC_PROTO=grpc/testing/testservice.proto
GRPC_REQ='{"response_size":32,"fill_server_id":true}'
GRPC_METHOD=grpc.testing.TestService/UnaryCall
ITERATIONS=10

echo "--- gRPC affinity checks (port 443, grpcs listener — GRPCRoute only) ---"

# grpc-a.grpc.example.test must always route to backend-a
misrouted=0
for i in $(seq 1 $ITERATIONS); do
  server_id=$(grpcurl -insecure \
    -authority grpc-a.grpc.example.test \
    -import-path "$GRPC_IMPORT_PATH" \
    -proto "$GRPC_PROTO" \
    -d "$GRPC_REQ" \
    localhost:443 \
    "$GRPC_METHOD" | jq -r '.serverId')
  if [ "$server_id" != "backend-a" ]; then
    echo "  iteration $i: grpc-a.grpc.example.test routed to '$server_id' (expected backend-a)" >&2
    misrouted=$((misrouted + 1))
  fi
done
if [ "$misrouted" -gt 0 ]; then
  echo "FAIL: grpc-a.grpc.example.test mis-routed $misrouted/$ITERATIONS requests" >&2
  exit 1
fi
echo "PASS: grpc-a.grpc.example.test — all $ITERATIONS requests routed to backend-a"

# grpc-b.grpc.example.test must always route to backend-b
misrouted=0
for i in $(seq 1 $ITERATIONS); do
  server_id=$(grpcurl -insecure \
    -authority grpc-b.grpc.example.test \
    -import-path "$GRPC_IMPORT_PATH" \
    -proto "$GRPC_PROTO" \
    -d "$GRPC_REQ" \
    localhost:443 \
    "$GRPC_METHOD" | jq -r '.serverId')
  if [ "$server_id" != "backend-b" ]; then
    echo "  iteration $i: grpc-b.grpc.example.test routed to '$server_id' (expected backend-b)" >&2
    misrouted=$((misrouted + 1))
  fi
done
if [ "$misrouted" -gt 0 ]; then
  echo "FAIL: grpc-b.grpc.example.test mis-routed $misrouted/$ITERATIONS requests" >&2
  exit 1
fi
echo "PASS: grpc-b.grpc.example.test — all $ITERATIONS requests routed to backend-b"

echo "--- HTTP redirect checks (port 80, http listener — no explicit kinds) ---"
http_code=$(retry 5 2 curl -o /dev/null -s -w "%{http_code}" --resolve "http-a.http.example.test:80:127.0.0.1" http://http-a.http.example.test/headers)
if [ "$http_code" != "301" ]; then
  echo "FAIL: HTTP redirect expected 301, got $http_code" >&2
  exit 1
fi
echo "PASS: HTTP redirect on port 80 returns 301"

echo "--- TLS passthrough checks (port 443, tls-passthrough listener — TLSRoute only) ---"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

kubectl get secret backend-a-mtls-server -n backend-a -o jsonpath='{.data.ca\.crt}' | base64 -d > "$TMPDIR/a-ca.crt"
kubectl get secret backend-a-mtls-client -n backend-a -o jsonpath='{.data.tls\.crt}' | base64 -d > "$TMPDIR/a-client.crt"
kubectl get secret backend-a-mtls-client -n backend-a -o jsonpath='{.data.tls\.key}' | base64 -d > "$TMPDIR/a-client.key"

curl -fsS --resolve "tls-a.tls.example.test:443:127.0.0.1" \
  --cacert "$TMPDIR/a-ca.crt" --cert "$TMPDIR/a-client.crt" --key "$TMPDIR/a-client.key" \
  https://tls-a.tls.example.test:443/ >/dev/null
echo "PASS: TLS passthrough — tls-a.tls.example.test mTLS on port 443"
