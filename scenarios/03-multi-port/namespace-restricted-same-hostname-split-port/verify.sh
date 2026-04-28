#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_on_versions "1.19.1 1.19.3 1.20.0-pre.1" "namespace-restricted same-hostname split-port broken (cilium#42159 + cilium#44889)"

# --- Wait for resources ---
# Tier 1 — pods & certificates (parallel)
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=5s" \
  "certificate/ns-restricted-split-port-gateway-certificate -n gateway-system --for=condition=Ready --timeout=10s"

# Tier 2 — gateway
kubectl wait gateway/ns-restricted-same-hostname-split-port-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=5s

# Give the controller time to reconcile route status
sleep 5

# --- Check gateway listener attachedRoutes ---
restricted=$(kubectl get gateway/ns-restricted-same-hostname-split-port-gateway -n gateway-system \
  -o jsonpath='{.status.listeners[?(@.name=="https-restricted")].attachedRoutes}')
open=$(kubectl get gateway/ns-restricted-same-hostname-split-port-gateway -n gateway-system \
  -o jsonpath='{.status.listeners[?(@.name=="https-open")].attachedRoutes}')

echo "https-restricted attachedRoutes: ${restricted}"
echo "https-open attachedRoutes: ${open}"

# https-restricted (from: Same) should NOT accept cross-namespace route
if [ "$restricted" = "0" ]; then
  echo "PASS: https-restricted listener correctly rejects cross-namespace route"
else
  echo "FAIL: https-restricted listener has attachedRoutes=${restricted} (expected 0) — cilium#42159" >&2
  exit 1
fi

# https-open (from: All) SHOULD accept cross-namespace route
if [ "$open" = "1" ]; then
  echo "PASS: https-open listener correctly accepts cross-namespace route"
else
  echo "FAIL: https-open listener has attachedRoutes=${open} (expected 1) — cilium#42159" >&2
  exit 1
fi

# --- Traffic check on the open listener (port 50051) ---
retry_until 10 curl -kfsS --resolve "api.example.test:50051:127.0.0.1" https://api.example.test:50051/headers >/dev/null
echo "PASS: HTTPS traffic — api.example.test on port 50051 (open listener)"

# --- Negative: restricted listener must not serve the same-hostname route ---
# The cross-namespace route is rejected by the restricted listener (attachedRoutes=0),
# so traffic on port 443 for the same hostname should return 404.
# Currently broken: Cilium's data plane leaks the route from the open listener
# onto port 443 via shared envoy filter chains — cilium#42159 (data-plane half).
http_status=$(curl -kso /dev/null -w '%{http_code}' --resolve "api.example.test:443:127.0.0.1" https://api.example.test:443/headers || true)
if [ "$http_status" = "404" ]; then
  echo "PASS: restricted listener returns 404 for same hostname (listener isolation enforced)"
else
  echo "FAIL: restricted listener returned HTTP ${http_status} (expected 404) — data-plane half of cilium#42159" >&2
  exit 1
fi
