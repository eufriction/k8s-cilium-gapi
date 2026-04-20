#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../.." && pwd)"
kubectl wait pod/netshoot-client -n client --for=condition=Ready --timeout=60s
kubectl wait pod/api -n backend-a --for=condition=Ready --timeout=60s
kubectl wait pod/api -n backend-b --for=condition=Ready --timeout=60s
kubectl wait gateway/multi-namespace-gateway -n gateway-system --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
kubectl wait httproute/backend-a-route -n backend-a --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
kubectl wait httproute/backend-b-route -n backend-b --for='jsonpath={.status.parents[0].conditions[?(@.type=="Accepted")].status}=True' --timeout=120s
curl -fsS -H 'Host: backend-a.example.test' http://localhost/headers >/dev/null
echo "PASS: backend-a HTTP"
curl -fsS -H 'Host: backend-b.example.test' http://localhost/headers >/dev/null
echo "PASS: backend-b HTTP"

# cilium/cilium#43881 — Accepted message
msg=$(kubectl get httproute/backend-a-route -n backend-a -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
[ "$msg" = "Accepted HTTPRoute" ] || { echo "FAIL: backend-a-route message='$msg'" >&2; exit 1; }
echo "PASS: backend-a-route Accepted message = '$msg'"

msg=$(kubectl get httproute/backend-b-route -n backend-b -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}')
[ "$msg" = "Accepted HTTPRoute" ] || { echo "FAIL: backend-b-route message='$msg'" >&2; exit 1; }
echo "PASS: backend-b-route Accepted message = '$msg'"
