#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
# shellcheck source=lib/envoy-metrics.sh
source "${REPO_ROOT}/lib/envoy-metrics.sh"

skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "ext_proc ExtensionRef requires branch build"
require_crd ciliumenvoyextprocfilters.cilium.io \
  "run against a branch build with ext_proc support"
gateway_ports waf-gateway gateway-system 80

# Tier 1: pods
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "deployment/coraza-waf-extproc -n gateway-system --for=condition=Available --timeout=30s"

# Tier 2: gateway
wait_gateway waf-gateway gateway-system

# Tier 3: route
wait_route httproute waf-route backend-a
wait_route httproute waf-route backend-a ResolvedRefs

# --- Listener status assertions ---
assert_listener_status waf-gateway gateway-system http 1 HTTPRoute GRPCRoute

# Warm up the HTTP listener
retry_until 10 curl -fsS -H 'Host: app.example.test' http://localhost:"${PORT_80}"/headers >/dev/null

metric_name="envoy_http_ext_proc_ceepf_backend_a_coraza_waf_streams_started"
metric_listener_prefix="listener-insecure"
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
  if ! printf '%s\n' "$metrics" | grep -E 'ceepf_backend_a_coraza_waf|ext_proc|timed out waiting for the condition|ErrImagePull|ImagePullBackOff|CreateContainer|Pending' >&2; then
    [ -n "$metrics" ] && printf '%s\n' "$metrics" >&2
  fi
  exit 1
}
echo "PASS: ext_proc Envoy metrics expose ceepf.backend_a.coraza_waf stats"

# Test 1: Clean request passes through WAF
assert_body "http://localhost:${PORT_80}/headers" 'x-waf-result' \
  -H 'Host: app.example.test'

# Test 2: SQL injection is blocked by WAF
assert_http "http://localhost:${PORT_80}/get?q=union+select+1+from+users" 403 \
  -H 'Host: app.example.test'

# Test 3: XSS attempt is blocked by WAF
assert_http "http://localhost:${PORT_80}/get?q=<script>alert(1)</script>" 403 \
  -H 'Host: app.example.test'

# Test 4: Path traversal is blocked by WAF
assert_http "http://localhost:${PORT_80}/get?file=../../../etc/passwd" 403 \
  -H 'Host: app.example.test'

# Test 5: Another clean request to confirm WAF isn't over-blocking
assert_body "http://localhost:${PORT_80}/get?name=hello" 'x-waf-result' \
  -H 'Host: app.example.test'

# Test 6: Envoy ext_proc metrics increase after WAF traffic.
metrics_settle_sleep="${ENVOY_METRICS_SETTLE_SLEEP:-30}"
echo "Waiting ${metrics_settle_sleep}s for Envoy metrics to settle..."
sleep "$metrics_settle_sleep"

metrics_deadline=$((SECONDS + metrics_timeout))
after_metric=""
while ((SECONDS < metrics_deadline)); do
  after_metric=$(scrape_ext_proc_metric_sum "$metric_name" "$metric_listener_prefix")
  if [ -n "$after_metric" ] && [ "$after_metric" -gt "$baseline_metric" ]; then
    echo "PASS: ext_proc Envoy metrics increased after WAF traffic (${baseline_metric} -> ${after_metric})"
    break
  fi

  echo "  ext_proc Envoy metric has not increased yet, retrying in 1s..." >&2
  sleep 1
done

if [ -z "$after_metric" ] || [ "$after_metric" -le "$baseline_metric" ]; then
  echo "FAIL: ext_proc Envoy metric ${metric_name} did not increase after WAF traffic (${baseline_metric} -> ${after_metric:-missing})" >&2
  if ! printf '%s\n' "$metrics" | grep -E 'ceepf_backend_a_coraza_waf|ext_proc|timed out waiting for the condition|ErrImagePull|ImagePullBackOff|CreateContainer|Pending' >&2; then
    [ -n "$metrics" ] && printf '%s\n' "$metrics" >&2
  fi
  exit 1
fi
