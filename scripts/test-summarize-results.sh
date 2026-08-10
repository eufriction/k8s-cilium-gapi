#!/usr/bin/env bash

set -euo pipefail

work_dir=$(mktemp -d "${TEST_TMPDIR:-${TMPDIR:-/tmp}}/summarize-results.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

cat >"$work_dir/run.log" <<'EOF'
[//scenarios/01-basic/http:start] $ run scenario
SCENARIO: /repo/scenarios/01-basic/http
PASS: basic HTTP scenario passed
[//scenarios/06-extensions/http-ext-auth…] $ run scenario
SCENARIO: /repo/scenarios/06-extensions/http-ext-auth-missing-backend
FAIL: expected HTTP 500 (fail-closed), got HTTP '200'
[//scenarios/04-route-admission/https-tl…] $ run scenario
SCENARIO: /repo/scenarios/04-route-admission/https-tls-kinds-shared-port
SKIP: known broken on Cilium 1.19.1
EOF

bash scripts/summarize-results.sh \
  --results "$work_dir/results.tsv" \
  --cilium-version branch \
  "$work_dir/run.log" >"$work_dir/summary.txt"

grep -F $'counts\tpass=1\tfail=1\tskip=1' "$work_dir/results.tsv" >/dev/null
grep -F $'scenario\t01-basic/http\tPASS\t-' "$work_dir/results.tsv" >/dev/null
grep -F $'scenario\t06-extensions/http-ext-auth-missing-backend\tFAIL\tmise run //scenarios/06-extensions/http-ext-auth-missing-backend:start --delete\t expected HTTP 500 (fail-closed), got HTTP '\''200'\''' "$work_dir/results.tsv" >/dev/null
grep -F $'scenario\t04-route-admission/https-tls-kinds-shared-port\tSKIP\t-\t known broken on Cilium 1.19.1' "$work_dir/results.tsv" >/dev/null
grep -F 'mise run //scenarios/06-extensions/http-ext-auth-missing-backend:start --delete' "$work_dir/summary.txt" >/dev/null

printf 'PASS: summarize-results handles truncated mise task labels\n'
