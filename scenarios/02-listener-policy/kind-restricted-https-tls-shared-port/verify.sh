#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_if X_ALLOWED_ROUTES_SEPARATE_PORT_BROKEN "per-listener allowedRoutes.kinds broken — CheckGatewayRouteKindAllowed global overwrite (cilium#45559)"

# --- Wait for resources ---
kubectl wait pod/api -n backend-a --for=condition=Ready --timeout=60s
kubectl wait pod/backend-mtls -n backend-b --for=condition=Ready --timeout=60s
kubectl wait certificate/kind-https-tls-gateway-certificate -n gateway-system --for=condition=Ready --timeout=180s
kubectl wait certificate/backend-b-mtls-ca -n backend-b --for=condition=Ready --timeout=180s
kubectl wait certificate/backend-b-mtls-server -n backend-b --for=condition=Ready --timeout=180s
kubectl wait certificate/backend-b-mtls-client -n backend-b --for=condition=Ready --timeout=180s
kubectl wait gateway/kind-https-tls-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=120s

echo "--- Checking route acceptance ---"
route_fail=0

if ! kubectl wait httproute/backend-a-web-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s 2>/dev/null; then
  echo "FAIL: HTTPRoute backend-a-web-route NOT accepted by https listener"
  echo "  reason: $(kubectl get httproute backend-a-web-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].reason}')"
  echo "  message: $(kubectl get httproute backend-a-web-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')"
  route_fail=1
else
  echo "PASS: HTTPRoute backend-a-web-route accepted by https listener"
fi

if ! kubectl wait tlsroute/backend-b-mtls-route -n backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s 2>/dev/null; then
  echo "FAIL: TLSRoute backend-b-mtls-route NOT accepted by tls listener"
  echo "  reason: $(kubectl get tlsroute backend-b-mtls-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].reason}')"
  echo "  message: $(kubectl get tlsroute backend-b-mtls-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')"
  route_fail=1
else
  echo "PASS: TLSRoute backend-b-mtls-route accepted by tls listener"
fi

if [ "$route_fail" -eq 1 ]; then
  echo ""
  echo "--- Diagnostic: Gateway listener status ---"
  kubectl get gateway kind-https-tls-gateway -n gateway-system -o jsonpath='{range .status.listeners[*]}listener={.name}  attachedRoutes={.attachedRoutes}  supportedKinds={.supportedKinds[*].kind}{"\n"}{end}'
  echo ""
  echo "Per-listener allowedRoutes.kinds not scoped correctly."
  echo "  The tls listener (kinds=[TLSRoute]) overwrites the Accepted condition"
  echo "  for the HTTPRoute on the https listener."
  echo "  See: https://github.com/cilium/cilium/issues/45559"
  exit 1
fi

# --- HTTPS termination (web.example.test on port 443) ---
retry 5 2 curl -kfsS --resolve "web.example.test:443:127.0.0.1" https://web.example.test/headers >/dev/null
echo "PASS: HTTPS termination — web.example.test on port 443"

# --- TLS passthrough with mTLS (mtls-b.example.test on port 443) ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

kubectl get secret backend-b-mtls-server -n backend-b -o jsonpath='{.data.ca\.crt}' | base64 -d > "$TMPDIR/b-ca.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.crt}' | base64 -d > "$TMPDIR/b-client.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.key}' | base64 -d > "$TMPDIR/b-client.key"

curl -fsS --resolve "mtls-b.example.test:443:127.0.0.1" \
  --cacert "$TMPDIR/b-ca.crt" --cert "$TMPDIR/b-client.crt" --key "$TMPDIR/b-client.key" \
  https://mtls-b.example.test:443/ >/dev/null
echo "PASS: TLS passthrough — mtls-b.example.test mTLS on port 443"

# --- Status message checks ---
msg=$(kubectl get tlsroute/backend-b-mtls-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_TLSROUTE_ACCEPTED_MSG" "backend-b-mtls-route"
