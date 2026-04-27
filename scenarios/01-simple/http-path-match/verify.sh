#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

# Tier 1: pods in parallel
wait_parallel \
  "pod/api -n backend-a --for=condition=Ready --timeout=5s" \
  "pod/api -n backend-b --for=condition=Ready --timeout=5s"

# Tier 2: gateway
kubectl wait gateway/path-match-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=5s

# Tier 3: routes in parallel
kubectl wait httproute/backend-a-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=5s &
kubectl wait httproute/backend-b-route -n backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=5s &
wait

# Warm up the HTTP listener
retry_until 10 curl -fsS -H 'Host: app.example.test' http://localhost/api/headers >/dev/null

# Test 1: /api/* → backend-a
body=$(curl -fsS -H 'Host: app.example.test' http://localhost/api/headers)
echo "$body" | grep -q '"X-Routed-To"' && echo "$body" | grep -q 'backend-a' \
  || { echo "FAIL: /api/headers not routed to backend-a" >&2; echo "$body" >&2; exit 1; }
echo "PASS: /api/headers → backend-a"

# Test 2: /* → backend-b
body=$(curl -fsS -H 'Host: app.example.test' http://localhost/headers)
echo "$body" | grep -q '"X-Routed-To"' && echo "$body" | grep -q 'backend-b' \
  || { echo "FAIL: /headers not routed to backend-b" >&2; echo "$body" >&2; exit 1; }
echo "PASS: /headers → backend-b"

# Test 3: Verify /api prefix takes precedence over / catch-all
body=$(curl -fsS -H 'Host: app.example.test' http://localhost/api/get)
echo "$body" | grep -q 'backend-a' \
  || { echo "FAIL: /api/get not routed to backend-a (prefix precedence)" >&2; echo "$body" >&2; exit 1; }
echo "PASS: /api/get → backend-a (prefix takes precedence over catch-all)"
