#!/usr/bin/env bash
# Summarize scenario reporting records and write TSV results.
set -euo pipefail

usage() {
  echo "Usage: $0 [--results FILE] [--cilium-version VERSION] [LOG_FILE|-]" >&2
  exit 2
}

results_file="${RUN_RESULTS:-run-all-results.tsv}"
version="${CILIUM_VERSION:-unknown}"
input_file="-"
input_set=false
while [ "$#" -gt 0 ]; do
  case "$1" in
  --results | --cilium-version)
    [ "$#" -ge 2 ] && [ -n "$2" ] || usage
    if [ "$1" = --results ]; then results_file="$2"; else version="$2"; fi
    shift 2
    ;;
  --)
    shift
    [ "$#" -le 1 ] || usage
    if [ "$#" -eq 1 ]; then
      [ "$input_set" = false ] || usage
      input_file="$1"
    fi
    break
    ;;
  -h | --help) usage ;;
  -*)
    [ "$1" = - ] && [ "$input_set" = false ] || usage
    input_set=true
    shift
    ;;
  *)
    [ "$input_set" = false ] || usage
    input_file="$1"
    input_set=true
    shift
    ;;
  esac
done

if [ -d "$results_file" ]; then
  echo "ERROR: results path is a directory: $results_file" >&2
  exit 1
fi
temporary_input=""
temporary_results=""
trap 'rm -f -- "$temporary_input" "$temporary_results"' EXIT
trap 'exit 1' HUP INT TERM
# Spool files too: cat detects read errors before we publish anything.
temporary_input=$(mktemp "${TMPDIR:-/tmp}/summarize-input.tmp.XXXXXX")
if [ "$input_file" = - ]; then cat >"$temporary_input"; else cat -- "$input_file" >"$temporary_input"; fi

scenarios=() statuses=() details=() diagnostics=() completed=()
current=""
found_index=-1
run_started=false
run_finished=false
run_detail=""
run_diagnostics=""

ensure_scenario() {
  local i
  for i in "${!scenarios[@]}"; do
    if [ "${scenarios[$i]}" = "$1" ]; then
      found_index=$i
      return
    fi
  done
  found_index=${#scenarios[@]}
  scenarios+=("$1") statuses+=(UNKNOWN) details+=("") diagnostics+=("") completed+=(false)
}

record_result() {
  local result="$1" detail="$2"
  ensure_scenario "$current"
  if [ -n "$result" ] && [ "${statuses[$found_index]}" != FAIL ]; then statuses[found_index]="$result"; fi
  if [ -n "$detail" ]; then details[found_index]+="${details[$found_index]:+; }$detail"; fi
}

run_failure() { run_detail+="${run_detail:+; }$1"; }

tab=$'\t'
start_re="^SCENARIO_START${tab}([^[:space:]]+)$"
result_re="^SCENARIO_RESULT${tab}([^[:space:]]+)${tab}(PASS|FAIL|SKIP)${tab}([0-9]+)$"
run_re="^RUN_RESULT${tab}([0-9]+)$"
prefix_re='^\[[^]]*\][[:space:]]+'
label_re='//scenarios/([^:[:space:]]+):(start|verify|delete)'
fixture_re='(^|[[:space:]])\[(//:)?fixture:[^]]*\][[:space:]]'
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  payload="$line"
  while [[ "$payload" =~ $prefix_re ]]; do payload="${payload#"${BASH_REMATCH[0]}"}"; done
  if [[ "$payload" =~ $start_re ]]; then
    current="${BASH_REMATCH[1]}"
    ensure_scenario "$current"
    completed[found_index]=false
    [ "${statuses[$found_index]}" = FAIL ] || statuses[found_index]=UNKNOWN
    continue
  elif [[ "$payload" =~ $result_re ]]; then
    current="${BASH_REMATCH[1]}"
    outcome="${BASH_REMATCH[2]}"
    code="${BASH_REMATCH[3]}"
    detail=""
    if [ "$outcome" = FAIL ] || [[ ! "$code" =~ ^0+$ ]]; then
      detail="SCENARIO_RESULT $outcome exited $code"
      outcome=FAIL
    fi
    record_result "$outcome" "$detail"
    completed[found_index]=true
    current=""
    continue
  elif [ "$payload" = RUN_START ]; then
    run_started=true
    run_finished=false
    current=""
    continue
  elif [[ "$payload" =~ $run_re ]]; then
    code="${BASH_REMATCH[1]}"
    [ "$run_started" = true ] || run_failure 'incomplete: RUN_RESULT without RUN_START'
    run_finished=true
    [[ "$code" =~ ^0+$ ]] || run_failure "RUN_RESULT exited $code"
    current=""
    continue
  elif [[ "$payload" == SCENARIO_RESULT* || "$payload" == RUN_RESULT* ]]; then
    run_failure "malformed result record: $payload"
    continue
  fi

  if [[ "$payload" =~ ^SCENARIO:[[:space:]]+.*/scenarios/(.+)$ ]]; then
    current="${BASH_REMATCH[1]}"
    ensure_scenario "$current"
  elif [[ "$line" =~ $label_re ]]; then
    candidate="${BASH_REMATCH[1]}"
    if [[ "$candidate" != *'...'* && "$candidate" != *'…'* ]]; then current="$candidate"; fi
  elif [[ "$line" =~ $fixture_re ]]; then
    current=""
  fi
  if [ -n "$current" ]; then
    ensure_scenario "$current"
    [ "${completed[$found_index]}" = false ] || current=""
  fi
  if [[ "$payload" == *'FAIL:'* || "$payload" == *'INFRA:'* || "$payload" == *'ERROR:'* ||
    "$payload" == *'Error:'* || "$payload" == 'Error '* || "$payload" == *'error:'* || "$payload" == *'Task '*' failed'* ]]; then
    # Prose supplies context, not outcomes: errors may have been handled.
    if [ -n "$current" ]; then
      diagnostics[found_index]+="${diagnostics[$found_index]:+; }$payload"
    else
      run_diagnostics+="${run_diagnostics:+; }$payload"
    fi
  elif [[ "$payload" == *'SKIP:'* && -n "$current" ]]; then
    record_result "" "${payload#*SKIP:}"
  fi
done <"$temporary_input"

pass_count=0
fail_count=0
skip_count=0
for i in "${!scenarios[@]}"; do
  if [ "${completed[$i]}" = false ]; then
    current="${scenarios[$i]}"
    record_result FAIL 'incomplete: missing SCENARIO_RESULT'
  fi
  case "${statuses[$i]}" in
  PASS) pass_count=$((pass_count + 1)) ;;
  FAIL)
    fail_count=$((fail_count + 1))
    current="${scenarios[$i]}"
    record_result "" "${diagnostics[$i]}"
    ;;
  SKIP) skip_count=$((skip_count + 1)) ;;
  esac
