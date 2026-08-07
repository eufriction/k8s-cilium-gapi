#!/usr/bin/env bash
# verify-helpers.sh — version-conditional helpers for scenario verify scripts
#
# Source this file at the top of verify.sh (after setting REPO_ROOT):
#   source "${REPO_ROOT}/lib/verify-helpers.sh"

VERIFY_HELPERS_DIR="$(CDPATH="" cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/envoy-readiness.sh
source "${VERIFY_HELPERS_DIR}/envoy-readiness.sh"

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
    # intentional word splitting
    # shellcheck disable=SC2086
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

# retry_until <max_seconds> <command...>
#
# Time-boxed retry: keeps retrying a command with 1s sleeps until the deadline.
# The final attempt after the deadline runs with stderr to surface errors.
# Use this when you want a hard cap on wall-clock time.
#
# The deadline can be overridden globally via LISTENER_READY_TIMEOUT env var.
# When set, the env var acts as a floor — the effective deadline is the larger
# of the passed value and LISTENER_READY_TIMEOUT.
#
# Example:
#   retry_until 5 curl -kfsS --resolve "host:443:127.0.0.1" https://host/path >/dev/null
retry_until() {
  local deadline=$1
  shift
  # Allow env var to raise the floor (useful after cilium-agent restarts)
  local floor="${LISTENER_READY_TIMEOUT:-0}"
  if ((floor > deadline)); then deadline=$floor; fi
  local end=$((SECONDS + deadline))
  while ((SECONDS < end)); do
    if "$@" 2>/dev/null; then return 0; fi
    echo "  listener not ready, retrying in 1s..." >&2
    sleep 1
  done
  "$@"
}

# assert_http <url> <expected_status> [<curl_args>...]
#
# Requests a URL and verifies its HTTP status code. Additional arguments are
# passed to curl before the URL, which supports headers and other request
# options used by scenario checks.
#
# Example:
#   assert_http "http://localhost:${PORT_80}/headers" 200 \
#     -H 'Host: app.example.test'
assert_http() {
  local url="$1" expected="$2"
  shift 2
  local status

  # Keep the status assertion responsible for reporting connection failures as
  # HTTP 000 instead of letting curl's non-zero exit status bypass the check.
  status=$(curl -s -o /dev/null -w '%{http_code}' "$@" "$url" || true)
  if [ "$status" != "$expected" ]; then
    envoy_assert_http_failure_class "$url" "$status" "$expected"
    return 1
  fi
  echo "PASS: $url → HTTP $expected"
}

# assert_body <url> <grep_pattern> [<curl_args>...]
#
# Requests a URL and verifies that its response body matches a case-insensitive
# grep pattern. Additional arguments are passed to curl before the URL.
#
# Example:
#   assert_body "http://localhost:${PORT_80}/headers" 'x-waf-result' \
#     -H 'Host: app.example.test'
assert_body() {
  local url="$1" pattern="$2"
  shift 2
  local body

  if ! body=$(curl -fsS "$@" "$url"); then
    echo "FAIL: $url → unable to retrieve response body" >&2
    return 1
  fi
  if ! printf '%s\n' "$body" | grep -i -- "$pattern" >/dev/null; then
    echo "FAIL: $url body missing '$pattern'" >&2
    echo "$body" >&2
    return 1
  fi
  echo "PASS: $url body contains '$pattern'"
}

# assert_redirect <url> <location_pattern> [<curl_args>...]
#
# Requests the headers for a URL and verifies that the Location header matches
# the supplied case-sensitive grep pattern. Additional arguments are passed to
# curl before the URL.
#
# Example:
#   assert_redirect "http://localhost:${PORT_80}/" '^https://' \
#     -H 'Host: redirect.example.test'
assert_redirect() {
  local url="$1" expected="$2"
  shift 2
  local headers location

  if ! headers=$(curl -sS -I "$@" "$url"); then
    echo "FAIL: $url → unable to retrieve response headers" >&2
    return 1
  fi
  location=$(printf '%s\n' "$headers" | grep -i '^location:' | tr -d '\r' | awk '{print $2}' || true)
  if ! printf '%s\n' "$location" | grep -- "$expected" >/dev/null; then
    echo "FAIL: $url redirect → $location (expected match '$expected')" >&2
    return 1
  fi
  echo "PASS: $url redirects to $location"
}

# wait_gateway <name> <namespace> [<condition>]
#
# Waits for a Gateway condition to become True. The condition defaults to
# Accepted and the timeout can be overridden with GW_READY_TIMEOUT.
wait_gateway() {
  local name="$1" ns="$2" condition="${3:-Accepted}"
  kubectl wait "gateway/$name" -n "$ns" \
    --for="jsonpath={.status.conditions[?(@.type==\"$condition\")].status}=True" \
    --timeout="${GW_READY_TIMEOUT:-30}s"
}

