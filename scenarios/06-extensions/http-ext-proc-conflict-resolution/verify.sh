#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "ext_proc ExtensionRef requires branch build"

if ! kubectl get crd ciliumenvoyextprocfilters.cilium.io &>/dev/null; then
  echo "FAIL: CiliumEnvoyExtProcFilter CRD not installed — run against a branch build with ext_proc support" >&2
  exit 1
fi

gateway_ports ext-proc-conflict-resolution-gateway gateway-system 80
HOST=ext-proc-auth.example.test
BASE_URL="http://localhost:${PORT_80}"

wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-30}s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-30}s" \
  "deployment/coraza-waf-extproc -n gateway-system --for=condition=Available --timeout=60s" \
  "deployment/external-authz -n auth --for=condition=Available --timeout=60s"

gw_timeout="${GW_READY_TIMEOUT:-30}s"
route_timeout="${ROUTE_READY_TIMEOUT:-30}s"
wait_gateway ext-proc-conflict-resolution-gateway gateway-system
kubectl wait gateway/ext-proc-conflict-resolution-gateway -n gateway-system \
  --for='jsonpath={.status.conditions[?(@.type=="Programmed")].status}=True' \
  --timeout="$gw_timeout"

tie_and_ordered_routes=(
  "backend-a|00-oldest-route"
  "backend-a|a-tie-route"
  "backend-b|a-tie-route"
  "backend-b|b-tie-route"
  "backend-b|newest-route"
  "backend-a|auth-route"
)
for route in "${tie_and_ordered_routes[@]}"; do
  IFS='|' read -r namespace name <<<"$route"
  wait_route httproute "$name" "$namespace"
  kubectl wait httproute/"${name}" -n "$namespace" \
    --for='jsonpath={.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}=True' \
    --timeout="$route_timeout"
done

echo "PASS: six valid HTTPRoutes are Accepted=True and ResolvedRefs=True"

wait_route httproute invalid-route backend-a
kubectl wait httproute/invalid-route -n backend-a \
  --for='jsonpath={.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}=False' \
  --timeout="$route_timeout"
invalid_reason=$(kubectl get httproute/invalid-route -n backend-a \
  -o 'jsonpath={.status.parents[0].conditions[?(@.type=="ResolvedRefs")].reason}')
if [ "$invalid_reason" != "BackendNotFound" ]; then
  echo "FAIL: invalid-route ResolvedRefs reason=${invalid_reason} (expected BackendNotFound)" >&2
  exit 1
fi
echo "PASS: invalid-route reports ResolvedRefs=False, reason=BackendNotFound"

assert_listener_status ext-proc-conflict-resolution-gateway gateway-system http 7 HTTPRoute GRPCRoute

cec_name=cilium-gateway-ext-proc-conflict-resolution-gateway
retry_until 30 kubectl get cec/"$cec_name" -n gateway-system >/dev/null

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
actual_all="$tmp_dir/actual-all"
actual_extproc="$tmp_dir/actual-extproc"
expected_extproc="$tmp_dir/expected-extproc"
expected_rows="$tmp_dir/expected-rows"

# The CEC stores Envoy resources as JSON objects in spec.resources. Select the
# HTTP connection manager's filter list without depending on a fixed resource
# index or on the representation of protobuf Any fields.
kubectl get cec/"$cec_name" -n gateway-system -o json |
  jq -r '
      .spec.resources[]
      | .. | objects
      | select(.httpFilters? != null)
      | .httpFilters[]?.name
    ' >"$actual_all"
grep '^envoy.filters.http.ext_proc/' "$actual_all" >"$actual_extproc" || true

# This is the same precedence tuple used by Cilium's getUniqueExtProcFilters:
# creationTimestamp, namespace, route name, then the ExtensionRef index. The
# final awk step models the listener-wide deduplication by Envoy filter name.
route_filter_specs=(
  "backend-a|00-oldest-route|0|oldest-first"
  "backend-a|00-oldest-route|1|shared-a"
  "backend-a|00-oldest-route|2|oldest-last"
  "backend-a|a-tie-route|0|shared-a"
  "backend-a|a-tie-route|1|a-tie-last"
  "backend-b|a-tie-route|0|b-tie-first"
  "backend-b|a-tie-route|1|shared-b"
  "backend-b|a-tie-route|2|b-tie-last"
  "backend-b|b-tie-route|0|shared-b"
  "backend-b|b-tie-route|1|b-name-tie-last"
  "backend-b|newest-route|0|newest-first"
  "backend-b|newest-route|1|newest-last"
  "backend-a|auth-route|0|auth-extproc"
)
for route_filter in "${route_filter_specs[@]}"; do
  IFS='|' read -r namespace route index filter <<<"$route_filter"
  timestamp=$(kubectl get httproute/"$route" -n "$namespace" \
    -o jsonpath='{.metadata.creationTimestamp}')
  printf '%s\t%s\t%s\t%s\tenvoy.filters.http.ext_proc/%s/%s\n' \
    "$timestamp" "$namespace" "$route" "$index" "$namespace" "$filter"
