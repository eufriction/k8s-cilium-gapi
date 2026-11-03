#!/usr/bin/env bash
set -euo pipefail

work_dir=$(mktemp -d "${TEST_TMPDIR:-${TMPDIR:-/tmp}}/scenario-lifecycle.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
mkdir "$work_dir/bin"
export MOCK_DIR="$work_dir"
export PATH="$work_dir/bin:$PATH"
export KIND_CLUSTER_NAME=test-cluster
preflight_script="$(pwd)/lib/scenario-preflight.sh"

cat >"$work_dir/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'get gateways.gateway.networking.k8s.io -A -o json')
    [ "${MOCK_FAILURE:-}" != gateways ] || exit 1
    cat "$MOCK_DIR/gateways.json"
    ;;
  'get services -A -o json')
    [ "${MOCK_FAILURE:-}" != services ] || exit 1
    cat "$MOCK_DIR/services.json"
    ;;
  *) echo "Unexpected kubectl call: $*" >&2; exit 99 ;;
esac
EOF
cat >"$work_dir/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_DIR/docker-calls"
[ "${MOCK_FAILURE:-}" != docker ] || exit 1
cat "$MOCK_DIR/proxies"
EOF
chmod +x "$work_dir/bin/kubectl" "$work_dir/bin/docker"

reset_state() {
  printf '{"items":[]}\n' >"$work_dir/gateways.json"
  printf '{"items":[]}\n' >"$work_dir/services.json"
  : >"$work_dir/proxies"
  : >"$work_dir/docker-calls"
  unset MOCK_FAILURE
}

check_preflight() {
  local expected="$1" actual=0
  bash "$preflight_script" >"$work_dir/output" 2>&1 || actual=$?
  if [ "$actual" -ne "$expected" ]; then
    cat "$work_dir/output" >&2
    echo "FAIL: preflight returned $actual, expected $expected" >&2
    exit 1
  fi
}

reset_state
mkdir -p "$work_dir/scenarios/group/missing-overlay"
touch "$work_dir/scenarios/group/missing-overlay/mise.toml"
(
  cd "$work_dir"
  check_preflight 2
)
grep -F 'needs a gateway/kustomization.yaml' "$work_dir/output" >/dev/null

check_preflight 0
grep -F 'label=io.x-k8s.cloud-provider-kind.cluster=test-cluster' "$work_dir/docker-calls" >/dev/null
grep -F 'label=io.x-k8s.cloud-provider-kind.loadbalancer.name' "$work_dir/docker-calls" >/dev/null

cat >"$work_dir/gateways.json" <<'EOF'
{"items":[{"metadata":{"name":"route-cache-escape-gateway","namespace":"gateway-system"},"spec":{"gatewayClassName":"cilium"}}]}
EOF
check_preflight 2
grep -F 'Gateway/gateway-system/route-cache-escape-gateway' "$work_dir/output" >/dev/null

reset_state
cat >"$work_dir/gateways.json" <<'EOF'
{"items":[{"metadata":{"name":"other","namespace":"other"},"spec":{"gatewayClassName":"other"}}]}
EOF
check_preflight 0

reset_state
cat >"$work_dir/services.json" <<'EOF'
{"items":[{"metadata":{"name":"cilium-gateway-shared-backend-gateway","namespace":"gateway-system","deletionTimestamp":"2026-11-02T15:09:48Z","labels":{"io.cilium.gateway/owning-gateway":"shared-backend-gateway"}}}]}
EOF
check_preflight 2
grep -F 'Service/gateway-system/cilium-gateway-shared-backend-gateway (terminating)' "$work_dir/output" >/dev/null

reset_state
cat >"$work_dir/services.json" <<'EOF'
{"items":[{"metadata":{"name":"api","namespace":"backend-a"},"spec":{"type":"ClusterIP"}}]}
EOF
check_preflight 0

reset_state
printf 'kindccm-leftover\tCreated\t\n' >"$work_dir/proxies"
check_preflight 2
grep -F kindccm-leftover "$work_dir/output" >/dev/null

for failure in gateways services docker; do
  reset_state
  export MOCK_FAILURE="$failure"
  check_preflight 2
done
printf 'PASS: preflight checks fixture overlays and rejects leftover resources\n'

# Execute the real task body with verbose disabled and fixture tasks mocked.
awk '
  /^\[tasks\."scenarios:run-all"\]$/ { task = 1; next }
  task && /^run = """$/ { body = 1; next }
  body && /^"""$/ { exit }
  body {
    sub(/\{% if usage.verbose %\} --verbose\{% endif %\}/, "")
    gsub(/\\\\/, "\\")
    print
  }
  END { if (!body) exit 1 }
' mise.toml >"$work_dir/run-all.sh"
cat >"$work_dir/bin/mise" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MOCK_DIR/mise-calls"
exit 99
EOF
chmod +x "$work_dir/bin/mise"

reset_state
printf 'kindccm-leftover\tCreated\t\n' >"$work_dir/proxies"
: >"$work_dir/mise-calls"
export RUN_LOG="$work_dir/runner log.txt" RUN_RESULTS="$work_dir/runner results.tsv"
runner_status=0
bash "$work_dir/run-all.sh" >"$work_dir/output" 2>&1 || runner_status=$?
if [ "$runner_status" -ne 2 ] || [ -s "$work_dir/mise-calls" ]; then
  cat "$work_dir/output" "$work_dir/mise-calls" >&2
  echo 'FAIL: rejected preflight must exit 2 without fixture setup or cleanup' >&2
  exit 1
