#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "ext_proc ExtensionRef requires branch build"

# Fast-fail if CiliumEnvoyExtProcFilter CRD is absent — without it the
# per-route ext_proc config is never generated and both filters cannot coexist.
if ! kubectl get crd ciliumenvoyextprocfilters.cilium.io &>/dev/null; then
  echo "FAIL: CiliumEnvoyExtProcFilter CRD not installed — run against a branch build with ext_proc support" >&2
  exit 1
fi

gateway_ports ext-proc-ext-auth-gateway gateway-system 80

HOST=ext-proc-ext-auth.example.test
BASE_URL="http://localhost:${PORT_80}"

# Tier 1: pods and deployments in parallel
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "deployment/coraza-waf-extproc -n gateway-system --for=condition=Available --timeout=30s" \
  "deployment/external-authz -n auth --for=condition=Available --timeout=30s"

# Tier 2: gateway
wait_gateway ext-proc-ext-auth-gateway gateway-system

# Tier 3: route
wait_route httproute ext-proc-ext-auth-route backend-a
kubectl wait httproute/ext-proc-ext-auth-route -n backend-a \
  --for='jsonpath={.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}=True' \
  --timeout="${ROUTE_READY_TIMEOUT:-30}s"

# --- Listener status ---
assert_listener_status ext-proc-ext-auth-gateway gateway-system http 1 HTTPRoute GRPCRoute

# Warm up the HTTP listener with the public path
retry_until 10 curl -fsS -H "Host: ${HOST}" "${BASE_URL}/public/headers" >/dev/null

# Test 1: /public — no filters active, neither WAF nor auth header injected
public_body=$(curl -fsS -H "Host: ${HOST}" "${BASE_URL}/public/headers")
if echo "$public_body" | grep -qi 'x-waf-result'; then
  echo "FAIL: /public unexpectedly has x-waf-result (WAF should not be active on this path)" >&2
  echo "$public_body" >&2
  exit 1
fi
if echo "$public_body" | grep -qi 'x-ext-authz-result'; then
  echo "FAIL: /public unexpectedly has x-ext-authz-result (ExternalAuth should not be active on this path)" >&2
  echo "$public_body" >&2
  exit 1
fi
echo "PASS: /public reaches backend with neither WAF nor ExternalAuth header"

# Test 2: /protected with a valid auth token — both filters must be active.
# The WAF injects x-waf-result and the auth service injects x-ext-authz-result
# as upstream request headers, both visible in go-httpbin /headers output.
body=$(curl -fsS -H "Host: ${HOST}" -H 'X-Authz-Token: allow' "${BASE_URL}/protected/headers")
if ! echo "$body" | grep -qi 'x-waf-result'; then
  echo "FAIL: /protected missing x-waf-result — WAF (ext_proc) filter not active on this rule" >&2
  echo "$body" >&2
  exit 1
fi
if ! echo "$body" | grep -qi 'x-ext-authz-result'; then
  echo "FAIL: /protected missing x-ext-authz-result — ExternalAuth filter not active on this rule" >&2
  echo "$body" >&2
  exit 1
fi
echo "PASS: /protected with auth token — both WAF and ExternalAuth filters active (coexistence confirmed)"

# Test 3: /protected without auth token — ExternalAuth must deny
assert_http "${BASE_URL}/protected/headers" 403 -H "Host: ${HOST}"
echo "PASS: /protected without token denied (HTTP 403)"

# Test 4: /protected with auth token but SQL injection — WAF must block
assert_http "${BASE_URL}/protected/get?q=union+select+1+from+users" 403 \
  -H "Host: ${HOST}" -H 'X-Authz-Token: allow'