done |
  sort -t "$(printf '\t')" -k1,1 -k2,2 -k3,3 -k4,4n |
  tee "$expected_rows" |
  awk -F '\t' '!seen[$5]++ {print $5}' >"$expected_extproc"

if ! diff -u "$expected_extproc" "$actual_extproc"; then
  echo "FAIL: generated ext_proc filter order does not match Gateway API precedence" >&2
  echo "Expected order:" >&2
  cat "$expected_extproc" >&2
  echo "Actual order:" >&2
  cat "$actual_extproc" >&2
  exit 1
fi

oldest_timestamp=$(kubectl get httproute/00-oldest-route -n backend-a \
  -o jsonpath='{.metadata.creationTimestamp}')
tie_a_timestamp=$(kubectl get httproute/a-tie-route -n backend-a \
  -o jsonpath='{.metadata.creationTimestamp}')
tie_b_timestamp=$(kubectl get httproute/a-tie-route -n backend-b \
  -o jsonpath='{.metadata.creationTimestamp}')
name_tie_timestamp=$(kubectl get httproute/b-tie-route -n backend-b \
  -o jsonpath='{.metadata.creationTimestamp}')
newest_timestamp=$(kubectl get httproute/newest-route -n backend-b \
  -o jsonpath='{.metadata.creationTimestamp}')
if ! [[ "$oldest_timestamp" < "$tie_a_timestamp" ]] ||
  [ "$tie_a_timestamp" != "$tie_b_timestamp" ] ||
  [ "$tie_a_timestamp" != "$name_tie_timestamp" ] ||
  ! [[ "$tie_a_timestamp" < "$newest_timestamp" ]]; then
  echo "FAIL: route timestamps do not form the intended older/tie/newer groups" >&2
  printf '  oldest=%s\n  namespace-tie-a=%s\n  namespace-tie-b=%s\n  name-tie=%s\n  newest=%s\n' \
    "$oldest_timestamp" "$tie_a_timestamp" "$tie_b_timestamp" "$name_tie_timestamp" "$newest_timestamp" >&2
  exit 1
fi
echo "PASS: CEC ext_proc order follows creation time, namespace/name, filter index, and deduplication"

first_auth=$(awk '/^envoy.filters.http.ext_authz\// {print NR; exit}' "$actual_all")
last_extproc=$(awk '/^envoy.filters.http.ext_proc\// {line=NR} END {print line+0}' "$actual_all")
if [ -z "$first_auth" ] || [ "$last_extproc" -eq 0 ] || [ "$last_extproc" -ge "$first_auth" ]; then
  echo "FAIL: ext_proc filters are not all before ext_authz (last ext_proc line ${last_extproc}, first ext_authz line ${first_auth:-missing})" >&2
  cat "$actual_all" >&2
  exit 1
fi
echo "PASS: all ext_proc filters precede ext_authz in the generated HTTP filter chain"

retry_until 20 curl -fsS -H "Host: ${HOST}" -H 'X-Authz-Token: allow' \
  "${BASE_URL}/headers" >/dev/null
body=$(curl -fsS -H "Host: ${HOST}" -H 'X-Authz-Token: allow' "${BASE_URL}/headers")
if ! echo "$body" | grep -qi 'x-waf-result'; then
  echo "FAIL: authenticated route is missing x-waf-result" >&2
  exit 1
fi
if ! echo "$body" | grep -qi 'x-ext-authz-result'; then
  echo "FAIL: authenticated route is missing x-ext-authz-result" >&2
  exit 1
fi
echo "PASS: authenticated route runs ext_proc and ExternalAuth"

status_code=""
deadline=$((SECONDS + 30))
while ((SECONDS < deadline)); do
  status_code=$(curl -s -o /dev/null -w '%{http_code}' \
    -H 'Host: ext-proc-invalid.example.test' "${BASE_URL}/headers" 2>/dev/null) || true
  [ "$status_code" = "500" ] && break
  echo "  invalid route returned ${status_code:-<no response>}, retrying in 1s..." >&2
  sleep 1
done
if [ "$status_code" != "500" ]; then
  echo "FAIL: invalid ext_proc reference returned HTTP ${status_code:-<no response>} (expected 500)" >&2
  exit 1
fi
echo "PASS: invalid ext_proc reference fails closed with HTTP 500"
