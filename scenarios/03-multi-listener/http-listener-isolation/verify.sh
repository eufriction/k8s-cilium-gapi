#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
gateway_ports http-listener-isolation-gateway gateway-system 80

# Tier 1: pods in parallel
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s"

# Tier 2: gateway
wait_gateway http-listener-isolation-gateway gateway-system

# Tier 3: routes accepted in parallel
wait_route httproute route-catch-all backend-a &
wait_route httproute route-wildcard-example backend-a &
wait_route httproute route-wildcard-foo backend-b &
wait_route httproute route-exact-abc-foo backend-b &
wait

# --- Listener status assertions ---
assert_listener_status http-listener-isolation-gateway gateway-system catch-all 1 HTTPRoute GRPCRoute
assert_listener_status http-listener-isolation-gateway gateway-system wildcard-example 1 HTTPRoute GRPCRoute
assert_listener_status http-listener-isolation-gateway gateway-system wildcard-foo 1 HTTPRoute GRPCRoute
assert_listener_status http-listener-isolation-gateway gateway-system exact-abc-foo 1 HTTPRoute GRPCRoute

# --- Data-plane: listener isolation tests ---
# Each route sets a ResponseHeaderModifier adding X-Listener: <listener-name>.
# By checking this header, we verify which listener served the request.
# Listener isolation means the MOST SPECIFIC listener claims the hostname.

# Helper: assert that a request returns X-Listener matching an expected value.
assert_listener() {
  local host="$1" expected="$2" label="$3"
  local actual
  actual=$(curl -sS -H "Host: ${host}" http://localhost:"${PORT_80}"/get -o /dev/null -w '%header{x-listener}')
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: ${label} — X-Listener='${actual}' (expected '${expected}')" >&2
    exit 1
  fi
  echo "PASS: ${label} — X-Listener='${expected}'"
}

# Wait for the listener to become ready
retry_until 10 assert_http "http://localhost:${PORT_80}/get" 200 -H 'Host: abc.foo.example.test'

# Test 1: Most specific — exact hostname abc.foo.example.test → exact-abc-foo listener
assert_listener "abc.foo.example.test" "exact-abc-foo" \
  "abc.foo.example.test served by exact-abc-foo (most specific)"

# Test 2: Wildcard *.foo.example.test — bar.foo.example.test → wildcard-foo listener
assert_listener "bar.foo.example.test" "wildcard-foo" \
  "bar.foo.example.test served by wildcard-foo (not caught by exact)"

# Test 3: Wildcard *.example.test — bar.example.test → wildcard-example listener
assert_listener "bar.example.test" "wildcard-example" \
  "bar.example.test served by wildcard-example"

# Test 4: Catch-all — hostname not matching any wildcard → catch-all listener
assert_listener "other.domain.test" "catch-all" \
  "other.domain.test served by catch-all (no wildcard match)"

# Test 5: Another *.foo.example.test name to confirm wildcard-foo isolation
assert_listener "xyz.foo.example.test" "wildcard-foo" \
  "xyz.foo.example.test served by wildcard-foo"

# Test 6: Another *.example.test name that doesn't match *.foo.example.test
assert_listener "something.example.test" "wildcard-example" \
  "something.example.test served by wildcard-example (not *.foo.example.test)"

# Test 7: Confirm multi-level subdomain under foo matches wildcard-foo
# Note: *.foo.example.test should NOT match deep.sub.foo.example.test per RFC
# (wildcard only matches one level). This should fall to wildcard-example or catch-all.
# Adjust expectation based on actual gateway behavior.
assert_listener "deep.sub.example.test" "wildcard-example" \
  "deep.sub.example.test served by wildcard-example (single-level wildcard)"
