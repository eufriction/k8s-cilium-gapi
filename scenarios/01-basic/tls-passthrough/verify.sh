#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
gateway_ports mtls-multi-namespace-gateway gateway-system 9443
# Tier 1: pods + certs in parallel
wait_parallel \
  "pod/backend-mtls -n backend-a --for=condition=Ready --timeout=${MTLS_POD_READY_TIMEOUT:-60}s" \
  "pod/backend-mtls -n backend-b --for=condition=Ready --timeout=${MTLS_POD_READY_TIMEOUT:-60}s" \
  "certificate/backend-a-mtls-ca -n backend-a --for=condition=Ready --timeout=10s" \
  "certificate/backend-a-mtls-server -n backend-a --for=condition=Ready --timeout=10s" \
  "certificate/backend-a-mtls-client -n backend-a --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-ca -n backend-b --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-server -n backend-b --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-client -n backend-b --for=condition=Ready --timeout=10s"
# Tier 2: gateway
wait_gateway mtls-multi-namespace-gateway gateway-system
# Tier 3: routes in parallel
wait_route tlsroute backend-a-mtls-route backend-a &
wait_route tlsroute backend-b-mtls-route backend-b &
wait

# --- Listener status assertions ---
assert_listener_status mtls-multi-namespace-gateway gateway-system mtls 2 TLSRoute

CERT_DIR=$(mktemp -d)
trap 'rm -rf "$CERT_DIR"' EXIT

kubectl get secret backend-a-mtls-server -n backend-a -o jsonpath='{.data.ca\.crt}' | base64 -d >"$CERT_DIR/a-ca.crt"
kubectl get secret backend-a-mtls-client -n backend-a -o jsonpath='{.data.tls\.crt}' | base64 -d >"$CERT_DIR/a-client.crt"
kubectl get secret backend-a-mtls-client -n backend-a -o jsonpath='{.data.tls\.key}' | base64 -d >"$CERT_DIR/a-client.key"
kubectl get secret backend-b-mtls-server -n backend-b -o jsonpath='{.data.ca\.crt}' | base64 -d >"$CERT_DIR/b-ca.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.crt}' | base64 -d >"$CERT_DIR/b-client.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.key}' | base64 -d >"$CERT_DIR/b-client.key"

retry_until 10 curl -fsS --resolve "mtls-a.example.test:${PORT_9443}:127.0.0.1" \
  --cacert "$CERT_DIR/a-ca.crt" --cert "$CERT_DIR/a-client.crt" --key "$CERT_DIR/a-client.key" \
  https://mtls-a.example.test:"${PORT_9443}"/ >/dev/null
echo "PASS: backend-a accepts correct client cert"

curl -fsS --resolve "mtls-b.example.test:${PORT_9443}:127.0.0.1" \
  --cacert "$CERT_DIR/b-ca.crt" --cert "$CERT_DIR/b-client.crt" --key "$CERT_DIR/b-client.key" \
  https://mtls-b.example.test:"${PORT_9443}"/ >/dev/null
echo "PASS: backend-b accepts correct client cert"

if curl -fsS --resolve "mtls-a.example.test:${PORT_9443}:127.0.0.1" \
  --cacert "$CERT_DIR/a-ca.crt" \
  https://mtls-a.example.test:"${PORT_9443}"/ >/dev/null 2>&1; then
  echo "FAIL: backend-a should reject missing client cert" >&2
  exit 1
fi
echo "PASS: backend-a rejects missing client cert"

if curl -fsS --resolve "mtls-b.example.test:${PORT_9443}:127.0.0.1" \
  --cacert "$CERT_DIR/b-ca.crt" --cert "$CERT_DIR/a-client.crt" --key "$CERT_DIR/a-client.key" \
  https://mtls-b.example.test:"${PORT_9443}"/ >/dev/null 2>&1; then
  echo "FAIL: backend-b should reject cross-namespace client cert" >&2
  exit 1
fi
echo "PASS: backend-b rejects cross-namespace client cert"

# cilium/cilium#43881 — TLSRoute reports "Accepted HTTPRoute" on <= 1.19.x
msg=$(kubectl get tlsroute/backend-a-mtls-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_TLSROUTE_ACCEPTED_MSG" "backend-a-mtls-route"

msg=$(kubectl get tlsroute/backend-b-mtls-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_TLSROUTE_ACCEPTED_MSG" "backend-b-mtls-route"
