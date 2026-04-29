#!/usr/bin/env bash
# verify-helpers.sh — version-conditional helpers for scenario verify scripts
#
# Source this file at the top of verify.sh (after setting REPO_ROOT):
#   source "${REPO_ROOT}/lib/verify-helpers.sh"

# wait_parallel <wait_args...>
#
# Runs multiple `kubectl wait` calls in parallel and waits for all to finish.
# Each argument is a string of arguments passed to `kubectl wait`.
# Returns non-zero if any wait fails.
#
# Example:
#   wait_parallel \
#     "pod/api -n backend-a --for=condition=Ready --timeout=60s" \
#     "pod/api -n backend-b --for=condition=Ready --timeout=60s" \
#     "certificate/my-cert -n gateway-system --for=condition=Ready --timeout=180s"
wait_parallel() {
  local pids=() cmds=() rc=0
  for args in "$@"; do
    kubectl wait $args &
    pids+=($!)
    cmds+=("$args")
  done
  for i in "${!pids[@]}"; do
    if ! wait "${pids[$i]}"; then
      echo "FAIL: kubectl wait ${cmds[$i]}" >&2
      rc=1
    fi
  done
  return $rc
}

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

# retry_until <max_seconds> <command...>
#
# Time-boxed retry: keeps retrying a command with 1s sleeps until the deadline.
# The final attempt after the deadline runs with stderr to surface errors.
# Prefer this over `retry` when you want a hard cap on wall-clock time.
#
# Example:
#   retry_until 5 curl -kfsS --resolve "host:443:127.0.0.1" https://host/path >/dev/null
retry_until() {
  local deadline=$1; shift
  local end=$((SECONDS + deadline))
  while (( SECONDS < end )); do
    if "$@" 2>/dev/null; then return 0; fi
    echo "  listener not ready, retrying in 1s..." >&2
    sleep 1
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
  local expected="${!var_name:-}"

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

# assert_listener_status <gateway> <namespace> <listener> <expected_attached> [<expected_kind> ...]
#
# Verifies a gateway listener's attachedRoutes count and optionally its
# supportedKinds set (order-insensitive). Prints PASS/FAIL and returns 0/1.
#
# When no expected_kind args are given, only attachedRoutes is checked.
# When one or more expected_kind args are given, the supportedKinds set
# must match exactly (sorted comparison).
#
# Examples:
#   assert_listener_status my-gw gateway-system https 1
#   assert_listener_status my-gw gateway-system https 1 HTTPRoute
#   assert_listener_status my-gw gateway-system https 2 HTTPRoute GRPCRoute
assert_listener_status() {
  local gw="$1" ns="$2" listener="$3" expected_attached="$4"
  shift 4
  local expected_kinds=("$@")

  local actual_attached
  actual_attached=$(kubectl get "gateway/${gw}" -n "$ns" \
    -o jsonpath="{.status.listeners[?(@.name==\"${listener}\")].attachedRoutes}")

  if [ -z "$actual_attached" ]; then
    echo "FAIL: ${listener} listener — no attachedRoutes in gateway status (listener not found?)" >&2
    return 1
  fi

  if [ "$actual_attached" != "$expected_attached" ]; then
    echo "FAIL: ${listener} listener — attachedRoutes=${actual_attached} (expected ${expected_attached})" >&2
    kubectl get "gateway/${gw}" -n "$ns" \
      -o jsonpath="{range .status.listeners[?(@.name==\"${listener}\")]}{\"  supportedKinds=\"}{.supportedKinds[*].kind}{\"  conditions=\"}{.conditions}{\"\\n\"}{end}" >&2
    return 1
  fi

  # If no expected kinds specified, pass on attachedRoutes alone
  if [ ${#expected_kinds[@]} -eq 0 ]; then
    echo "PASS: ${listener} listener — attachedRoutes=${actual_attached}"
    return 0
  fi

  # Compare supportedKinds (sorted, space-separated)
  local actual_kinds_raw
  actual_kinds_raw=$(kubectl get "gateway/${gw}" -n "$ns" \
    -o jsonpath="{.status.listeners[?(@.name==\"${listener}\")].supportedKinds[*].kind}")
  local actual_sorted expected_sorted
  actual_sorted=$(echo "$actual_kinds_raw" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')
  expected_sorted=$(printf '%s\n' "${expected_kinds[@]}" | sort | tr '\n' ' ' | sed 's/ $//')

  if [ "$actual_sorted" != "$expected_sorted" ]; then
    echo "FAIL: ${listener} listener — attachedRoutes=${actual_attached} OK but supportedKinds=[${actual_sorted}] (expected [${expected_sorted}])" >&2
    return 1
  fi

  echo "PASS: ${listener} listener — attachedRoutes=${actual_attached}, supportedKinds=[${actual_sorted}]"
  return 0
}

# skip_on_versions <versions> [message]
#
# If CILIUM_VERSION matches any version in the space-separated list,
# prints a SKIP message and exits 0.
# Use at the top of a verify script to skip known-broken scenarios.
skip_on_versions() {
  local versions="$1"
  local msg="${2:-known broken on Cilium ${CILIUM_VERSION}}"
  for _v in $versions; do
    if [ "$_v" = "${CILIUM_VERSION}" ]; then
      echo "SKIP: ${msg}"
      exit 0
    fi
  done
}
