#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_on_versions "1.19.1 1.19.3 1.20.0-pre.1" "TLS passthrough same-hostname split ports broken (cilium#42898)"

# --- Tier 1: pods & certificates (parallel) ---
wait_parallel \
  "pod/backend-mtls -n backend-a --for=condition=Ready --timeout=5s" \
  "pod/backend-mtls -n backend-b --for=condition=Ready --timeout=5s" \
  "certificate/backend-a-mtls-ca -n backend-a --for=condition=Ready --timeout=10s" \
  "certificate/backend-a-mtls-server -n backend-a --for=condition=Ready --timeout=10s" \
  "certificate/backend-a-mtls-client -n backend-a --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-ca -n backend-b --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-server -n backend-b --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-client -n backend-b --for=condition=Ready --timeout=10s"

# --- Tier 2: gateway ---
kubectl wait gateway/tls-passthrough-split-ports-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=5s

# --- Tier 3: routes (parallel, manual & + wait) ---
kubectl wait tlsroute/backend-a-tls-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=5s &
kubectl wait tlsroute/backend-b-tls-route -n backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=5s &
wait

# --- Listener status assertions ---
assert_listener_status tls-passthrough-split-ports-gateway gateway-system tls-443  1 TLSRoute
assert_listener_status tls-passthrough-split-ports-gateway gateway-system tls-9443 1 TLSRoute

# --- Extract certs ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

kubectl get secret backend-a-mtls-server -n backend-a -o jsonpath='{.data.ca\.crt}' | base64 -d > "$TMPDIR/a-ca.crt"
kubectl get secret backend-a-mtls-client -n backend-a -o jsonpath='{.data.tls\.crt}' | base64 -d > "$TMPDIR/a-client.crt"
kubectl get secret backend-a-mtls-client -n backend-a -o jsonpath='{.data.tls\.key}' | base64 -d > "$TMPDIR/a-client.key"
kubectl get secret backend-b-mtls-server -n backend-b -o jsonpath='{.data.ca\.crt}' | base64 -d > "$TMPDIR/b-ca.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.crt}' | base64 -d > "$TMPDIR/b-client.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.key}' | base64 -d > "$TMPDIR/b-client.key"

# --- TLS passthrough on port 443 → backend-a ---
retry_until 10 curl -fsS --resolve "tls.example.test:443:127.0.0.1" \
  --cacert "$TMPDIR/a-ca.crt" --cert "$TMPDIR/a-client.crt" --key "$TMPDIR/a-client.key" \
  https://tls.example.test:443/ >/dev/null
echo "PASS: TLS passthrough — tls.example.test on port 443 → backend-a"

# --- TLS passthrough on port 9443 → backend-b ---
curl -fsS --resolve "tls.example.test:9443:127.0.0.1" \
  --cacert "$TMPDIR/b-ca.crt" --cert "$TMPDIR/b-client.crt" --key "$TMPDIR/b-client.key" \
  https://tls.example.test:9443/ >/dev/null
echo "PASS: TLS passthrough — tls.example.test on port 9443 → backend-b"

# --- Status message checks ---
msg=$(kubectl get tlsroute/backend-a-tls-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_TLSROUTE_ACCEPTED_MSG" "backend-a-tls-route"
msg=$(kubectl get tlsroute/backend-b-tls-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
assert_msg "$msg" "X_TLSROUTE_ACCEPTED_MSG" "backend-b-tls-route"
