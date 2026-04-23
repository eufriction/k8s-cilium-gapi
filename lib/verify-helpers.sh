#!/usr/bin/env bash
# verify-helpers.sh — version-conditional helpers for scenario verify scripts
#
# Source this file at the top of verify.sh (after setting REPO_ROOT):
#   source "${REPO_ROOT}/lib/verify-helpers.sh"

# retry <max_attempts> <sleep_seconds> <command...>
#
# Retries a command up to max_attempts times with sleep_seconds between attempts.
# Intermediate failures suppress stderr; the final attempt runs normally so
# errors propagate. Use this to absorb transient Envoy listener startup latency
# after kubectl wait succeeds (SSL_ERROR_SYSCALL / connection-refused race).
#
# Example:
#   retry 5 2 curl -kfsS --resolve "host:443:127.0.0.1" https://host/path >/dev/null
retry() {
  local max=$1 sleep_s=$2; shift 2
  for ((i=1; i<max; i++)); do
    if "$@" 2>/dev/null; then return 0; fi
    echo "  listener not ready, retrying in ${sleep_s}s ($i/$((max-1)))..." >&2
    sleep "$sleep_s"
  done
  "$@"
}

# assert_msg <actual> <env_var_name> <resource_label>
#
# Compares an actual status message against the value of the named env var.
# If the env var is empty/unset, the check is skipped (exit 0).
# Prints PASS/FAIL and returns 0/1.
assert_msg() {
  local actual="$1" var_name="$2" resource="$3"
  local expected="${!var_name}"

  if [ -z "$expected" ]; then
    echo "SKIP: ${resource} message check — ${var_name} not set"
    return 0
  fi
  if [ "$actual" = "$expected" ]; then
    echo "PASS: ${resource} Accepted message = '${actual}'"
    return 0
  fi
  echo "FAIL: ${resource} message='${actual}' (expected '${expected}' from ${var_name})" >&2
  return 1
}

# skip_if <env_var_name> [message]
#
# If the named env var is "true", prints a SKIP message and exits 0.
# Use at the top of a verify script to skip the entire scenario.
skip_if() {
  local var_name="$1"
  local msg="${2:-known bug (${var_name}=true)}"
  if [ "${!var_name}" = "true" ]; then
    echo "SKIP: ${msg}"
    exit 0
  fi
}
