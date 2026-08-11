#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "ext_proc ExtensionRef requires branch build"

# Fast-fail if the CiliumEnvoyExtProcFilter CRD is absent: without it Cilium
# cannot observe the cross-namespace ref, so ResolvedRefs stays True and the
# ReferenceGrant enforcement check never fires.
require_crd ciliumenvoyextprocfilters.cilium.io \
  "run this scenario against a branch build with ext_proc support"

gateway_ports rg-gateway gateway-system 80

HOST=ext-proc-rg.example.test
BASE_URL="http://localhost:${PORT_80}"

# Tier 1: pods
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "deployment/coraza-waf-extproc -n gateway-system --for=condition=Available --timeout=30s"

# Tier 2: gateway
wait_gateway rg-gateway gateway-system

# Tier 3: route syntactically accepted by the gateway
wait_route httproute rg-route backend-a
echo "PASS: HTTPRoute Accepted=True (route is attached to gateway)"

# --- ReferenceGrant enforcement: ResolvedRefs must be False ---
# The deployed ReferenceGrant covers a *different* Service (ext-proc-other),
# so the actual backendRef (coraza-waf-extproc) is not permitted.
wait_route httproute rg-route backend-a ResolvedRefs False
echo "PASS: HTTPRoute ResolvedRefs=False"

reason=$(kubectl get httproute/rg-route -n backend-a \
  -o 'jsonpath={.status.parents[0].conditions[?(@.type=="ResolvedRefs")].reason}')
if [ "$reason" != "RefNotPermitted" ]; then
  echo "FAIL: expected ResolvedRefs reason=RefNotPermitted, got '${reason}'" >&2
  exit 1
fi
echo "PASS: ResolvedRefs reason=RefNotPermitted"

# --- Listener status: route is still attached (Accepted drives attachedRoutes) ---
assert_listener_status rg-gateway gateway-system http 1 HTTPRoute GRPCRoute

# --- Data plane: fail-closed because failureModeAllow=false ---
# Wait up to 30s for the data plane to settle. A 200 here would indicate
# fail-open behaviour (regression); a 500 confirms the filter blocks traffic.
echo "Waiting for data plane to settle as fail-closed..."
wait_http_status "${BASE_URL}/headers" 500 30 -H "Host: ${HOST}"
echo "PASS: data plane fails closed (HTTP 500) — ext_proc ref blocked by missing ReferenceGrant"
