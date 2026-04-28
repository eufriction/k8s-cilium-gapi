#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

# --- Wait for resources ---
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=5s"
kubectl wait gateway/ns-split-port-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=5s

# Give the controller time to reconcile route status
sleep 5

# --- Check gateway listener attachedRoutes ---
restricted=$(kubectl get gateway/ns-split-port-gateway -n gateway-system \
  -o jsonpath='{.status.listeners[?(@.name=="http-restricted")].attachedRoutes}')
open=$(kubectl get gateway/ns-split-port-gateway -n gateway-system \
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

# --- Traffic test on http-open (port 8080) ---
retry_until 10 curl -fsS -H 'Host: open.example.test' http://localhost:8080/headers >/dev/null
echo "PASS: HTTP traffic to open.example.test on port 8080 (open listener)"

# --- Negative: restricted listener rejects traffic ---
# Port 80 listener has no attached routes (cross-namespace rejected), so any
# request should get 404.
http_status=$(curl -so /dev/null -w '%{http_code}' -H 'Host: restricted.example.test' http://localhost/headers || true)
if [ "$http_status" = "404" ]; then
  echo "PASS: restricted listener returns 404 (no routes attached)"
else
  echo "FAIL: restricted listener returned HTTP ${http_status} (expected 404)" >&2
  exit 1
fi
