#!/usr/bin/env bash
# envoy-metrics.sh — shared Envoy ext_proc metric scraping helpers
#
# Callers must set envoy_ips before scraping. The optional
# metrics_probe_timeout and metrics_timeout variables override the defaults;
# ENVOY_METRICS_PROBE_TIMEOUT, ENVOY_METRICS_READY_TIMEOUT, and
# NETSHOOT_VERSION provide environment-level overrides.

# scrape_ext_proc_metric_sum <metric_name> [<listener_prefix>]
#
# Scrape the named Envoy metric from every Cilium Envoy and return the sum of
# matching samples. If listener_prefix is provided, only samples from that
# Envoy HTTP connection-manager listener are included.
#
# The raw probe output is retained in the caller's `metrics` variable for
# timeout diagnostics, matching the existing scenario verifier behavior.
scrape_ext_proc_metric_sum() {
  local metric_name="$1" listener_prefix="${2:-}"
  local envoy_ips_value="${envoy_ips:-}"
  local metrics_probe matches metric_re
  metrics_probe="ext-proc-metrics-probe-${RANDOM}"

  if [ -n "$listener_prefix" ]; then
    metric_re="^${metric_name}\\{[^}]*envoy_http_conn_manager_prefix=\"${listener_prefix}\"[^}]*\\} [0-9]+(\\.[0-9]+)?$"
  else
    metric_re="^${metric_name}\\{[^}]*\\} [0-9]+(\\.[0-9]+)?$"
  fi

  # shellcheck disable=SC2016 # ENVOY_IPS is expanded inside the probe pod.
  metrics=$(kubectl run "$metrics_probe" -n gateway-system --rm -i --restart=Never \
    --pod-running-timeout="${metrics_probe_timeout:-${ENVOY_METRICS_PROBE_TIMEOUT:-15s}}" \
    --image="nicolaka/netshoot:${NETSHOOT_VERSION:-v0.15}" \
    --env="ENVOY_IPS=${envoy_ips_value}" \
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

# wait_for_ext_proc_metric_sum <metric_name> [<listener_prefix>] [<timeout>]
#
# Wait until the named metric is available, returning its summed value or
# failure after timeout seconds.
wait_for_ext_proc_metric_sum() {
  local metric_name="$1" listener_prefix="${2:-}"
  local timeout="${3:-${metrics_timeout:-${ENVOY_METRICS_READY_TIMEOUT:-30}}}"
  local deadline metric_sum
  deadline=$((SECONDS + timeout))
  while ((SECONDS < deadline)); do
    metric_sum=$(scrape_ext_proc_metric_sum "$metric_name" "$listener_prefix")
    if [ -n "$metric_sum" ]; then
      echo "$metric_sum"
      return 0
    fi
    echo "  ext_proc Envoy metric not ready, retrying in 1s..." >&2
    sleep 1
  done
  return 1
}
