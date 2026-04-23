#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"
kubectl wait pod/netshoot-client -n client --for=condition=Ready --timeout=60s
kubectl wait pod/api -n backend-a --for=condition=Ready --timeout=60s
kubectl wait pod/api -n backend-b --for=condition=Ready --timeout=60s
kubectl wait certificate/https-gateway-certificate -n gateway-system --for=condition=Ready --timeout=180s
kubectl wait gateway/https-multi-namespace-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
kubectl wait httproute/backend-a-https-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
kubectl wait httproute/backend-b-https-route -n backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
retry 5 2 curl -kfsS --resolve "https-a.example.test:443:127.0.0.1" https://https-a.example.test/headers >/dev/null
echo "PASS: https-a.example.test"
curl -kfsS --resolve "https-b.example.test:443:127.0.0.1" https://https-b.example.test/headers >/dev/null
echo "PASS: https-b.example.test"

# cilium/cilium#43881
msg=$(kubectl get httproute/backend-a-https-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
[ "$msg" = "Accepted HTTPRoute" ] || { echo "FAIL: backend-a-https-route message='$msg'" >&2; exit 1; }
echo "PASS: backend-a-https-route Accepted message = '$msg'"

msg=$(kubectl get httproute/backend-b-https-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
[ "$msg" = "Accepted HTTPRoute" ] || { echo "FAIL: backend-b-https-route message='$msg'" >&2; exit 1; }
echo "PASS: backend-b-https-route Accepted message = '$msg'"
