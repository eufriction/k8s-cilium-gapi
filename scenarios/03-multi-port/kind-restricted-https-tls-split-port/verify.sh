#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_if X_ALLOWED_ROUTES_SEPARATE_PORT_BROKEN "kind-restricted HTTPS+TLS split-port broken (cilium#45559 + cilium#44889 + cilium#45371)"

# --- Wait for resources ---
kubectl wait pod/api -n backend-a --for=condition=Ready --timeout=60s
kubectl wait pod/backend-mtls -n backend-b --for=condition=Ready --timeout=60s
kubectl wait certificate/kind-restricted-split-port-gateway-certificate -n gateway-system --for=condition=Ready --timeout=180s
kubectl wait certificate/backend-b-mtls-ca -n backend-b --for=condition=Ready --timeout=180s
kubectl wait certificate/backend-b-mtls-server -n backend-b --for=condition=Ready --timeout=180s
kubectl wait certificate/backend-b-mtls-client -n backend-b --for=condition=Ready --timeout=180s
kubectl wait gateway/kind-restricted-https-tls-split-port-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
kubectl wait httproute/backend-a-https-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
kubectl wait tlsroute/backend-b-tls-route -n backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s

# --- HTTPS termination (api.example.test on port 443, kinds: [HTTPRoute]) ---
retry 5 2 curl -kfsS --resolve "api.example.test:443:127.0.0.1" https://api.example.test/headers >/dev/null
echo "PASS: HTTPS termination — api.example.test on port 443 (kind-restricted to HTTPRoute)"

# --- TLS passthrough with mTLS (api.example.test on port 9443, kinds: [TLSRoute]) ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

kubectl get secret backend-b-mtls-server -n backend-b -o jsonpath='{.data.ca\.crt}' | base64 -d > "$TMPDIR/b-ca.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.crt}' | base64 -d > "$TMPDIR/b-client.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.key}' | base64 -d > "$TMPDIR/b-client.key"

curl -fsS --resolve "api.example.test:9443:127.0.0.1" \
  --cacert "$TMPDIR/b-ca.crt" --cert "$TMPDIR/b-client.crt" --key "$TMPDIR/b-client.key" \
  https://api.example.test:9443/ >/dev/null
echo "PASS: TLS passthrough — api.example.test mTLS on port 9443 (kind-restricted to TLSRoute)"

# --- Status message checks ---
msg=$(kubectl get tlsroute/backend-b-tls-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_TLSROUTE_ACCEPTED_MSG" "backend-b-tls-route"
