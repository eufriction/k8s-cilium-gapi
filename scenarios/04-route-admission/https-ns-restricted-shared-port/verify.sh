#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
gateway_ports ns-shared-port-gateway gateway-system 443

# --- Wait for resources ---
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "certificate/ns-shared-port-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s"
wait_gateway ns-shared-port-gateway gateway-system

# --- Listener status assertions ---
retry_until 10 assert_listener_status ns-shared-port-gateway gateway-system https-restricted 0 HTTPRoute GRPCRoute
retry_until 10 assert_listener_status ns-shared-port-gateway gateway-system https-open 1 HTTPRoute GRPCRoute

# --- Traffic check on open listener ---
retry_until 10 curl -kfsS --resolve "open.example.test:${PORT_443}:127.0.0.1" https://open.example.test:"${PORT_443}"/headers >/dev/null
echo "PASS: HTTPS traffic to open.example.test on port 443"
