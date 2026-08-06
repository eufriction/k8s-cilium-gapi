#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
gateway_ports selector-listener-conflict-gateway gateway-system 80

# --- Wait for resources ---
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s"
wait_gateway selector-listener-conflict-gateway gateway-system

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
assert_http "http://localhost:${PORT_80}/headers" 404 -H 'Host: unselected.example.test'
