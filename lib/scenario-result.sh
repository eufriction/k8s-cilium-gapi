#!/usr/bin/env bash
# Report the task's exit status; Mise still owns verification and cleanup.
set -euo pipefail

_scenario_result_id="${1#*/scenarios/}"
_scenario_result_outcome=PASS

scenario_result() {
  local status="$?"
  trap - EXIT
  if [ "$status" -ne 0 ]; then _scenario_result_outcome=FAIL; fi
  printf 'SCENARIO_RESULT\t%s\t%s\t%s\n' \
    "$_scenario_result_id" "$_scenario_result_outcome" "$status" || true
  exit "$status"
}

echo "SCENARIO: $1"
printf 'SCENARIO_START\t%s\n' "$_scenario_result_id"
trap scenario_result EXIT
for _scenario_result_version in ${SCENARIO_SKIP_VERSIONS:-}; do
  if [ "$_scenario_result_version" = "${CILIUM_VERSION:-}" ]; then
    _scenario_result_outcome=SKIP
    echo "SKIP: known broken or unsupported on Cilium ${CILIUM_VERSION}"
    exit 0
  fi
done
