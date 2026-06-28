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
kubectl wait httproute/waf-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}=True' --timeout="${ROUTE_READY_TIMEOUT:-30}s"

# --- Listener status assertions ---
assert_listener_status waf-gateway gateway-system http 1 HTTPRoute GRPCRoute

# Warm up the HTTP listener
retry_until 10 curl -fsS -H 'Host: app.example.test' http://localhost:"${PORT_80}"/headers >/dev/null

metric_name="envoy_http_ext_proc_ceepf_backend_a_coraza_waf_streams_started"
metric_re="^${metric_name}\\{[^}]*envoy_http_conn_manager_prefix=\"listener-insecure\"[^}]*\\} [0-9]+(\\.[0-9]+)?$"
metrics_timeout="${ENVOY_METRICS_READY_TIMEOUT:-30}"
metrics_probe_timeout="${ENVOY_METRICS_PROBE_TIMEOUT:-15s}"
metrics=""

scrape_ext_proc_metric_sum() {
  local metrics_probe matches
  metrics_probe="ext-proc-metrics-probe-${RANDOM}"
  # shellcheck disable=SC2016 # ENVOY_IPS is expanded inside the probe pod.
  metrics=$(kubectl run "$metrics_probe" -n gateway-system --rm -i --restart=Never \
    --pod-running-timeout="$metrics_probe_timeout" \
    --image="nicolaka/netshoot:${NETSHOOT_VERSION:-v0.15}" \
    --env="ENVOY_IPS=${envoy_ips}" \
    --command -- sh -eu -c '
      for ip in ${ENVOY_IPS}; do
        curl -fsS --connect-timeout 2 --max-time 5 "http://${ip}:9964/metrics" || true
      done
    ' 2>&1 || true)

  matches=$(printf '%s\n' "$metrics" | grep -E "$metric_re" || true)
  if [ -z "$matches" ]; then
    return 0
  fi
  echo "$matches" | awk '{sum += $2} END {printf "%d\n", sum}'
}

wait_for_ext_proc_metric_sum() {
  local deadline metric_sum
  deadline=$((SECONDS + metrics_timeout))
  while ((SECONDS < deadline)); do
    metric_sum=$(scrape_ext_proc_metric_sum)
    if [ -n "$metric_sum" ]; then
      echo "$metric_sum"
      return 0
    fi
    echo "  ext_proc Envoy metric not ready, retrying in 1s..." >&2
    sleep 1
  done
  return 1
}

# Capture a baseline after the listener is ready. The warm-up request may or may
# not have reached the same Envoy instance before metrics are scraped, so only
# the before/after delta from the remaining test traffic is asserted below.
envoy_ips=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium-envoy -o jsonpath='{range .items[*]}{.status.podIP}{" "}{end}')
if [ -z "$envoy_ips" ]; then
  echo "FAIL: no cilium-envoy pod IPs found for metrics scrape" >&2
  exit 1
fi

baseline_metric=$(wait_for_ext_proc_metric_sum) || {
  echo "FAIL: ext_proc Envoy metric ${metric_name} is missing after ${metrics_timeout}s" >&2
  if ! printf '%s\n' "$metrics" | grep -E 'ceepf_backend_a_coraza_waf|ext_proc|timed out waiting for the condition|ErrImagePull|ImagePullBackOff|CreateContainer|Pending' >&2; then
    [ -n "$metrics" ] && printf '%s\n' "$metrics" >&2
  fi
  exit 1
}
echo "PASS: ext_proc Envoy metrics expose ceepf.backend_a.coraza_waf stats"

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

# Test 6: Envoy ext_proc metrics increase after WAF traffic.
metrics_settle_sleep="${ENVOY_METRICS_SETTLE_SLEEP:-30}"
echo "Waiting ${metrics_settle_sleep}s for Envoy metrics to settle..."
sleep "$metrics_settle_sleep"

metrics_deadline=$((SECONDS + metrics_timeout))
after_metric=""
while ((SECONDS < metrics_deadline)); do
  after_metric=$(scrape_ext_proc_metric_sum)
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
