#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_on_versions "1.19.1 1.19.3 1.20.0-pre.1" "TLSRoute no-sectionName bug — duplicate FilterChains on mixed-listener Gateway (cilium#45050)"

# --- Wait for resources ---
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=5s" \
  "pod/backend-mtls -n backend-b --for=condition=Ready --timeout=5s" \
  "certificate/no-sectionname-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-ca -n backend-b --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-server -n backend-b --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-client -n backend-b --for=condition=Ready --timeout=10s"
kubectl wait gateway/mixed-listener-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=5s
kubectl wait httproute/backend-a-web-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=5s &
kubectl wait httproute/backend-a-web-route -n backend-a --for='jsonpath={.status.parents[1].conditions[?(@.type=="Accepted")].status}=True' --timeout=5s &
kubectl wait tlsroute/backend-b-mtls-route -n backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=5s &
wait

# --- HTTPS termination (web.example.test on port 443) ---
retry_until 10 curl -kfsS --resolve "web.example.test:443:127.0.0.1" https://web.example.test/headers >/dev/null
echo "PASS: HTTPS termination — web.example.test on port 443"

# --- TLS passthrough with mTLS (mtls.example.test on port 443) ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

kubectl get secret backend-b-mtls-server -n backend-b -o jsonpath='{.data.ca\.crt}' | base64 -d > "$TMPDIR/b-ca.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.crt}' | base64 -d > "$TMPDIR/b-client.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.key}' | base64 -d > "$TMPDIR/b-client.key"

curl -fsS --resolve "mtls.example.test:443:127.0.0.1" \
  --cacert "$TMPDIR/b-ca.crt" --cert "$TMPDIR/b-client.crt" --key "$TMPDIR/b-client.key" \
  https://mtls.example.test:443/ >/dev/null
echo "PASS: TLS passthrough — mtls.example.test mTLS on port 443"

# --- HTTP listener (port 80) ---
retry_until 10 curl -fsS -H 'Host: web.example.test' http://localhost/headers >/dev/null
echo "PASS: HTTP — web.example.test on port 80"

# --- TLSRoute parent count assertion ---
# The TLSRoute omits sectionName, so per spec it should only attach to the
# "tls" listener (protocol: TLS). If it also attaches to the HTTP or HTTPS
# listeners, the parent count will be > 1 (cilium#45050).
parent_count=$(kubectl get tlsroute/backend-b-mtls-route -n backend-b -o jsonpath='{.status.parents}' | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
if [ "$parent_count" -eq 1 ]; then
  echo "PASS: TLSRoute has exactly 1 parent (attached to tls listener only)"
else
  echo "FAIL: TLSRoute has $parent_count parents (expected 1 — should only attach to tls listener)" >&2
  exit 1
fi

# --- Status message check ---
msg=$(kubectl get tlsroute/backend-b-mtls-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_TLSROUTE_ACCEPTED_MSG" "backend-b-mtls-route"
