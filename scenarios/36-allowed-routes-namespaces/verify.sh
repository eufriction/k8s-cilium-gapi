#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
skip_if X_ALLOWED_ROUTES_NAMESPACES_BROKEN "allowedRoutes.namespaces per-listener enforcement broken (cilium#42159)"

# --- Wait for resources ---
kubectl wait pod/api -n backend-a --for=condition=Ready --timeout=60s
kubectl wait gateway/allowed-routes-ns-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=120s

# Give the controller time to reconcile route status
sleep 5

# --- Check gateway listener attachedRoutes ---
restricted=$(kubectl get gateway/allowed-routes-ns-gateway -n gateway-system \
  -o jsonpath='{.status.listeners[?(@.name=="http-restricted")].attachedRoutes}')
open=$(kubectl get gateway/allowed-routes-ns-gateway -n gateway-system \
  -o jsonpath='{.status.listeners[?(@.name=="http-open")].attachedRoutes}')

echo "http-restricted attachedRoutes: ${restricted}"
echo "http-open attachedRoutes: ${open}"

# http-restricted (from: Same) should NOT accept cross-namespace route
if [ "$restricted" = "0" ]; then
  echo "PASS: http-restricted listener correctly rejects cross-namespace route"
else
  echo "FAIL: http-restricted listener has attachedRoutes=${restricted} (expected 0) — cilium#42159" >&2
  exit 1
fi

# http-open (from: All) SHOULD accept cross-namespace route
if [ "$open" = "1" ]; then
  echo "PASS: http-open listener correctly accepts cross-namespace route"
else
  echo "FAIL: http-open listener has attachedRoutes=${open} (expected 1) — cilium#42159" >&2
  exit 1
fi
