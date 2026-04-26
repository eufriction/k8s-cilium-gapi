#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

kubectl wait pod/api -n backend-a --for=condition=Ready --timeout=60s
kubectl wait pod/netshoot-client -n client --for=condition=Ready --timeout=60s
kubectl wait certificate/redirect-gateway-certificate -n gateway-system --for=condition=Ready --timeout=120s
kubectl wait gateway/redirect-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
kubectl wait httproute/http-redirect -n gateway-system --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
kubectl wait httproute/backend-a-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s

# Test 1: HTTP request should get 301 redirect
http_code=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: redirect.example.test' http://localhost/)
[ "$http_code" = "301" ] || { echo "FAIL: expected HTTP 301, got $http_code" >&2; exit 1; }
echo "PASS: HTTP→HTTPS redirect returns 301"

# Test 2: Redirect Location header points to HTTPS
location=$(curl -s -I -H 'Host: redirect.example.test' http://localhost/ | grep -i '^location:' | tr -d '\r' | awk '{print $2}')
echo "$location" | grep -q '^https://' || { echo "FAIL: redirect Location not HTTPS: $location" >&2; exit 1; }
echo "PASS: redirect Location header is HTTPS ($location)"

# Test 3: HTTPS endpoint serves traffic
retry 5 2 curl -kfsS --resolve "redirect.example.test:443:127.0.0.1" https://redirect.example.test/headers >/dev/null
echo "PASS: HTTPS endpoint serves traffic"

# Test 4: Follow redirect end-to-end
retry 5 2 curl -kLfsS --resolve "redirect.example.test:443:127.0.0.1" --resolve "redirect.example.test:80:127.0.0.1" -H 'Host: redirect.example.test' http://localhost/headers >/dev/null
echo "PASS: HTTP→HTTPS redirect end-to-end (follow redirects)"
