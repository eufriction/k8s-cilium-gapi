#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

# --- Wait for resources ---
kubectl wait pod/api -n backend-a --for=condition=Ready --timeout=60s
kubectl wait pod/backend-mtls -n backend-b --for=condition=Ready --timeout=60s
kubectl wait certificate/scenario-25-gateway-certificate -n gateway-system --for=condition=Ready --timeout=180s
kubectl wait certificate/backend-b-mtls-ca -n backend-b --for=condition=Ready --timeout=180s
kubectl wait certificate/backend-b-mtls-server -n backend-b --for=condition=Ready --timeout=180s
kubectl wait certificate/backend-b-mtls-client -n backend-b --for=condition=Ready --timeout=180s
kubectl wait gateway/https-tls-same-port-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
kubectl wait httproute/backend-a-web-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
kubectl wait tlsroute/backend-b-mtls-route -n backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s

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
# cilium/cilium#43881 — TLSRoute reports "Accepted HTTPRoute" on <= 1.19.x
msg=$(kubectl get tlsroute/backend-b-mtls-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_TLSROUTE_ACCEPTED_MSG" "backend-b-mtls-route"
