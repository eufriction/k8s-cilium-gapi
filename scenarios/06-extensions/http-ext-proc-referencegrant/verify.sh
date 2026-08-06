#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "ext_proc ExtensionRef requires branch build"

# Fast-fail if the CiliumEnvoyExtProcFilter CRD is absent: without it Cilium
# cannot observe the cross-namespace ref, so ResolvedRefs stays True and the
# ReferenceGrant enforcement check never fires.
if ! kubectl get crd ciliumenvoyextprocfilters.cilium.io &>/dev/null; then
  echo "FAIL: CiliumEnvoyExtProcFilter CRD not installed — run this scenario against a branch build with ext_proc support" >&2
  exit 1
fi

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
kubectl wait httproute/rg-route -n backend-a \
  --for='jsonpath={.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}=False' \
  --timeout="${ROUTE_READY_TIMEOUT:-30}s"
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
deadline=$((SECONDS + 30))
status_code=""
while ((SECONDS < deadline)); do
  status_code=$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Host: ${HOST}" "${BASE_URL}/headers" 2>/dev/null) || true
  [ "$status_code" = "500" ] && break
  echo "  got HTTP ${status_code:-<no response>}, retrying in 1s..." >&2
  sleep 1
done
if [ "$status_code" != "500" ]; then
  echo "FAIL: expected HTTP 500 (fail-closed, failureModeAllow=false), got HTTP '${status_code}'" >&2
  exit 1
fi
echo "PASS: data plane fails closed (HTTP 500) — ext_proc ref blocked by missing ReferenceGrant"
