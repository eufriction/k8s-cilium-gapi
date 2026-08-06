#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_on_versions "1.19.1 1.19.3 1.20.0-pre.1" "HTTPS + TLS passthrough same-hostname split-port broken (cilium#44889 + cilium#45371)"
gateway_ports https-tls-split-port-gateway gateway-system 443 9443

# --- Wait for resources ---
# Tier 1 — pods & certificates (parallel)
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/backend-mtls -n backend-b --for=condition=Ready --timeout=${MTLS_POD_READY_TIMEOUT:-60}s" \
  "certificate/https-tls-split-port-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-ca -n backend-b --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-server -n backend-b --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-client -n backend-b --for=condition=Ready --timeout=10s"

# Tier 2 — gateway
wait_gateway https-tls-split-port-gateway gateway-system

# Tier 3 — routes (parallel, manual & + wait)
wait_route httproute backend-a-https-route backend-a &
wait_route tlsroute backend-b-tls-route backend-b &
wait

# --- Listener status assertions ---
assert_listener_status https-tls-split-port-gateway gateway-system https 1 HTTPRoute GRPCRoute
assert_listener_status https-tls-split-port-gateway gateway-system tls 1 TLSRoute

# --- HTTPS termination (api.example.test on port 443) ---
retry_until 10 assert_http "https://api.example.test:${PORT_443}/headers" 200 -k --resolve "api.example.test:${PORT_443}:127.0.0.1"
echo "PASS: HTTPS termination — api.example.test on port 443"

# --- TLS passthrough with mTLS (api.example.test on port 9443) ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

kubectl get secret backend-b-mtls-server -n backend-b -o jsonpath='{.data.ca\.crt}' | base64 -d >"$TMPDIR/b-ca.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.crt}' | base64 -d >"$TMPDIR/b-client.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.key}' | base64 -d >"$TMPDIR/b-client.key"

curl -fsS --resolve "api.example.test:${PORT_9443}:127.0.0.1" \
  --cacert "$TMPDIR/b-ca.crt" --cert "$TMPDIR/b-client.crt" --key "$TMPDIR/b-client.key" \
  https://api.example.test:"${PORT_9443}"/ >/dev/null
echo "PASS: TLS passthrough — api.example.test mTLS on port 9443"

# --- Status message checks ---
msg=$(kubectl get tlsroute/backend-b-tls-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_TLSROUTE_ACCEPTED_MSG" "backend-b-tls-route"
