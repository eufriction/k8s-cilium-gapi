#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
gateway_ports header-match-gateway gateway-system 80

# Tier 1: pods in parallel
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s"

# Tier 2: gateway
wait_gateway header-match-gateway gateway-system

# Tier 3: routes in parallel
wait_route httproute backend-a-route backend-a &
wait_route httproute backend-b-route backend-b &
wait

# --- Listener status assertions ---
assert_listener_status header-match-gateway gateway-system http 2 HTTPRoute GRPCRoute

# Warm up the HTTP listener before running tests
retry_until 10 curl -fsS -H 'Host: api.example.test' -H 'X-Version: v1' http://localhost:"${PORT_80}"/headers >/dev/null

# Test 1: X-Version: v1 → backend-a
body=$(curl -fsS -H 'Host: api.example.test' -H 'X-Version: v1' http://localhost:"${PORT_80}"/headers)
if ! echo "$body" | grep -q '"X-Routed-To"' || ! echo "$body" | grep -q 'backend-a'; then
  echo "FAIL: X-Version: v1 not routed to backend-a" >&2
  exit 1
fi
echo "PASS: X-Version: v1 → backend-a"

# Test 2: X-Version: v2 → backend-b
body=$(curl -fsS -H 'Host: api.example.test' -H 'X-Version: v2' http://localhost:"${PORT_80}"/headers)
if ! echo "$body" | grep -q '"X-Routed-To"' || ! echo "$body" | grep -q 'backend-b'; then
  echo "FAIL: X-Version: v2 not routed to backend-b" >&2
  exit 1
fi
echo "PASS: X-Version: v2 → backend-b"

# Test 3: No X-Version header → 404 (no matching route)
assert_http "http://localhost:${PORT_80}/headers" 404 -H 'Host: api.example.test'
echo "PASS: no X-Version header → 404 (no matching route)"
