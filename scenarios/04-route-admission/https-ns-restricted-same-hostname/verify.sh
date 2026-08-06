#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_on_versions "1.19.1 1.19.3 1.20.0-pre.1" "namespace-restricted same-hostname split-port broken (cilium#42159 + cilium#44889)"
gateway_ports ns-restricted-same-hostname-split-port-gateway gateway-system 443 50051

# --- Wait for resources ---
# Tier 1 — pods & certificates (parallel)
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=${POD_READY_TIMEOUT:-10}s" \
  "certificate/ns-restricted-split-port-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s"

# Tier 2 — gateway
wait_gateway ns-restricted-same-hostname-split-port-gateway gateway-system

# Give the controller time to reconcile route status
sleep 5

# --- Listener status assertions ---
assert_listener_status ns-restricted-same-hostname-split-port-gateway gateway-system https-restricted 0 HTTPRoute GRPCRoute
assert_listener_status ns-restricted-same-hostname-split-port-gateway gateway-system https-open 1 HTTPRoute GRPCRoute

# --- Traffic check on the open listener (port 50051) ---
retry_until 10 curl -kfsS --resolve "api.example.test:${PORT_50051}:127.0.0.1" https://api.example.test:"${PORT_50051}"/headers >/dev/null
echo "PASS: HTTPS traffic — api.example.test on port 50051 (open listener)"

# --- Negative: restricted listener must not serve the same-hostname route ---
# The cross-namespace route is rejected by the restricted listener (attachedRoutes=0),
# so traffic on port 443 for the same hostname should return 404.
# Currently broken: Cilium's data plane leaks the route from the open listener
# onto port 443 via shared envoy filter chains — cilium#42159 (data-plane half).
assert_http "https://api.example.test:${PORT_443}/headers" 404 \
  -k --resolve "api.example.test:${PORT_443}:127.0.0.1"
