#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "ext_proc ExtensionRef requires branch build"
gateway_ports waf-gateway gateway-system 80

# Tier 1: pods
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "deployment/coraza-waf-extproc -n gateway-system --for=condition=Available --timeout=30s"

# Tier 2: gateway
kubectl wait gateway/waf-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout="${GW_READY_TIMEOUT:-30}s"

# Tier 3: route
kubectl wait httproute/waf-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout="${ROUTE_READY_TIMEOUT:-30}s"

# --- Listener status assertions ---
assert_listener_status waf-gateway gateway-system http 1 HTTPRoute GRPCRoute

# Warm up the HTTP listener
retry_until 10 curl -fsS -H 'Host: app.example.test' http://localhost:"${PORT_80}"/headers >/dev/null

# Test 1: Clean request passes through WAF
body=$(curl -fsS -H 'Host: app.example.test' http://localhost:"${PORT_80}"/headers)
if ! echo "$body" | grep -qi 'x-waf-result'; then
  echo "FAIL: clean request missing x-waf-result header (WAF not processing)" >&2
  echo "$body" >&2
  exit 1
fi
echo "PASS: clean request passed through WAF (x-waf-result header present)"

# Test 2: SQL injection is blocked by WAF
status_code=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: app.example.test' "http://localhost:${PORT_80}/get?q=union+select+1+from+users")
if [ "$status_code" != "403" ]; then
  echo "FAIL: SQL injection not blocked (got HTTP ${status_code}, expected 403)" >&2
  exit 1
fi
echo "PASS: SQL injection blocked by WAF (HTTP 403)"

# Test 3: XSS attempt is blocked by WAF
status_code=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: app.example.test' "http://localhost:${PORT_80}/get?q=<script>alert(1)</script>")
if [ "$status_code" != "403" ]; then
  echo "FAIL: XSS not blocked (got HTTP ${status_code}, expected 403)" >&2
  exit 1
fi
echo "PASS: XSS blocked by WAF (HTTP 403)"

# Test 4: Path traversal is blocked by WAF
status_code=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: app.example.test' "http://localhost:${PORT_80}/get?file=../../../etc/passwd")
if [ "$status_code" != "403" ]; then
  echo "FAIL: path traversal not blocked (got HTTP ${status_code}, expected 403)" >&2
  exit 1
fi
echo "PASS: path traversal blocked by WAF (HTTP 403)"

# Test 5: Another clean request to confirm WAF isn't over-blocking
body=$(curl -fsS -H 'Host: app.example.test' http://localhost:"${PORT_80}"/get?name=hello)
if ! echo "$body" | grep -qi 'x-waf-result'; then
  echo "FAIL: legitimate request blocked or WAF not processing" >&2
  echo "$body" >&2
  exit 1
fi
echo "PASS: legitimate request with query params passes WAF"
