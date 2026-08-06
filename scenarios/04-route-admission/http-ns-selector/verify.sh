#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
gateway_ports selector-ns-gateway gateway-system 80

# --- Wait for resources ---
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s"
wait_gateway selector-ns-gateway gateway-system

# Give the controller time to reconcile route status.
sleep 5

# --- Listener status assertions ---
# Only backend-a has expose=true, so only selector-allowed-route should attach.
assert_listener_status selector-ns-gateway gateway-system http-selector 1 HTTPRoute GRPCRoute

# --- Traffic test for the selected namespace route ---
retry_until 10 curl -fsS -H 'Host: selector-allowed.example.test' http://localhost:"${PORT_80}"/headers >/dev/null
echo "PASS: HTTP traffic to selector-allowed.example.test (namespace label matches selector)"

# --- Negative: non-selected namespace route must not be attached or served ---
assert_http "http://localhost:${PORT_80}/headers" 404 -H 'Host: selector-denied.example.test'