# wait_route <kind> <name> <namespace> [<condition>]
#
# Waits for a route parent condition to become True. The condition defaults to
# Accepted and the timeout can be overridden with ROUTE_READY_TIMEOUT.
wait_route() {
  local kind="$1" name="$2" ns="$3" condition="${4:-Accepted}"
  kubectl wait "$kind/$name" -n "$ns" \
    --for="jsonpath={.status.parents[0].conditions[?(@.type==\"$condition\")].status}=True" \
    --timeout="${ROUTE_READY_TIMEOUT:-30}s"
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

# gateway_ports <gateway-name> <namespace> <port> [<port> ...]
#
# Resolves host-mapped ports for a gateway and sets PORT_<n> variables in the
# caller's scope.  Does ONE kubectl + docker lookup per call regardless of how
# many ports are requested.
#
# In hostNetwork mode (no kindccm proxy), ports map 1:1 so PORT_<n>=<n>.
# In LB mode (cloud-provider-kind running), looks up the kindccm Docker
# container for the gateway's LB IP and extracts the host-mapped port for each
# requested service port.
#
# Example:
#   gateway_ports my-gw gateway-system 80 443 50051
#   curl http://localhost:${PORT_80}/headers
#   curl --resolve "host:${PORT_443}:127.0.0.1" https://host:${PORT_443}/path
#   grpcurl -insecure localhost:${PORT_50051} ...
gateway_ports() {
  local gw="$1" ns="$2"
  shift 2
  local svc_name="cilium-gateway-${gw}"

  # Wait for the service to exist and check its type.
  # In LB mode the service is type LoadBalancer and we must wait for
  # cloud-provider-kind to assign an external IP + create a kindccm container.
  local lb_ip="" svc_type=""
  local deadline=$((SECONDS + ${GATEWAY_PORTS_TIMEOUT:-60}))

  while ((SECONDS < deadline)); do
    # `|| true` prevents a transient NotFound (exit != 0) from tripping the
    # caller's `set -e` and silently killing the whole verify.sh — that
    # would defeat this retry loop entirely, since svc not existing yet is
    # an expected, normal condition here.
    svc_type=$(kubectl get svc "${svc_name}" -n "${ns}" \
      -o jsonpath='{.spec.type}' 2>/dev/null || true)
    if [ -z "$svc_type" ]; then
      # Service doesn't exist yet — Cilium hasn't reconciled the Gateway
      sleep 1
      continue
    fi
    if [ "$svc_type" != "LoadBalancer" ]; then
      # Not LB mode — hostNetwork fallback (ports map 1:1)
      for p in "$@"; do
        printf -v "PORT_${p}" '%s' "${p}"
      done
      return
    fi
    # Service is LoadBalancer — wait for ingress IP
    lb_ip=$(kubectl get svc "${svc_name}" -n "${ns}" \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [ -n "$lb_ip" ]; then
      break
    fi
    sleep 1
  done

  if [ -z "$lb_ip" ]; then
    echo "INFRA: gateway_ports — no LB IP for ${svc_name} after ${GATEWAY_PORTS_TIMEOUT:-60}s" >&2
    return 2
  fi

  # Resolve every requested port by re-scanning live kindccm containers on
  # every attempt, rather than committing to a single container id up front.
  # cloud-provider-kind can recreate its proxy container (new container id)
  # when a new LB port appears on an existing IP, e.g. right after a fresh
  # Gateway is created during rapid scenario churn. Polling a fixed, possibly
  # stale container id would wait forever for a port it will never gain.
  local remaining=("$@")
  local port_deadline=$((SECONDS + ${GATEWAY_PORT_TIMEOUT:-60}))
  while ((SECONDS < port_deadline)) && ((${#remaining[@]} > 0)); do
    local cid=""
    while IFS= read -r id; do
      local ip
      ip=$(docker inspect "$id" \
        --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' 2>/dev/null || true)
      if echo "$ip" | grep -qw "$lb_ip"; then
        cid="$id"
        break
      fi
    done < <(docker ps --filter "name=kindccm" --format '{{.ID}}' 2>/dev/null)

    if [ -n "$cid" ]; then
      local still_missing=()
      for p in "${remaining[@]}"; do
        local mapped
        mapped=$(docker port "$cid" "${p}/tcp" 2>/dev/null | head -1 | cut -d: -f2 || true)
        if [ -n "$mapped" ]; then
          printf -v "PORT_${p}" '%s' "$mapped"
        else
          still_missing+=("$p")
        fi
      done
      # Bash 3.2 (macOS system bash) treats `"${arr[@]}"` on an empty array
      # as an unbound variable under `set -u`, which would kill the whole
      # verify.sh via `set -e`. Guard every expansion of a possibly-empty
      # array.
      if ((${#still_missing[@]} > 0)); then
        remaining=("${still_missing[@]}")
      else
        remaining=()
      fi
    fi
    ((${#remaining[@]} == 0)) && break
    sleep 1
  done

  if ((${#remaining[@]} > 0)); then
    for p in "${remaining[@]}"; do
      echo "INFRA: gateway_ports — docker port ${p}/tcp not mapped for LB IP ${lb_ip}" >&2
    done
    return 2
  fi

  # Do not start data-plane assertions until every Cilium Envoy has the
  # Gateway listener, route configuration, and reserved:ingress policy.
  envoy_gateway_ready "$gw" "$ns"
}

# skip_on_versions <versions> [message]
#
# If CILIUM_VERSION matches any version in the space-separated list,
# prints a SKIP message and exits 0.
# Use at the top of a verify script to skip known-broken scenarios.
skip_on_versions() {
  local versions="$1"
  local cilium_version="${CILIUM_VERSION:-}"
  local msg="${2:-known broken on Cilium ${cilium_version}}"
  for _v in $versions; do
    if [ "$_v" = "$cilium_version" ]; then
      echo "SKIP: ${msg}"
      exit 0
    fi
  done
}
