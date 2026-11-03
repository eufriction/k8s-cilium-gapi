#!/usr/bin/env bash
set -euo pipefail

work_dir=$(mktemp -d "${TEST_TMPDIR:-${TMPDIR:-/tmp}}/summarize-results.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
summarizer="$script_dir/summarize-results.sh"
export TMPDIR="$work_dir"
unset RUN_RESULTS CILIUM_VERSION
checks=0

contains() {
  if ! grep -F -- "$2" "$1" >/dev/null; then
    echo "FAIL: missing '$2' in $1" >&2
    cat "$work_dir/results.tsv" >&2
    exit 1
  fi
}
excludes() {
  if grep -F -- "$2" "$1" >/dev/null; then
    echo "FAIL: unexpected '$2' in $1" >&2
    cat "$work_dir/results.tsv" >&2
    exit 1
  fi
}
report() {
  printf '%b\n' "$@" >"$work_dir/run.log"
  bash "$summarizer" --results "$work_dir/results.tsv" --cilium-version branch \
    "$work_dir/run.log" >"$work_dir/summary.txt"
  contains "$work_dir/results.tsv" '# gateway-api-scenario-results v1'
  checks=$((checks + 1))
}
status() { contains "$work_dir/results.tsv" "$(printf 'status\t%s' "$1")"; }
scenario() { contains "$work_dir/results.tsv" "$(printf 'scenario\t%s\t%s\t' "$1" "$2")"; }

# Explicit records use authoritative ids, regardless of truncated/misleading labels.
report '[//scenarios/group/long…] SCENARIO_START\tgroup/http' \
  '[suite] [//scenarios/group/...:start] SCENARIO_RESULT\tgroup/http\tPASS\t0' \
  'SCENARIO_START\tgroup/bad' 'SCENARIO_RESULT\tgroup/bad\tFAIL\t2' \
  'SCENARIO_START\tgroup/skipped' 'SKIP: version unsupported' \
  'SCENARIO_RESULT\tgroup/skipped\tSKIP\t0'
status FAIL
scenario group/http PASS
scenario group/bad FAIL
scenario group/skipped SKIP
contains "$work_dir/results.tsv" $'counts\tpass=1\tfail=1\tskip=1'
contains "$work_dir/results.tsv" 'version unsupported'
contains "$work_dir/summary.txt" 'mise run //scenarios/group/bad:start --delete'
contains "$work_dir/summary.txt" '  PASS  group/http'
contains "$work_dir/summary.txt" '  FAIL  group/bad  SCENARIO_RESULT FAIL exited 2'
contains "$work_dir/summary.txt" '  SKIP  group/skipped'

# Long scenario names do not shift the status column.
report 'SCENARIO_START\tgroup/a-scenario-name-longer-than-the-old-forty-eight-character-column' \
  'SCENARIO_RESULT\tgroup/a-scenario-name-longer-than-the-old-forty-eight-character-column\tPASS\t0'
contains "$work_dir/summary.txt" '  PASS  group/a-scenario-name-longer-than-the-old-forty-eight-character-column'

# Silent setup failure and successful cleanup cannot override the terminal failure.
report 'SCENARIO_START\tgroup/http' 'PASS: cleanup succeeded' 'SCENARIO_RESULT\tgroup/http\tFAIL\t8'
status FAIL
scenario group/http FAIL
contains "$work_dir/results.tsv" 'exited 8'

# Handled scenario diagnostics cannot override terminal PASS or SKIP.
report 'RUN_START' 'SCENARIO_START\tgroup/http' 'INFRA: first probe unavailable' \
  'FAIL: first probe failed' 'ERROR: retrying probe' 'PASS: retry succeeded' \
  'SCENARIO_RESULT\tgroup/http\tPASS\t0' 'SCENARIO_START\tgroup/skipped' \
  'SKIP: unsupported version' 'Error: optional probe failed' \
  'SCENARIO_RESULT\tgroup/skipped\tSKIP\t0' 'RUN_RESULT\t0'
status PASS
scenario group/http PASS
scenario group/skipped SKIP
contains "$work_dir/results.tsv" $'counts\tpass=1\tfail=0\tskip=1'
contains "$work_dir/results.tsv" 'unsupported version'
excludes "$work_dir/results.tsv" 'probe'

# fixture:start tolerates image pull errors before falling back to local images.
report '[scenarios:run-all] RUN_START' \
  '[fixture:start] [images:load] Error response from daemon: pull access denied' \
  '[fixture:start] [images:load] WARN: pull failed for example/image, using local image' \
  '[fixture:start] PASS: local images loaded' \
  'SCENARIO_START\tgroup/http' 'SCENARIO_RESULT\tgroup/http\tPASS\t0' \
  '[fixture:delete] ERROR: first cleanup probe failed; retry succeeded' 'RUN_RESULT\t0'
status PASS
scenario group/http PASS
excludes "$work_dir/results.tsv" 'pull access denied'
excludes "$work_dir/results.tsv" 'cleanup probe'

# A terminal failure retains the diagnostic that explains it.
report 'SCENARIO_START\tgroup/http' 'FAIL: expected HTTP 200, got 503' \
  'PASS: cleanup succeeded' 'SCENARIO_RESULT\tgroup/http\tFAIL\t7'
status FAIL
scenario group/http FAIL
contains "$work_dir/results.tsv" 'expected HTTP 200, got 503'
contains "$work_dir/results.tsv" 'SCENARIO_RESULT FAIL exited 7'

# A standalone scenario log needs neither suite boundary.
report 'SCENARIO_START\tgroup/http' 'SCENARIO_RESULT\tgroup/http\tPASS\t0'
status PASS
scenario group/http PASS

# A nonzero terminal exit is a failure, including teardown-only failures.
report 'SCENARIO_START\tgroup/http' 'PASS: verify succeeded' 'Error: cleanup timed out' \
  'SCENARIO_RESULT\tgroup/http\tPASS\t9'
status FAIL
scenario group/http FAIL
contains "$work_dir/results.tsv" 'exited 9'
contains "$work_dir/results.tsv" 'Error: cleanup timed out'

report 'SCENARIO_START\tgroup/http' 'INFRA: verification interrupted' 'PASS: cleanup succeeded'
status FAIL
contains "$work_dir/results.tsv" 'incomplete: missing SCENARIO_RESULT'
contains "$work_dir/results.tsv" 'INFRA: verification interrupted'

# A suite must finish reporting after fixture cleanup, even when scenarios passed.
report 'RUN_START' 'SCENARIO_START\tgroup/http' 'SCENARIO_RESULT\tgroup/http\tPASS\t0'
status FAIL
scenario group/http PASS
contains "$work_dir/results.tsv" 'missing RUN_RESULT'
report 'RUN_START' 'SCENARIO_START\tgroup/http' 'SCENARIO_RESULT\tgroup/http\tPASS\t0' \
  '[//scenarios/group/http:delete] $ task finished' 'FAIL: fixture teardown failed' 'RUN_RESULT\t9'
status FAIL
scenario group/http PASS
contains "$work_dir/results.tsv" $'counts\tpass=1\tfail=0\tskip=0'
contains "$work_dir/results.tsv" 'RUN_RESULT exited 9'
contains "$work_dir/results.tsv" 'FAIL: fixture teardown failed'

# A head-truncated suite suffix cannot certify success without RUN_START.
report 'SCENARIO_START\tgroup/http' 'SCENARIO_RESULT\tgroup/http\tPASS\t0' 'RUN_RESULT\t0'
status FAIL
scenario group/http PASS
contains "$work_dir/results.tsv" 'RUN_RESULT without RUN_START'

# Malformed terminal records still fail, regardless of successful records.
report 'RUN_START' 'ERROR: fixture setup needed a retry' \
  'SCENARIO_RESULT\tgroup/http\tPASS' 'SCENARIO_RESULT\tgroup/http\tPASS\t0' 'RUN_RESULT\t0'
status FAIL
contains "$work_dir/results.tsv" 'malformed result record: SCENARIO_RESULT'
contains "$work_dir/results.tsv" 'ERROR: fixture setup needed a retry'
report 'RUN_START' 'SCENARIO_RESULT\tgroup/http\tPASS\t0' 'RUN_RESULT\tinvalid'
status FAIL
contains "$work_dir/results.tsv" 'malformed result record: RUN_RESULT'

# Legacy identification/skip prose and empty logs cannot certify success.
report 'SCENARIO: /repo/scenarios/group/legacy' 'SKIP: known bug' \
  '[//scenarios/group/other:verify] PASS: verified'
status FAIL
scenario group/legacy FAIL
scenario group/other FAIL
report ''
status FAIL
contains "$work_dir/results.tsv" $'counts\tpass=0\tfail=0\tskip=0'

# stdin, RUN_RESULTS, explicit overrides, and a successfully completed suite.
printf 'RUN_START\nSCENARIO_START\tgroup/http\nSCENARIO_RESULT\tgroup/http\tPASS\t0\nRUN_RESULT\t0\n' >"$work_dir/pass.log"
RUN_RESULTS="$work_dir/env.tsv" CILIUM_VERSION=custom bash "$summarizer" - <"$work_dir/pass.log" >"$work_dir/summary.txt"
contains "$work_dir/env.tsv" $'status\tPASS'
contains "$work_dir/env.tsv" $'version\tcustom'
RUN_RESULTS="$work_dir/unused.tsv" bash "$summarizer" --results "$work_dir/results.tsv" --cilium-version override \
  "$work_dir/pass.log" >"$work_dir/summary.txt"
contains "$work_dir/results.tsv" $'status\tPASS'
contains "$work_dir/results.tsv" $'version\toverride'
[ ! -e "$work_dir/unused.tsv" ]

# An incomplete snapshot replaces stale PASS; failed publication/read preserves it.
report 'RUN_START'
status FAIL
if grep -F $'scenario\t' "$work_dir/results.tsv" >/dev/null; then
  echo 'FAIL: stale scenario survived' >&2
  exit 1
fi
cp "$work_dir/results.tsv" "$work_dir/prior.tsv"
mkdir "$work_dir/bin"
printf '#!/bin/sh\nexit 23\n' >"$work_dir/bin/mv"
chmod +x "$work_dir/bin/mv"
if PATH="$work_dir/bin:$PATH" bash "$summarizer" --results "$work_dir/results.tsv" - <"$work_dir/pass.log" >"$work_dir/summary.txt" 2>&1; then
  echo 'FAIL: failed publication returned zero' >&2
  exit 1
fi
cmp "$work_dir/prior.tsv" "$work_dir/results.tsv"
printf '#!/bin/sh\nprintf "partial input\\n"\nexit 24\n' >"$work_dir/bin/cat"
chmod +x "$work_dir/bin/cat"
if PATH="$work_dir/bin:$PATH" bash "$summarizer" --results "$work_dir/results.tsv" "$work_dir/pass.log" >"$work_dir/summary.txt" 2>&1; then
  echo 'FAIL: failed read returned zero' >&2
  exit 1
fi
cmp "$work_dir/prior.tsv" "$work_dir/results.tsv"
if find "$work_dir" -name '*.tmp.*' -print | grep . >/dev/null; then
  echo 'FAIL: temporary file leaked' >&2
  exit 1
fi

printf 'PASS: summarize-results (%s logs, stdin/overrides, stale replacement, read/publication failures)\n' "$checks"
