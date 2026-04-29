#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

# --- Wait for resources ---
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=5s" \
  "certificate/ns-shared-port-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s"
kubectl wait gateway/ns-shared-port-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=5s

# Give the controller time to reconcile route status
sleep 5

# --- Listener status assertions ---
assert_listener_status ns-shared-port-gateway gateway-system https-restricted 0 HTTPRoute GRPCRoute
assert_listener_status ns-shared-port-gateway gateway-system https-open       1 HTTPRoute GRPCRoute

# --- Traffic check on open listener ---
retry_until 10 curl -kfsS --resolve "open.example.test:443:127.0.0.1" https://open.example.test/headers >/dev/null
echo "PASS: HTTPS traffic to open.example.test on port 443"
