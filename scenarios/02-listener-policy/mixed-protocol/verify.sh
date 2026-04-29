#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_on_versions "1.19.1 1.19.3 1.20.0-pre.1" "mixed-protocol listeners — known broken (cilium#45559)"

# --- Wait for resources ---
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=5s" \
  "pod/backend-mtls -n backend-b --for=condition=Ready --timeout=5s" \
  "certificate/mixed-protocol-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-ca -n backend-b --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-server -n backend-b --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-client -n backend-b --for=condition=Ready --timeout=10s"
kubectl wait gateway/mixed-protocol-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=5s

# --- Route acceptance ---
# When cilium#45559 is present, adding a TLS Passthrough listener causes
# CheckGatewayRouteKindAllowed to globally overwrite the Accepted condition,
# rejecting HTTPRoutes with NotAllowedByListeners.
route_fail=0

kubectl wait httproute/backend-a-app-route -n gateway-system \
  --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=5s || route_fail=1
kubectl wait httproute/http-redirect -n gateway-system \
  --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=5s || route_fail=1
kubectl wait tlsroute/backend-b-mtls-route -n gateway-system \
  --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=5s || route_fail=1

if [ "$route_fail" -ne 0 ]; then
  echo "FAIL: One or more routes not accepted — dumping gateway listener status" >&2
  echo "--- Gateway listener status (supportedKinds) ---" >&2
  kubectl get gateway/mixed-protocol-gateway -n gateway-system -o jsonpath='{range .status.listeners[*]}{.name}: supportedKinds={.supportedKinds} conditions={.conditions}{"\n"}{end}' >&2
  echo "--- HTTPRoute backend-a-app-route status ---" >&2
  kubectl get httproute/backend-a-app-route -n gateway-system -o jsonpath='{.status.parents}' >&2
  echo "" >&2
  echo "--- HTTPRoute http-redirect status ---" >&2
  kubectl get httproute/http-redirect -n gateway-system -o jsonpath='{.status.parents}' >&2
  echo "" >&2
  echo "--- TLSRoute backend-b-mtls-route status ---" >&2
  kubectl get tlsroute/backend-b-mtls-route -n gateway-system -o jsonpath='{.status.parents}' >&2
  echo "" >&2
  echo "See https://github.com/cilium/cilium/issues/45559" >&2
  exit 1
fi
echo "PASS: All routes accepted (no NotAllowedByListeners regression — cilium#45559)"

# --- Listener status assertions ---
# 3 listeners with implicit kinds — catches cilium#45371 isKindAllowed cross-count.
# No explicit allowedRoutes.kinds — only check attachedRoutes (implicit kinds
# may vary by Cilium version).
assert_listener_status mixed-protocol-gateway gateway-system http  1
assert_listener_status mixed-protocol-gateway gateway-system https 1
assert_listener_status mixed-protocol-gateway gateway-system tls   1
echo "PASS: Per-listener attachedRoutes correct (no isKindAllowed cross-count — cilium#45371)"

# --- HTTPS termination (app.example.test on port 443) ---
retry_until 10 curl -kfsS --resolve "app.example.test:443:127.0.0.1" https://app.example.test/headers >/dev/null
echo "PASS: HTTPS termination — app.example.test on port 443"

# --- HTTP → HTTPS redirect (port 80, expect 301) ---
redirect_status=""
end=$((SECONDS + 10))
while (( SECONDS < end )); do
  redirect_status=$(curl -ksS -o /dev/null -w '%{http_code}' \
    --resolve "app.example.test:80:127.0.0.1" \
    http://app.example.test/ 2>/dev/null) && break
  echo "  listener not ready, retrying in 1s..." >&2
  sleep 1
done
if [ "$redirect_status" = "301" ]; then
  echo "PASS: HTTP → HTTPS redirect — app.example.test port 80 returned 301"
else
  echo "FAIL: HTTP → HTTPS redirect — expected 301, got ${redirect_status}" >&2
  exit 1
fi

# --- TLS passthrough with mTLS (mtls.example.test on port 443) ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

kubectl get secret backend-b-mtls-server -n backend-b -o jsonpath='{.data.ca\.crt}' | base64 -d > "$TMPDIR/b-ca.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.crt}' | base64 -d > "$TMPDIR/b-client.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.key}' | base64 -d > "$TMPDIR/b-client.key"

retry_until 10 curl -fsS --resolve "mtls.example.test:443:127.0.0.1" \
  --cacert "$TMPDIR/b-ca.crt" --cert "$TMPDIR/b-client.crt" --key "$TMPDIR/b-client.key" \
  https://mtls.example.test:443/ >/dev/null
echo "PASS: TLS passthrough — mtls.example.test mTLS on port 443"

# --- Status message assertions ---
msg=$(kubectl get httproute/backend-a-app-route -n gateway-system -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_HTTPROUTE_ACCEPTED_MSG" "backend-a-app-route"

msg=$(kubectl get tlsroute/backend-b-mtls-route -n gateway-system -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_TLSROUTE_ACCEPTED_MSG" "backend-b-mtls-route"
