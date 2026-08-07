#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_on_versions "1.19.1 1.19.3 1.20.0-pre.1" "TLS passthrough same-hostname split ports broken (cilium#42898)"
gateway_ports tls-passthrough-split-ports-gateway gateway-system 443 9443

# --- Tier 1: pods & certificates (parallel) ---
wait_parallel \
  "pod/backend-mtls -n backend-a --for=condition=Ready --timeout=${MTLS_POD_READY_TIMEOUT:-60}s" \
  "pod/backend-mtls -n backend-b --for=condition=Ready --timeout=${MTLS_POD_READY_TIMEOUT:-60}s" \
  "certificate/backend-a-mtls-ca -n backend-a --for=condition=Ready --timeout=10s" \
  "certificate/backend-a-mtls-server -n backend-a --for=condition=Ready --timeout=10s" \
  "certificate/backend-a-mtls-client -n backend-a --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-ca -n backend-b --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-server -n backend-b --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-client -n backend-b --for=condition=Ready --timeout=10s"

# --- Tier 2: gateway ---
wait_gateway tls-passthrough-split-ports-gateway gateway-system

# --- Tier 3: routes (parallel, manual & + wait) ---
wait_route tlsroute backend-a-tls-route backend-a &
wait_route tlsroute backend-b-tls-route backend-b &
wait

# --- Listener status assertions ---
assert_listener_status tls-passthrough-split-ports-gateway gateway-system tls-443 1 TLSRoute
assert_listener_status tls-passthrough-split-ports-gateway gateway-system tls-9443 1 TLSRoute

# --- Extract certs ---
CERT_DIR=$(mktemp -d)
trap 'rm -rf "$CERT_DIR"' EXIT

kubectl get secret backend-a-mtls-server -n backend-a -o jsonpath='{.data.ca\.crt}' | base64 -d >"$CERT_DIR/a-ca.crt"
kubectl get secret backend-a-mtls-client -n backend-a -o jsonpath='{.data.tls\.crt}' | base64 -d >"$CERT_DIR/a-client.crt"
kubectl get secret backend-a-mtls-client -n backend-a -o jsonpath='{.data.tls\.key}' | base64 -d >"$CERT_DIR/a-client.key"
kubectl get secret backend-b-mtls-server -n backend-b -o jsonpath='{.data.ca\.crt}' | base64 -d >"$CERT_DIR/b-ca.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.crt}' | base64 -d >"$CERT_DIR/b-client.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.key}' | base64 -d >"$CERT_DIR/b-client.key"

# --- TLS passthrough on port 443 → backend-a ---
retry_until 10 curl -fsS --resolve "tls.example.test:${PORT_443}:127.0.0.1" \
  --cacert "$CERT_DIR/a-ca.crt" --cert "$CERT_DIR/a-client.crt" --key "$CERT_DIR/a-client.key" \
  https://tls.example.test:"${PORT_443}"/ >/dev/null
echo "PASS: TLS passthrough — tls.example.test on port 443 → backend-a"

# --- TLS passthrough on port 9443 → backend-b ---
curl -fsS --resolve "tls.example.test:${PORT_9443}:127.0.0.1" \
  --cacert "$CERT_DIR/b-ca.crt" --cert "$CERT_DIR/b-client.crt" --key "$CERT_DIR/b-client.key" \
  https://tls.example.test:"${PORT_9443}"/ >/dev/null
echo "PASS: TLS passthrough — tls.example.test on port 9443 → backend-b"

# --- Status message checks ---
msg=$(kubectl get tlsroute/backend-a-tls-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_TLSROUTE_ACCEPTED_MSG" "backend-a-tls-route"
msg=$(kubectl get tlsroute/backend-b-tls-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_TLSROUTE_ACCEPTED_MSG" "backend-b-tls-route"
