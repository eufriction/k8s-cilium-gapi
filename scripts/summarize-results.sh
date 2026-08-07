#!/usr/bin/env bash
# summarize-results.sh — summarize mise scenario output and write TSV results

set -euo pipefail

usage() {
  echo "Usage: $0 [--results FILE] [--cilium-version VERSION] [LOG_FILE|-]" >&2
  exit 2
}

results_file="${RUN_RESULTS:-run-all-results.tsv}"
version="${CILIUM_VERSION:-unknown}"
input_file="-"

while [ "$#" -gt 0 ]; do
  case "$1" in
  --results)
    [ "$#" -ge 2 ] || usage
    results_file="$2"
    shift 2
    ;;
  --cilium-version)
    [ "$#" -ge 2 ] || usage
    version="$2"
    shift 2
    ;;
  -h | --help)
    usage
    ;;
  -)
    input_file="-"
    shift
    ;;
  --)
    shift
    [ "$#" -le 1 ] || usage
    if [ "$#" -eq 1 ]; then input_file="$1"; fi
    shift || true
    ;;
  *)
    [ "$input_file" = "-" ] || usage
    input_file="$1"
    shift
    ;;
  esac
done

if [ "$input_file" != "-" ] && [ ! -f "$input_file" ]; then
  echo "ERROR: log file not found: ${input_file}" >&2
  exit 1
fi

input_path="$input_file"
temporary_input=""
if [ "$input_file" = "-" ]; then
  temporary_input=$(mktemp)
  input_path="$temporary_input"
  trap 'rm -f "$temporary_input"' EXIT
  cat >"$temporary_input"
fi

scenarios=()
statuses=()
details=()
current=""
found_index=-1

find_scenario() {
  found_index=-1
  for i in "${!scenarios[@]}"; do
    if [ "${scenarios[$i]}" = "$1" ]; then
      found_index=$i
      return 0
    fi
  done
}

ensure_scenario() {
  find_scenario "$1"
  if [ "$found_index" -lt 0 ]; then
    scenarios+=("$1")
    statuses+=("UNKNOWN")
    details+=("")
    found_index=$((${#scenarios[@]} - 1))
  fi
}

record_result() {
  local result="$1" detail="$2"
  [ -n "$current" ] || return 0
  ensure_scenario "$current"

  case "$result" in
  PASS)
    if [ "${statuses[$found_index]}" = "UNKNOWN" ]; then
      statuses[found_index]="PASS"
    fi
    ;;
  SKIP)
    if [ "${statuses[$found_index]}" != "FAIL" ]; then
      statuses[found_index]="SKIP"
    fi
    if [ -z "${details[$found_index]}" ]; then
      details[found_index]="$detail"
    fi
    ;;
  FAIL)
    if [ "${statuses[$found_index]}" != "SKIP" ]; then
      statuses[found_index]="FAIL"
    fi
    if [ -z "${details[$found_index]}" ]; then
      details[found_index]="$detail"
    fi
    ;;
  esac
}

while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" =~ //scenarios/([^:[:space:]]+):(start|verify|delete) ]]; then
    candidate="${BASH_REMATCH[1]}"
    if [ "$candidate" != "..." ]; then
      current="$candidate"
      ensure_scenario "$current"
    fi
  fi

  if [[ "$line" == *"SKIP:"* ]]; then
    record_result SKIP "${line#*SKIP:}"
  elif [[ "$line" == *"FAIL:"* ]]; then
    record_result FAIL "${line#*FAIL:}"
  elif [[ "$line" == *"PASS:"* ]]; then
    record_result PASS ""
  elif [[ "$line" == *"ERROR:"* || "$line" == *"Error:"* || "$line" == *"error:"* || "$line" == *"Task "*" failed"* ]]; then
    record_result FAIL "$line"
  fi
done <"$input_path"

for i in "${!scenarios[@]}"; do
  if [ "${statuses[$i]}" = "UNKNOWN" ]; then
    statuses[i]="FAIL"
    details[i]="no PASS or SKIP marker observed"
  fi
done

pass_count=0
fail_count=0
skip_count=0
for status in "${statuses[@]}"; do
  case "$status" in
  PASS) pass_count=$((pass_count + 1)) ;;
  FAIL) fail_count=$((fail_count + 1)) ;;
  SKIP) skip_count=$((skip_count + 1)) ;;
  esac
done

overall_status=PASS
if [ "$fail_count" -gt 0 ]; then
  overall_status=FAIL
fi

results_dir="${results_file%/*}"
if [ "$results_dir" = "$results_file" ]; then
  results_dir="."
fi
mkdir -p "$results_dir"
{
  printf '# gateway-api-scenario-results v1\n'
  printf 'version\t%s\n' "$version"
  printf 'status\t%s\n' "$overall_status"
  printf 'counts\tpass=%s\tfail=%s\tskip=%s\n' "$pass_count" "$fail_count" "$skip_count"
  for i in "${!scenarios[@]}"; do
    rerun="-"
    if [ "${statuses[$i]}" = "FAIL" ]; then
      rerun="mise run //scenarios/${scenarios[$i]}:start --delete"
    fi
    detail="${details[$i]//$'\t'/ }"
    detail="${detail//$'\r'/ }"
    printf 'scenario\t%s\t%s\t%s\t%s\n' \
      "${scenarios[$i]}" "${statuses[$i]}" "$rerun" "$detail"
  done
} >"$results_file"

echo "Scenario results (Cilium ${version})"
if [ "${#scenarios[@]}" -eq 0 ]; then
  echo "  No scenario results found"
else
  scenario_width=8
  for scenario in "${scenarios[@]}"; do
    if [ "${#scenario}" -gt "$scenario_width" ]; then
      scenario_width=${#scenario}
    fi
  done
  printf "  %-*s  %-6s  %s\n" "$scenario_width" "Scenario" "Status" "Details"
  printf "  %-*s  %-6s  %s\n" "$scenario_width" "--------" "------" "-------"
  for i in "${!scenarios[@]}"; do
    printf "  %-*s  %-6s  %s\n" "$scenario_width" "${scenarios[$i]}" "${statuses[$i]}" "${details[$i]}"
  done
fi
printf 'Summary: %s PASS, %s FAIL, %s SKIP\n' "$pass_count" "$fail_count" "$skip_count"
echo "Results file: ${results_file}"

if [ "$fail_count" -gt 0 ]; then
  echo "Rerun failed scenarios:"
  for i in "${!scenarios[@]}"; do
    if [ "${statuses[$i]}" = "FAIL" ]; then
      echo "  mise run //scenarios/${scenarios[$i]}:start --delete"
    fi
  done
fi
