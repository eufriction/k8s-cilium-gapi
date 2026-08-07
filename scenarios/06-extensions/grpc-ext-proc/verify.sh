#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
# shellcheck source=lib/envoy-metrics.sh
source "${REPO_ROOT}/lib/envoy-metrics.sh"

skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "ext_proc ExtensionRef requires branch build"
gateway_ports grpc-ext-proc-gateway gateway-system 443

HOST=grpc-ext-proc.example.test
GRPC_IMPORT_PATH="${REPO_ROOT}/apps/backend-grpc/proto"
GRPC_PROTO=grpc/testing/testservice.proto
GRPC_REQ='{"response_size":32,"fill_server_id":true}'
GRPC_METHOD=grpc.testing.TestService/UnaryCall
ITERATIONS=5

# Tier 1: pods + certs
wait_parallel \
  "pod/grpc-api -n grpc-backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "deployment/coraza-waf-extproc -n gateway-system --for=condition=Available --timeout=30s" \
  "certificate/grpc-ext-proc-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s"

# Tier 2: gateway
wait_gateway grpc-ext-proc-gateway gateway-system

# Tier 3: route
wait_route grpcroute grpc-ext-proc-route grpc-backend-a
kubectl wait grpcroute/grpc-ext-proc-route -n grpc-backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}=True' --timeout="${ROUTE_READY_TIMEOUT:-30}s"

# --- Listener status assertions ---
assert_listener_status grpc-ext-proc-gateway gateway-system grpcs 1 HTTPRoute GRPCRoute

# Warm up the gRPC listener.
retry_until 10 grpcurl -insecure \
  -authority "$HOST" \
  -import-path "$GRPC_IMPORT_PATH" \
  -proto "$GRPC_PROTO" \
  -d "$GRPC_REQ" \
  localhost:"${PORT_443}" \
  "$GRPC_METHOD" >/dev/null

metric_name="envoy_http_ext_proc_ceepf_grpc_backend_a_grpc_coraza_waf_streams_started"
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
  if ! printf '%s\n' "$metrics" | grep -E 'ceepf_grpc_backend_a_grpc_coraza_waf|ext_proc|timed out waiting for the condition|ErrImagePull|ImagePullBackOff|CreateContainer|Pending' >&2; then
    [ -n "$metrics" ] && printf '%s\n' "$metrics" >&2
  fi
  exit 1
}
echo "PASS: ext_proc Envoy metrics expose ceepf.grpc_backend_a.grpc_coraza_waf stats"

# Test 1: gRPC requests route to the backend through the ExtensionRef filter.
misrouted=0
for i in $(seq 1 $ITERATIONS); do
  server_id=$(grpcurl -insecure \
    -authority "$HOST" \
    -import-path "$GRPC_IMPORT_PATH" \
    -proto "$GRPC_PROTO" \
    -d "$GRPC_REQ" \
    localhost:"${PORT_443}" \
    "$GRPC_METHOD" | jq -r '.serverId')
  if [ "$server_id" != "grpc-backend-a" ]; then
    echo "  iteration $i: routed to '${server_id}' (expected grpc-backend-a)" >&2
    misrouted=$((misrouted + 1))
  fi
done
[ "$misrouted" -eq 0 ] || {
  echo "FAIL: gRPC ext_proc route mis-routed ${misrouted}/${ITERATIONS}" >&2
  exit 1
}
echo "PASS: gRPC requests route to grpc-backend-a through the ext_proc-filtered route"

# Test 2: Envoy ext_proc metrics increase after gRPC traffic.
metrics_settle_sleep="${ENVOY_METRICS_SETTLE_SLEEP:-30}"
echo "Waiting ${metrics_settle_sleep}s for Envoy metrics to settle..."
sleep "$metrics_settle_sleep"

metrics_deadline=$((SECONDS + metrics_timeout))
after_metric=""
while ((SECONDS < metrics_deadline)); do
  after_metric=$(scrape_ext_proc_metric_sum "$metric_name" "$metric_listener_prefix")
  if [ -n "$after_metric" ] && [ "$after_metric" -gt "$baseline_metric" ]; then
    echo "PASS: ext_proc Envoy metrics increased after gRPC traffic (${baseline_metric} -> ${after_metric})"
    break
  fi

  echo "  ext_proc Envoy metric has not increased yet, retrying in 1s..." >&2
  sleep 1
done

if [ -z "$after_metric" ] || [ "$after_metric" -le "$baseline_metric" ]; then
  echo "FAIL: ext_proc Envoy metric ${metric_name} did not increase after gRPC traffic (${baseline_metric} -> ${after_metric:-missing})" >&2
  if ! printf '%s\n' "$metrics" | grep -E 'ceepf_grpc_backend_a_grpc_coraza_waf|ext_proc|timed out waiting for the condition|ErrImagePull|ImagePullBackOff|CreateContainer|Pending' >&2; then
    [ -n "$metrics" ] && printf '%s\n' "$metrics" >&2
  fi
  exit 1
fi