done
if [ "$run_started" = true ] && [ "$run_finished" = false ]; then run_failure 'incomplete: missing RUN_RESULT'; fi
[ "${#scenarios[@]}" -gt 0 ] || run_failure 'no scenario results found'
overall_status=PASS
if [ "$fail_count" -gt 0 ] || [ -n "$run_detail" ]; then
  overall_status=FAIL
  [ -z "$run_diagnostics" ] || run_failure "$run_diagnostics"
fi

clean_detail() {
  local text="$1"
  text="${text//$'\t'/ }"
  text="${text//$'\r'/ }"
  printf '%s' "${text//$'\n'/ }"
}
results_dir="${results_file%/*}"
if [ "$results_dir" = "$results_file" ]; then results_dir=.; fi
mkdir -p -- "$results_dir"
temporary_results=$(mktemp "${results_file}.tmp.XXXXXX")
{
  printf '# gateway-api-scenario-results v1\n'
  printf 'version\t%s\n' "$(clean_detail "$version")"
  printf 'status\t%s\n' "$overall_status"
  printf 'counts\tpass=%s\tfail=%s\tskip=%s\n' "$pass_count" "$fail_count" "$skip_count"
  if [ -n "$run_detail" ]; then printf 'detail\t%s\n' "$(clean_detail "$run_detail")"; fi
  for i in "${!scenarios[@]}"; do
    rerun=-
    if [ "${statuses[$i]}" = FAIL ]; then rerun="mise run //scenarios/${scenarios[$i]}:start --delete"; fi
    printf 'scenario\t%s\t%s\t%s\t%s\n' "${scenarios[$i]}" "${statuses[$i]}" "$rerun" "$(clean_detail "${details[$i]}")"
  done
} >"$temporary_results"
mv -f -- "$temporary_results" "$results_file"
temporary_results=""

echo "Scenario results (Cilium $version)"
if [ "${#scenarios[@]}" -eq 0 ]; then echo '  No scenario results found'; fi
for i in "${!scenarios[@]}"; do
  printf '  %-4s  %s' "${statuses[$i]}" "${scenarios[$i]}"
  if [ -n "${details[$i]}" ]; then printf '  %s' "${details[$i]}"; fi
  printf '\n'
done
printf 'Summary: %s PASS, %s FAIL, %s SKIP (overall %s)\n' "$pass_count" "$fail_count" "$skip_count" "$overall_status"
if [ -n "$run_detail" ]; then echo "Run details: $run_detail"; fi
echo "Results file: $results_file"
if [ "$fail_count" -gt 0 ]; then
  echo 'Rerun failed scenarios:'
  for i in "${!scenarios[@]}"; do
    if [ "${statuses[$i]}" = FAIL ]; then echo "  mise run //scenarios/${scenarios[$i]}:start --delete"; fi
  done
fi
exit 0