fi
grep -F kindccm-leftover "$work_dir/output" >/dev/null
printf 'PASS: rejected suite start invokes neither fixture setup nor fixture cleanup\n'

cat >"$work_dir/bin/mise" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_DIR/mise-calls"
case "$*" in
  'run fixture:start') exit "$MOCK_START_STATUS" ;;
  'run fixture:delete')
    if [ "$MOCK_CLEANUP_STATUS" -eq 0 ]; then
      echo 'PASS: fixture cleanup'
    else
      echo 'FAIL: fixture cleanup'
    fi
    exit "$MOCK_CLEANUP_STATUS"
    ;;
  'run --continue-on-error --jobs 1 //scenarios/...:start --delete')
    printf 'SCENARIO_START\tgroup/http\n'
    if [ "$MOCK_TERMINAL" = true ]; then
      outcome=PASS
      [ "$MOCK_VERIFY_STATUS" -eq 0 ] || outcome=FAIL
      printf 'SCENARIO_RESULT\tgroup/http\t%s\t%s\n' "$outcome" "$MOCK_VERIFY_STATUS"
    fi
    exit "$MOCK_VERIFY_STATUS"
    ;;
  *) echo "Unexpected mise call: $*" >&2; exit 99 ;;
esac
EOF

while read -r name start verify cleanup terminal expected overall scenario; do
  reset_state
  : >"$work_dir/mise-calls"
  export MOCK_START_STATUS="$start" MOCK_VERIFY_STATUS="$verify"
  export MOCK_CLEANUP_STATUS="$cleanup" MOCK_TERMINAL="$terminal"
  runner_status=0
  bash "$work_dir/run-all.sh" >"$work_dir/output" 2>&1 || runner_status=$?
  if [ "$runner_status" -ne "$expected" ]; then
    cat "$work_dir/output" >&2
    echo "FAIL: $name returned $runner_status, expected $expected" >&2
    exit 1
  fi
  grep -qx "$(printf 'status\t%s' "$overall")" "$RUN_RESULTS"
  if [ "$scenario" = - ]; then
    if grep -q '^scenario' "$RUN_RESULTS"; then
      echo "FAIL: $name published an unrun scenario" >&2
      exit 1
    fi
  else
    grep -F "$(printf 'scenario\tgroup/http\t%s\t' "$scenario")" "$RUN_RESULTS" >/dev/null
  fi
  {
    printf 'run fixture:start\n'
    if [ "$start" -eq 0 ]; then
      printf 'run --continue-on-error --jobs 1 //scenarios/...:start --delete\n'
    fi
    printf 'run fixture:delete\n'
  } >"$work_dir/expected-calls"
  diff -u "$work_dir/expected-calls" "$work_dir/mise-calls"
  run_result="$start"
  if [ "$run_result" -eq 0 ]; then run_result="$verify"; fi
  if [ "$run_result" -eq 0 ]; then run_result="$cleanup"; fi
  grep -qx "$(printf 'RUN_RESULT\t%s' "$run_result")" "$RUN_LOG"
  printf 'PASS: runner %s\n' "$name"
done <<'EOF'
success 0 0 0 true 0 PASS PASS
verify-failure 0 7 0 true 7 FAIL FAIL
cleanup-only-failure 0 0 9 true 9 FAIL PASS
original-failure-wins 0 7 9 true 7 FAIL FAIL
fixture-start-failure 4 0 0 true 4 FAIL -
incomplete-scenario 0 0 0 false 1 FAIL FAIL
EOF

reset_state
printf 'kindccm-leftover\tCreated\t\n' >"$work_dir/proxies"
printf 'status\tPASS\n' >"$RUN_RESULTS"
: >"$work_dir/mise-calls"
runner_status=0
bash "$work_dir/run-all.sh" >"$work_dir/output" 2>&1 || runner_status=$?
[ "$runner_status" -eq 2 ]
[ ! -e "$RUN_RESULTS" ]
[ ! -s "$work_dir/mise-calls" ]
grep -qx RUN_START "$RUN_LOG"
printf 'PASS: rejected preflight removes stale PASS without fixture calls\n'

# Stub the API/Envoy probes; only the Docker identity check is under test here.
source lib/envoy-readiness.sh
kubectl() { return 1; }
envoy_agent_pods() { echo test-agent; }
envoy_exec() { echo '{}'; }

reset_state
envoy_gateway_resources_gone shared-backend-gateway gateway-system
grep -F 'label=io.x-k8s.cloud-provider-kind.loadbalancer.name=test-cluster/gateway-system/cilium-gateway-shared-backend-gateway' "$work_dir/docker-calls" >/dev/null

printf 'leftover-id\n' >"$work_dir/proxies"
if envoy_gateway_resources_gone shared-backend-gateway gateway-system; then
  echo 'FAIL: teardown accepted a remaining load-balancer container' >&2
  exit 1
fi
export MOCK_FAILURE=docker
if envoy_gateway_resources_gone shared-backend-gateway gateway-system; then
  echo 'FAIL: teardown accepted a failed Docker query' >&2
  exit 1
fi
printf 'PASS: teardown checks the Service load-balancer label and fails closed on Docker errors\n'
