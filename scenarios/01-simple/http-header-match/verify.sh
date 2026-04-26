#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

# Tier 1: pods in parallel
wait_parallel \
  "pod/netshoot-client -n client --for=condition=Ready --timeout=60s" \
  "pod/api -n backend-a --for=condition=Ready --timeout=60s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=60s"

# Tier 2: gateway
kubectl wait gateway/header-match-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=120s

# Tier 3: routes in parallel
kubectl wait httproute/backend-a-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s &
kubectl wait httproute/backend-b-route -n backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s &
wait

# Test 1: X-Version: v1 → backend-a
body=$(curl -fsS -H 'Host: api.example.test' -H 'X-Version: v1' http://localhost/headers)
echo "$body" | grep -q '"X-Routed-To"' && echo "$body" | grep -q 'backend-a' \
  || { echo "FAIL: X-Version: v1 not routed to backend-a" >&2; echo "$body" >&2; exit 1; }
echo "PASS: X-Version: v1 → backend-a"

# Test 2: X-Version: v2 → backend-b
body=$(curl -fsS -H 'Host: api.example.test' -H 'X-Version: v2' http://localhost/headers)
echo "$body" | grep -q '"X-Routed-To"' && echo "$body" | grep -q 'backend-b' \
  || { echo "FAIL: X-Version: v2 not routed to backend-b" >&2; echo "$body" >&2; exit 1; }
echo "PASS: X-Version: v2 → backend-b"

# Test 3: No X-Version header → 404 (no matching route)
http_code=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: api.example.test' http://localhost/headers)
[ "$http_code" = "404" ] || { echo "FAIL: expected 404 without X-Version header, got $http_code" >&2; exit 1; }
echo "PASS: no X-Version header → 404 (no matching route)"
