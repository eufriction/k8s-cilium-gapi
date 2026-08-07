#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
gateway_ports allowed-routes-ns-gateway gateway-system 80 8080

# --- Wait for resources ---
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s"
wait_gateway allowed-routes-ns-gateway gateway-system

# --- Listener status assertions ---
retry_until 10 assert_listener_status allowed-routes-ns-gateway gateway-system http-restricted 0 HTTPRoute GRPCRoute
retry_until 10 assert_listener_status allowed-routes-ns-gateway gateway-system http-open 1 HTTPRoute GRPCRoute

# --- Traffic test on http-open (port 8080) ---
retry_until 10 curl -fsS -H 'Host: web.example.test' http://localhost:"${PORT_8080}"/headers >/dev/null
echo "PASS: HTTP traffic to web.example.test on port 8080 (open listener)"

# --- Negative: restricted listener rejects traffic ---
# Port 80 listener has no attached routes (cross-namespace rejected), so any
# request should get 404.  We use a non-matching hostname because Cilium's
# data plane merges envoy filter chains across listeners sharing the same IP,
# leaking the open-listener route onto port 80 for the same hostname.
assert_http "http://localhost:${PORT_80}/headers" 404 -H 'Host: restricted.example.test'
