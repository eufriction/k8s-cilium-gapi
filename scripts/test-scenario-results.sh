#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d "${TEST_TMPDIR:-${TMPDIR:-/tmp}}/scenario-results.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/bin" "$work_dir/scenarios/group/example"
export PATH="$work_dir/bin:$PATH"
export RESULT_HELPER="$repo_root/lib/scenario-result.sh"
export SCENARIO_ROOT="$work_dir/scenarios/group/example"
export MOCK_CALLS="$work_dir/calls"

cat >"$work_dir/bin/mock-apply" <<'EOF'
#!/usr/bin/env bash
printf 'apply\n' >>"$MOCK_CALLS"
exit "$MOCK_APPLY_STATUS"
EOF
cat >"$work_dir/bin/mise" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MOCK_CALLS"
echo 'PASS: cleanup completed'
exit "$MOCK_TASK_STATUS"
EOF
chmod +x "$work_dir/bin/mock-apply" "$work_dir/bin/mise"
cat >"$work_dir/body.sh" <<'EOF'
#!/usr/bin/env bash
# shellcheck disable=SC1090
source "$RESULT_HELPER" "$SCENARIO_ROOT"
mock-apply | cat
mise run :verify --delete
EOF

check() {
  local name="$1" expected="$2" outcome="$3" actual=0
  : >"$MOCK_CALLS"
  bash "$work_dir/body.sh" >"$work_dir/output" 2>&1 || actual=$?
  if [ "$actual" -ne "$expected" ] ||
    ! grep -Fx "$(printf 'SCENARIO_RESULT\tgroup/example\t%s\t%s' "$outcome" "$expected")" "$work_dir/output" >/dev/null; then
    cat "$work_dir/output" >&2
    echo "FAIL: $name returned $actual, expected $expected/$outcome" >&2
    exit 1
  fi
  printf 'PASS: %s\n' "$name"
}

export CILIUM_VERSION=branch SCENARIO_SKIP_VERSIONS='1.19.10 1.20.4'
export MOCK_APPLY_STATUS=0 MOCK_TASK_STATUS=0
check success 0 PASS
grep -Fx 'run :verify --delete' "$MOCK_CALLS" >/dev/null

export MOCK_APPLY_STATUS=7
check apply-pipeline-failure 7 FAIL
[ "$(cat "$MOCK_CALLS")" = apply ]

export MOCK_APPLY_STATUS=0 MOCK_TASK_STATUS=7
check verify-failure-cleanup-pass 7 FAIL
export MOCK_TASK_STATUS=9
check cleanup-failure 9 FAIL

export CILIUM_VERSION=1.20.4
check unsupported-version 0 SKIP
[ ! -s "$MOCK_CALLS" ]
