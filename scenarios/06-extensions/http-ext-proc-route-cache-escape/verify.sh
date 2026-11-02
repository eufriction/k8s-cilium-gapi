#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "ext_proc ExtensionRef requires branch build"

require_crd ciliumenvoyextprocfilters.cilium.io \
  "run against a branch build with ext_proc support"

gateway_ports route-cache-escape-gateway gateway-system 80

HOST=route-cache-escape.example.test
BASE_URL="http://localhost:${PORT_80}"

# Tier 1: pods and deployments in parallel
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "deployment/route-mutator-extproc -n gateway-system --for=condition=Available --timeout=30s" \
  "deployment/external-authz -n auth --for=condition=Available --timeout=30s"

# Tier 2: gateway
wait_gateway route-cache-escape-gateway gateway-system

# Tier 3: route
wait_route httproute route-cache-escape-route backend-a
wait_route httproute route-cache-escape-route backend-a ResolvedRefs

assert_listener_status route-cache-escape-gateway gateway-system http 1 HTTPRoute GRPCRoute

# Warm up the HTTP listener with the public path
retry_until 10 curl -fsS -H "Host: ${HOST}" "${BASE_URL}/anything/public/warmup" >/dev/null

# --- Test 1: the public rule is genuinely unauthenticated ---
# This is the rule an escaping request would land on, so establish that it
# serves without a token and that the processor is not attached to it.
public_body=$(curl -fsS -H "Host: ${HOST}" "${BASE_URL}/anything/public/data")
if ! printf '%s\n' "$public_body" | grep -qi 'public-rule'; then
  echo "FAIL: /anything/public not served by the public rule" >&2
  printf '%s\n' "$public_body" >&2
  exit 1
fi
if printf '%s\n' "$public_body" | grep -qi 'x-route-mutator'; then
  echo "FAIL: /anything/public shows x-route-mutator — the processor is attached to the wrong rule" >&2
  printf '%s\n' "$public_body" >&2
  exit 1
fi
echo "PASS: /anything/public is unauthenticated and has no ext_proc filter"

# --- Test 2: the processor cannot route around ExternalAuth ---
# The processor rewrites :path into the public prefix and asks Envoy to clear
# the route cache. ext_proc runs before ext_authz, so a cleared cache resolves
# the public rule and skips authorization entirely.
wait_http_status "${BASE_URL}/anything/protected/data" 403 "${ENVOY_READY_TIMEOUT:-30}" \
  -H "Host: ${HOST}"
echo "PASS: /anything/protected without a token is denied — route cache retained"

# --- Test 3: the header mutation still applies ---
# Proves test 2 does not pass because the processor is inert: :path is
# rewritten to the public prefix, yet the request is still served by the
# protected rule and still passes through ExternalAuth.
body=$(curl -fsS -H "Host: ${HOST}" -H 'X-Authz-Token: allow' "${BASE_URL}/anything/protected/data")
for pattern in 'x-route-mutator' 'rewrote' 'protected-rule' 'x-ext-authz-result' '/anything/public/data'; do
  if ! printf '%s\n' "$body" | grep -qi -- "$pattern"; then
    echo "FAIL: /anything/protected response missing '${pattern}'" >&2
    printf '%s\n' "$body" >&2
    exit 1
  fi
done
if printf '%s\n' "$body" | grep -qi 'public-rule'; then
  echo "FAIL: /anything/protected served by the public rule — the route cache was cleared" >&2
  printf '%s\n' "$body" >&2
  exit 1
fi
echo "PASS: :path rewritten to the public prefix while the protected rule and ExternalAuth still applied"

# --- Test 4: the generated config pins the behaviour ---
# The preceding checks describe the effect. This one names the cause, so a
# regression is reported against the field that changed rather than against a
# timing-sensitive request.
ext_proc_config=$(kubectl get cec/cilium-gateway-route-cache-escape-gateway -n gateway-system -o json |
  jq -r '
    .spec.resources[]
    | .. | objects
    | select(.httpFilters? != null)
    | .httpFilters[]?
    | select(.name | startswith("envoy.filters.http.ext_proc/"))
    | tostring
  ')
if [ -z "$ext_proc_config" ]; then
  echo "FAIL: no ext_proc filter in cilium-gateway-route-cache-escape-gateway" >&2
  exit 1
fi
if ! printf '%s\n' "$ext_proc_config" | grep -qi 'RETAIN'; then
  echo "FAIL: ext_proc filter does not pin the route cache action to RETAIN" >&2
  printf '%s\n' "$ext_proc_config" >&2
  exit 1
fi
echo "PASS: ext_proc filter pins route_cache_action=RETAIN"
