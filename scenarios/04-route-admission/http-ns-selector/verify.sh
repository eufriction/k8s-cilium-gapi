#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
gateway_ports selector-ns-gateway gateway-system 80

# --- Wait for resources ---
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s"
kubectl wait gateway/selector-ns-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout="${GW_READY_TIMEOUT:-30}s"

# Give the controller time to reconcile route status.
sleep 5

# --- Listener status assertions ---
# Only backend-a has expose=true, so only selector-allowed-route should attach.
assert_listener_status selector-ns-gateway gateway-system http-selector 1 HTTPRoute GRPCRoute

# --- Traffic test for the selected namespace route ---
retry_until 10 curl -fsS -H 'Host: selector-allowed.example.test' http://localhost:"${PORT_80}"/headers >/dev/null
echo "PASS: HTTP traffic to selector-allowed.example.test (namespace label matches selector)"

# --- Negative: non-selected namespace route must not be attached or served ---
http_status=$(curl -so /dev/null -w '%{http_code}' -H 'Host: selector-denied.example.test' http://localhost:"${PORT_80}"/headers || true)
if [ "$http_status" = "404" ]; then
  echo "PASS: selector-denied.example.test returns 404 (namespace label does not match selector)"
else
  echo "FAIL: selector-denied.example.test returned HTTP ${http_status} (expected 404)" >&2
  exit 1
fi
