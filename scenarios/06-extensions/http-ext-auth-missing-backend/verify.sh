#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "HTTPRoute ExternalAuth requires branch build"
gateway_ports ext-auth-missing-backend-gateway gateway-system 80

HOST=ext-auth-missing-backend.example.test
BASE_URL="http://localhost:${PORT_80}"

# Tier 1: backend pod
kubectl wait pod/api -n backend-a \
  --for=condition=Ready --timeout="${POD_READY_TIMEOUT:-10}s"

if kubectl get service/external-authz-missing -n auth >/dev/null 2>&1; then
  echo "FAIL: external-authz-missing Service exists, but this scenario requires it to be absent" >&2
  exit 1
fi
echo "PASS: configured ext_authz backend Service is missing"

# Tier 2: gateway
wait_gateway ext-auth-missing-backend-gateway gateway-system

# Tier 3: route
wait_route httproute ext-auth-missing-backend-route backend-a
echo "PASS: HTTPRoute Accepted=True (route is attached to gateway)"

assert_listener_status ext-auth-missing-backend-gateway gateway-system http 1 HTTPRoute GRPCRoute

# A missing ext_authz backend must not allow the request through to api.
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
  echo "FAIL: expected HTTP 500 (fail-closed), got HTTP '${status_code}'" >&2
  exit 1
fi
echo "PASS: data plane fails closed (HTTP 500) when ext_authz backend is missing"
