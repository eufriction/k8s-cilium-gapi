#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_if X_ALLOWED_ROUTES_NAMESPACES_BROKEN "allowedRoutes.namespaces per-listener enforcement broken (cilium#42159)"

# --- Wait for resources ---
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=60s" \
  "certificate/ns-shared-port-gateway-certificate -n gateway-system --for=condition=Ready --timeout=180s"
kubectl wait gateway/ns-shared-port-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=120s

# Give the controller time to reconcile route status
sleep 5

# --- Check gateway listener attachedRoutes ---
restricted=$(kubectl get gateway/ns-shared-port-gateway -n gateway-system \
  -o jsonpath='{.status.listeners[?(@.name=="https-restricted")].attachedRoutes}')
open=$(kubectl get gateway/ns-shared-port-gateway -n gateway-system \
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

# --- Traffic check on open listener ---
retry_until 10 curl -kfsS --resolve "open.example.test:443:127.0.0.1" https://open.example.test/headers >/dev/null
echo "PASS: HTTPS traffic to open.example.test on port 443"
