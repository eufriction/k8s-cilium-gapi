#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
gateway_ports path-match-gateway gateway-system 80

# Tier 1: pods in parallel
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s"

# Tier 2: gateway
wait_gateway path-match-gateway gateway-system

# Tier 3: routes in parallel
wait_route httproute backend-a-route backend-a &
wait_route httproute backend-b-route backend-b &
wait

# --- Listener status assertions ---
assert_listener_status path-match-gateway gateway-system http 2 HTTPRoute GRPCRoute

# Warm up the HTTP listener
retry_until 10 curl -fsS -H 'Host: app.example.test' http://localhost:"${PORT_80}"/api/headers >/dev/null

# Test 1: /api/* → backend-a
body=$(curl -fsS -H 'Host: app.example.test' http://localhost:"${PORT_80}"/api/headers)
if ! echo "$body" | grep -q '"X-Routed-To"' || ! echo "$body" | grep -q 'backend-a'; then
  echo "FAIL: /api/headers not routed to backend-a" >&2
  exit 1
fi
echo "PASS: /api/headers → backend-a"

# Test 2: /* → backend-b
body=$(curl -fsS -H 'Host: app.example.test' http://localhost:"${PORT_80}"/headers)
if ! echo "$body" | grep -q '"X-Routed-To"' || ! echo "$body" | grep -q 'backend-b'; then
  echo "FAIL: /headers not routed to backend-b" >&2
  exit 1
fi
echo "PASS: /headers → backend-b"

# Test 3: Verify /api prefix takes precedence over / catch-all
body=$(curl -fsS -H 'Host: app.example.test' http://localhost:"${PORT_80}"/api/get)
echo "$body" | grep -q 'backend-a' || {
  echo "FAIL: /api prefix did not take precedence over catch-all" >&2
  exit 1
}
echo "PASS: /api/get → backend-a (prefix takes precedence over catch-all)"
