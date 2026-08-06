#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "HTTPRoute gRPC ExternalAuth requires branch build"
gateway_ports ext-auth-grpc-gateway gateway-system 443

HOST=ext-auth-grpc.example.test
BASE_URL="https://${HOST}:${PORT_443}"
RESOLVE="${HOST}:${PORT_443}:127.0.0.1"

# Tier 1: pods + certs in parallel
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "deployment/external-authz -n auth --for=condition=Available --timeout=30s" \
  "certificate/https-ext-auth-grpc-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s"

# Tier 2: gateway
wait_gateway ext-auth-grpc-gateway gateway-system

# Tier 3: route
wait_route httproute ext-auth-grpc-route backend-a

# --- Listener status assertions ---
assert_listener_status ext-auth-grpc-gateway gateway-system https 1 HTTPRoute GRPCRoute

# Warm up HTTPS listener with the unauthenticated path.
retry_until 10 curl -kfsS --resolve "$RESOLVE" "${BASE_URL}/public/headers" >/dev/null

public_body=$(curl -kfsS --resolve "$RESOLVE" "${BASE_URL}/public/headers")
if echo "$public_body" | grep -qi 'x-ext-authz-result'; then
  echo "FAIL: public path unexpectedly included ExternalAuth result header" >&2
  echo "$public_body" >&2
  exit 1
fi
echo "PASS: /public reaches backend without ExternalAuth header"

assert_http "${BASE_URL}/grpc-auth/headers" 403 -k --resolve "$RESOLVE"
echo "PASS: /grpc-auth without token denied (HTTP 403)"

body=$(curl -kfsS --resolve "$RESOLVE" -H 'X-Authz-Token: allow' "${BASE_URL}/grpc-auth/headers")
if ! echo "$body" | grep -qi 'x-ext-authz-result'; then
  echo "FAIL: /grpc-auth allowed request missing X-Ext-Authz-Result header" >&2
  echo "$body" >&2
  exit 1
fi
if ! echo "$body" | grep -qi 'allowed-grpc'; then
  echo "FAIL: /grpc-auth allowed request missing allowed-grpc marker" >&2
  echo "$body" >&2
  exit 1
fi
echo "PASS: /grpc-auth with token allowed and gRPC auth result forwarded"

assert_body "${BASE_URL}/grpc-auth-shared/headers" 'allowed-grpc' \
  -k --resolve "$RESOLVE" -H 'X-Authz-Token: allow'
echo "PASS: /grpc-auth-shared reuses gRPC ExternalAuth config"
