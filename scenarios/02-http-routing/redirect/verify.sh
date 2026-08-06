#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
gateway_ports redirect-gateway gateway-system 80 443

# Tier 1: pods + certs in parallel
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "certificate/redirect-gateway-certificate -n gateway-system --for=condition=Ready --timeout=30s"

# Tier 2: gateway
wait_gateway redirect-gateway gateway-system

# Tier 3: routes in parallel
wait_route httproute http-redirect gateway-system &
wait_route httproute backend-a-route backend-a &
wait

# --- Listener status assertions ---
assert_listener_status redirect-gateway gateway-system http 1 HTTPRoute GRPCRoute
assert_listener_status redirect-gateway gateway-system https 1 HTTPRoute GRPCRoute

# Warm up the HTTP listener before testing
retry_until 10 curl -fsS -o /dev/null -H 'Host: redirect.example.test' http://localhost:"${PORT_80}"/

# Test 1: HTTP request should get 301 redirect
assert_http "http://localhost:${PORT_80}/" 301 -H 'Host: redirect.example.test'
echo "PASS: HTTP→HTTPS redirect returns 301"

# Test 2: Redirect Location header points to HTTPS
assert_redirect "http://localhost:${PORT_80}/" '^https://' \
  -H 'Host: redirect.example.test'
echo "PASS: redirect Location header is HTTPS"

# Test 3: HTTPS endpoint serves traffic
retry_until 10 curl -kfsS --resolve "redirect.example.test:${PORT_443}:127.0.0.1" https://redirect.example.test:"${PORT_443}"/headers >/dev/null
echo "PASS: HTTPS endpoint serves traffic"

# Test 4: Follow redirect end-to-end
# In LB mode the Location header contains :443 (the service port), but the
# host-mapped port is PORT_443. --connect-to rewrites the connection target
# so curl follows the redirect to 127.0.0.1:PORT_443 instead of :443.
retry_until 10 curl -kLfsS \
  --connect-to "redirect.example.test:443:127.0.0.1:${PORT_443}" \
  --resolve "redirect.example.test:${PORT_80}:127.0.0.1" \
  -H 'Host: redirect.example.test' \
  http://localhost:"${PORT_80}"/headers >/dev/null
echo "PASS: HTTP→HTTPS redirect end-to-end (follow redirects)"
