#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
# shellcheck source=lib/envoy-metrics.sh
source "${REPO_ROOT}/lib/envoy-metrics.sh"

skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "ext_proc ExtensionRef requires branch build"
gateway_ports https-waf-gateway gateway-system 443

HOST=app.example.test
BASE_URL="https://${HOST}:${PORT_443}"
RESOLVE="${HOST}:${PORT_443}:127.0.0.1"

# Tier 1: pods + certs
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "deployment/coraza-waf-extproc -n gateway-system --for=condition=Available --timeout=30s" \
  "certificate/https-ext-proc-waf-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s"

# Tier 2: gateway
wait_gateway https-waf-gateway gateway-system

# Tier 3: route
wait_route httproute https-waf-route backend-a
kubectl wait httproute/https-waf-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}=True' --timeout="${ROUTE_READY_TIMEOUT:-30}s"

# --- Listener status assertions ---
assert_listener_status https-waf-gateway gateway-system https 1 HTTPRoute GRPCRoute

# Warm up the HTTPS listener.
retry_until 10 curl -kfsS --resolve "$RESOLVE" "${BASE_URL}/headers" >/dev/null

metric_name="envoy_http_ext_proc_ceepf_backend_a_https_coraza_waf_streams_started"
metric_listener_prefix=""
metrics_timeout="${ENVOY_METRICS_READY_TIMEOUT:-30}"
metrics_probe_timeout="${ENVOY_METRICS_PROBE_TIMEOUT:-15s}"
metrics=""

# Capture a baseline after the listener is ready. The warm-up request may or may
# not have reached the same Envoy instance before metrics are scraped, so only
# the before/after delta from the remaining test traffic is asserted below.
envoy_ips=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium-envoy -o jsonpath='{range .items[*]}{.status.podIP}{" "}{end}')
if [ -z "$envoy_ips" ]; then
  echo "FAIL: no cilium-envoy pod IPs found for metrics scrape" >&2
  exit 1
fi

baseline_metric=$(wait_for_ext_proc_metric_sum "$metric_name" "$metric_listener_prefix" "$metrics_timeout") || {
  echo "FAIL: ext_proc Envoy metric ${metric_name} is missing after ${metrics_timeout}s" >&2
  if ! printf '%s\n' "$metrics" | grep -E 'ceepf_backend_a_https_coraza_waf|ext_proc|timed out waiting for the condition|ErrImagePull|ImagePullBackOff|CreateContainer|Pending' >&2; then
    [ -n "$metrics" ] && printf '%s\n' "$metrics" >&2
  fi
  exit 1
}
echo "PASS: ext_proc Envoy metrics expose ceepf.backend_a.https_coraza_waf stats"

# Test 1: Clean request passes through WAF after TLS termination.
body=$(curl -kfsS --resolve "$RESOLVE" "${BASE_URL}/headers")
if ! echo "$body" | grep -qi 'x-waf-result'; then
  echo "FAIL: clean HTTPS request missing x-waf-result header (WAF not processing)" >&2
  echo "$body" >&2
  exit 1
fi
echo "PASS: clean HTTPS request passed through WAF (x-waf-result header present)"

# Test 2: SQL injection is blocked by WAF.
status_code=$(curl -ksS -o /dev/null -w '%{http_code}' --resolve "$RESOLVE" "${BASE_URL}/get?q=union+select+1+from+users")
if [ "$status_code" != "403" ]; then
  echo "FAIL: SQL injection over HTTPS not blocked (got HTTP ${status_code}, expected 403)" >&2
  exit 1
fi
echo "PASS: SQL injection over HTTPS blocked by WAF (HTTP 403)"

# Test 3: XSS attempt is blocked by WAF.
status_code=$(curl -ksS -o /dev/null -w '%{http_code}' --resolve "$RESOLVE" "${BASE_URL}/get?q=<script>alert(1)</script>")
if [ "$status_code" != "403" ]; then
  echo "FAIL: XSS over HTTPS not blocked (got HTTP ${status_code}, expected 403)" >&2
  exit 1
fi
echo "PASS: XSS over HTTPS blocked by WAF (HTTP 403)"

# Test 4: Path traversal is blocked by WAF.
status_code=$(curl -ksS -o /dev/null -w '%{http_code}' --resolve "$RESOLVE" "${BASE_URL}/get?file=../../../etc/passwd")
if [ "$status_code" != "403" ]; then
  echo "FAIL: path traversal over HTTPS not blocked (got HTTP ${status_code}, expected 403)" >&2
  exit 1
fi
echo "PASS: path traversal over HTTPS blocked by WAF (HTTP 403)"

# Test 5: Another clean request confirms WAF is not over-blocking.
body=$(curl -kfsS --resolve "$RESOLVE" "${BASE_URL}/get?name=hello")
if ! echo "$body" | grep -qi 'x-waf-result'; then
  echo "FAIL: legitimate HTTPS request blocked or WAF not processing" >&2
  echo "$body" >&2
  exit 1
fi
echo "PASS: legitimate HTTPS request with query params passes WAF"

# Test 6: Envoy ext_proc metrics increase after WAF traffic.
metrics_settle_sleep="${ENVOY_METRICS_SETTLE_SLEEP:-30}"
echo "Waiting ${metrics_settle_sleep}s for Envoy metrics to settle..."
sleep "$metrics_settle_sleep"

metrics_deadline=$((SECONDS + metrics_timeout))
after_metric=""
while ((SECONDS < metrics_deadline)); do
  after_metric=$(scrape_ext_proc_metric_sum "$metric_name" "$metric_listener_prefix")
  if [ -n "$after_metric" ] && [ "$after_metric" -gt "$baseline_metric" ]; then
    echo "PASS: ext_proc Envoy metrics increased after HTTPS WAF traffic (${baseline_metric} -> ${after_metric})"
    break
  fi

  echo "  ext_proc Envoy metric has not increased yet, retrying in 1s..." >&2
  sleep 1
done

if [ -z "$after_metric" ] || [ "$after_metric" -le "$baseline_metric" ]; then
  echo "FAIL: ext_proc Envoy metric ${metric_name} did not increase after HTTPS WAF traffic (${baseline_metric} -> ${after_metric:-missing})" >&2
  if ! printf '%s\n' "$metrics" | grep -E 'ceepf_backend_a_https_coraza_waf|ext_proc|timed out waiting for the condition|ErrImagePull|ImagePullBackOff|CreateContainer|Pending' >&2; then
    [ -n "$metrics" ] && printf '%s\n' "$metrics" >&2
  fi
  exit 1
fi
