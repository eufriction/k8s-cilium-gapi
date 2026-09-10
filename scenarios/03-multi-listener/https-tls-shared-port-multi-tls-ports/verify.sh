#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "HTTPS/TLS shared-port multi-port regression requires per-port TLS translation (cilium#44889 + cilium#45371)"
gateway_ports https-tls-shared-port-multi-tls-ports-gateway gateway-system 443 50051 9443

# --- Wait for resources ---
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/backend-mtls -n backend-b --for=condition=Ready --timeout=${MTLS_POD_READY_TIMEOUT:-60}s" \
  "certificate/https-tls-shared-port-multi-tls-ports-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-ca -n backend-b --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-server -n backend-b --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-client -n backend-b --for=condition=Ready --timeout=10s"

# The issue can leave Gateway status healthy while its CEC is rejected, so the
# data-plane assertions below are required in addition to status checks.
wait_gateway https-tls-shared-port-multi-tls-ports-gateway gateway-system

# --- Routes ---
wait_route httproute backend-a-https-route-c backend-a &
wait_route httproute backend-a-https-route-c backend-a ResolvedRefs &
wait_route tlsroute backend-b-tls-route-a backend-b &
wait_route tlsroute backend-b-tls-route-a backend-b ResolvedRefs &
wait_route tlsroute backend-b-tls-route-b backend-b &
wait_route tlsroute backend-b-tls-route-b backend-b ResolvedRefs &
wait_route tlsroute backend-b-tls-route-d backend-b &
wait_route tlsroute backend-b-tls-route-d backend-b ResolvedRefs &
wait

# --- Listener status assertions ---
assert_listener_status https-tls-shared-port-multi-tls-ports-gateway gateway-system https-c 1 HTTPRoute GRPCRoute
assert_listener_status https-tls-shared-port-multi-tls-ports-gateway gateway-system tls-a 1 TLSRoute
assert_listener_status https-tls-shared-port-multi-tls-ports-gateway gateway-system tls-b 1 TLSRoute
assert_listener_status https-tls-shared-port-multi-tls-ports-gateway gateway-system tls-d 1 TLSRoute

echo "PASS: all four listeners report one attached route"

# --- HTTPS termination on the shared port ---
retry_until 10 assert_http "https://web.example.test:${PORT_443}/headers" 200 \
  -k --resolve "web.example.test:${PORT_443}:127.0.0.1"
echo "PASS: HTTPS termination — web.example.test on port 443"

# --- TLS passthrough on the two independent ports and shared port ---
CERT_DIR=$(mktemp -d)
trap 'rm -rf "$CERT_DIR"' EXIT

kubectl get secret backend-b-mtls-server -n backend-b -o jsonpath='{.data.ca\.crt}' | base64 -d >"$CERT_DIR/b-ca.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.crt}' | base64 -d >"$CERT_DIR/b-client.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.key}' | base64 -d >"$CERT_DIR/b-client.key"

retry_until 10 curl -fsS --resolve "api.example.test:${PORT_50051}:127.0.0.1" \
  --cacert "$CERT_DIR/b-ca.crt" --cert "$CERT_DIR/b-client.crt" --key "$CERT_DIR/b-client.key" \
  "https://api.example.test:${PORT_50051}/" >/dev/null
echo "PASS: TLS passthrough — api.example.test on port 50051"

retry_until 10 curl -fsS --resolve "tls.example.test:${PORT_9443}:127.0.0.1" \
  --cacert "$CERT_DIR/b-ca.crt" --cert "$CERT_DIR/b-client.crt" --key "$CERT_DIR/b-client.key" \
  "https://tls.example.test:${PORT_9443}/" >/dev/null
echo "PASS: TLS passthrough — tls.example.test on port 9443"

retry_until 10 curl -fsS --resolve "mtls-b.example.test:${PORT_443}:127.0.0.1" \
  --cacert "$CERT_DIR/b-ca.crt" --cert "$CERT_DIR/b-client.crt" --key "$CERT_DIR/b-client.key" \
  "https://mtls-b.example.test:${PORT_443}/" >/dev/null
echo "PASS: TLS passthrough — mtls-b.example.test on port 443"

# --- Status message checks ---
for route in backend-b-tls-route-a backend-b-tls-route-b backend-b-tls-route-d; do
  msg=$(kubectl get "tlsroute/${route}" -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
  assert_msg "$msg" "X_TLSROUTE_ACCEPTED_MSG" "$route"
done
