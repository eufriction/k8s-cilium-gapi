#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "HTTPRoute ExternalAuth requires branch build"
gateway_ports ext-auth-http-gateway gateway-system 443

HOST=ext-auth-http.example.test
BASE_URL="https://${HOST}:${PORT_443}"
RESOLVE="${HOST}:${PORT_443}:127.0.0.1"

# Tier 1: pods + certs in parallel
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "deployment/external-authz -n auth --for=condition=Available --timeout=30s" \
  "certificate/https-ext-auth-http-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s"

# Tier 2: gateway
wait_gateway ext-auth-http-gateway gateway-system

# Tier 3: route
wait_route httproute ext-auth-http-route backend-a

# --- Listener status assertions ---
assert_listener_status ext-auth-http-gateway gateway-system https 1 HTTPRoute GRPCRoute

# Warm up HTTPS listener with the unauthenticated path.
retry_until 10 curl -kfsS --resolve "$RESOLVE" "${BASE_URL}/public/headers" >/dev/null

public_body=$(curl -kfsS --resolve "$RESOLVE" "${BASE_URL}/public/headers")
if echo "$public_body" | grep -qi 'x-ext-authz-result'; then
  echo "FAIL: public path unexpectedly included ExternalAuth result header" >&2
  echo "$public_body" >&2
  exit 1
fi
echo "PASS: /public reaches backend without ExternalAuth header"

assert_http "${BASE_URL}/http-auth/headers" 403 -k --resolve "$RESOLVE"
echo "PASS: /http-auth without token denied (HTTP 403)"

body=$(curl -kfsS --resolve "$RESOLVE" -H 'X-Authz-Token: allow' "${BASE_URL}/http-auth/headers")
if ! echo "$body" | grep -qi 'x-ext-authz-result'; then
  echo "FAIL: /http-auth allowed request missing X-Ext-Authz-Result header" >&2
  echo "$body" >&2
  exit 1
fi
if ! echo "$body" | grep -qi 'allowed-http'; then
  echo "FAIL: /http-auth allowed request missing allowed-http marker" >&2
  echo "$body" >&2
  exit 1
fi
echo "PASS: /http-auth with token allowed and auth result forwarded"

assert_body "${BASE_URL}/http-auth-shared/headers" 'allowed-http' \
  -k --resolve "$RESOLVE" -H 'X-Authz-Token: allow'
echo "PASS: /http-auth-shared reuses HTTP ExternalAuth config"

status_code=$(curl -ksS -o /dev/null -w '%{http_code}' --resolve "$RESOLVE" "${BASE_URL}/http-auth-variant/headers")
if [ "$status_code" != "403" ]; then
  echo "FAIL: /http-auth-variant without variant header returned HTTP ${status_code} (expected 403)" >&2
  exit 1
fi
echo "PASS: /http-auth-variant without variant header denied (HTTP 403)"

assert_body "${BASE_URL}/http-auth-variant/headers" 'allowed-http' \
  -k --resolve "$RESOLVE" -H 'X-Debug-Token: demo'
echo "PASS: /http-auth-variant uses distinct HTTP ExternalAuth config"
