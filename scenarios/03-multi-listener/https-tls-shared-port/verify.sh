#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
gateway_ports https-tls-same-port-gateway gateway-system 443

# --- Tier 1: pods + certs in parallel ---
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/backend-mtls -n backend-b --for=condition=Ready --timeout=${MTLS_POD_READY_TIMEOUT:-60}s" \
  "certificate/https-tls-shared-port-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-ca -n backend-b --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-server -n backend-b --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-client -n backend-b --for=condition=Ready --timeout=10s"

# --- Tier 2: gateway ---
wait_gateway https-tls-same-port-gateway gateway-system

# --- Tier 3: routes in parallel ---
wait_route httproute backend-a-web-route backend-a &
wait_route tlsroute backend-b-mtls-route backend-b &
wait

# --- Listener status assertions ---
# Catches cilium#45371: isKindAllowed cross-counts TLSRoute on HTTPS listener.
# No explicit allowedRoutes.kinds — only check attachedRoutes (implicit kinds
# may vary by Cilium version).
assert_listener_status https-tls-same-port-gateway gateway-system https 1
assert_listener_status https-tls-same-port-gateway gateway-system tls 1
echo "PASS: Per-listener attachedRoutes correct (no isKindAllowed cross-count — cilium#45371)"

# --- HTTPS termination (web.example.test on port 443) ---
retry_until 10 assert_http "https://web.example.test:${PORT_443}/headers" 200 -k --resolve "web.example.test:${PORT_443}:127.0.0.1"
echo "PASS: HTTPS termination — web.example.test on port 443"

# --- TLS passthrough with mTLS (mtls-b.example.test on port 443) ---
CERT_DIR=$(mktemp -d)
trap 'rm -rf "$CERT_DIR"' EXIT

kubectl get secret backend-b-mtls-server -n backend-b -o jsonpath='{.data.ca\.crt}' | base64 -d >"$CERT_DIR/b-ca.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.crt}' | base64 -d >"$CERT_DIR/b-client.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.key}' | base64 -d >"$CERT_DIR/b-client.key"

retry_until 10 curl -fsS --resolve "mtls-b.example.test:${PORT_443}:127.0.0.1" \
  --cacert "$CERT_DIR/b-ca.crt" --cert "$CERT_DIR/b-client.crt" --key "$CERT_DIR/b-client.key" \
  https://mtls-b.example.test:"${PORT_443}"/ >/dev/null
echo "PASS: TLS passthrough — mtls-b.example.test mTLS on port 443"

# --- Status message checks ---
# cilium/cilium#43881 — pre-1.19.6 releases report "Accepted HTTPRoute"
msg=$(kubectl get tlsroute/backend-b-mtls-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_TLSROUTE_ACCEPTED_MSG" "backend-b-mtls-route"
