#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=$(mktemp -d "${TEST_TMPDIR:-${TMPDIR:-/tmp}}/background-waits.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
export VERIFY_HELPERS="$repo_root/lib/verify-helpers.sh"

cat >"$work_dir/body.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090
source "$VERIFY_HELPERS"

# Record actual waits to prove that a failure does not leave later children unjoined.
wait() {
  local status=0
  builtin wait "$1" || status=$?
  printf '%s\n' "$1" >>"$CASE_DIR/waited"
  return "$status"
}

pids=()
(exit "$FIRST_STATUS") &
pids+=("$!")
(exit "$SECOND_STATUS") &
pids+=("$!")
printf '%s\n' "${pids[@]}" >"$CASE_DIR/pids"
wait_pids "${pids[@]}"
echo 'continued' >"$CASE_DIR/continued"
EOF

check() {
  local name="$1" expected="$2" actual=0
  export FIRST_STATUS="$3" SECOND_STATUS="$4" CASE_DIR="$work_dir/$name"
  mkdir "$CASE_DIR"
  bash "$work_dir/body.sh" >"$CASE_DIR/output" 2>&1 || actual=$?
  if [ "$actual" -ne "$expected" ]; then
    cat "$CASE_DIR/output" >&2
    echo "FAIL: $name returned $actual, expected $expected" >&2
    exit 1
  fi
  cmp "$CASE_DIR/pids" "$CASE_DIR/waited"
  if [ "$expected" -eq 0 ]; then
    [ -f "$CASE_DIR/continued" ]
  else
    [ ! -e "$CASE_DIR/continued" ]
  fi
  printf 'PASS: %s\n' "$name"
}

check all-success 0 0 0
check first-child-fails 1 7 0
check last-child-fails 1 0 9
check both-children-fail 1 7 9
