#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
gateway_ports selector-listener-conflict-gateway gateway-system 80

# --- Wait for resources ---
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s"
kubectl wait gateway/selector-listener-conflict-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout="${GW_READY_TIMEOUT:-30}s"

# Give the controller time to reconcile route and listener status.
sleep 5

# --- Listener status assertions ---
# backend-a has expose=true, so the route namespace is allowed by http-selected.
# backend-a does not satisfy http-unselected's DoesNotExist selector, so the
# same route must not attach to that listener even though the route lists both
# listener hostnames and omits sectionName.
assert_listener_status selector-listener-conflict-gateway gateway-system http-selected 1 HTTPRoute GRPCRoute
assert_listener_status selector-listener-conflict-gateway gateway-system http-unselected 0 HTTPRoute GRPCRoute

# --- Positive: selected listener serves the route ---
retry_until 10 curl -fsS -H 'Host: selected.example.test' http://localhost:"${PORT_80}"/headers >/dev/null
echo "PASS: selected.example.test routes through the selector-matching listener"

# --- Negative: unselected listener must not serve the route ---
# This catches listener-level selector leaks where model ingestion treats
# NamespacesFromSelector as allow-all after gateway-level route filtering.
http_status=$(curl -so /dev/null -w '%{http_code}' -H 'Host: unselected.example.test' http://localhost:"${PORT_80}"/headers || true)
if [ "$http_status" = "404" ]; then
  echo "PASS: unselected.example.test returns 404 (route namespace does not match listener selector)"
else
  echo "FAIL: unselected.example.test returned HTTP ${http_status} (expected 404)" >&2
  exit 1
fi
