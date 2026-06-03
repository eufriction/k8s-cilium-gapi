#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

GW=https-tls-same-port-same-hostname-gateway
NS=gateway-system

# This is an invalid/unsupported combination: HTTPS termination and TLS
# passthrough have identical SNI matchers on the same port. Splitting by port
# cannot fix it, so Cilium should reject or mark the config conflicted.

# --- Wait for inputs to be ready enough for reconciliation ---
wait_parallel \
  "certificate/https-tls-same-port-same-hostname-certificate -n gateway-system --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-ca -n backend-b --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-server -n backend-b --for=condition=Ready --timeout=10s" \
  "certificate/backend-b-mtls-client -n backend-b --for=condition=Ready --timeout=10s"

# Give the controller time to reconcile route/listener status.
sleep 5

listener_condition() {
  local listener="$1" condition="$2"
  kubectl get gateway/"$GW" -n "$NS" \
    -o jsonpath="{.status.listeners[?(@.name==\"${listener}\")].conditions[?(@.type==\"${condition}\")].status}" 2>/dev/null || true
}

route_condition() {
  local kind="$1" name="$2" ns="$3" condition="$4"
  kubectl get "$kind/$name" -n "$ns" \
    -o jsonpath="{.status.parents[0].conditions[?(@.type==\"${condition}\")].status}" 2>/dev/null || true
}

https_accepted=$(listener_condition https Accepted)
https_conflicted=$(listener_condition https Conflicted)
tls_accepted=$(listener_condition tls Accepted)
tls_conflicted=$(listener_condition tls Conflicted)
http_route_accepted=$(route_condition httproute backend-a-web-route backend-a Accepted)
tls_route_accepted=$(route_condition tlsroute backend-b-mtls-route backend-b Accepted)

cat <<EOF
Observed status:
  listener/https Accepted=${https_accepted:-<empty>} Conflicted=${https_conflicted:-<empty>}
  listener/tls   Accepted=${tls_accepted:-<empty>} Conflicted=${tls_conflicted:-<empty>}
  httproute/backend-a-web-route Accepted=${http_route_accepted:-<empty>}
  tlsroute/backend-b-mtls-route Accepted=${tls_route_accepted:-<empty>}
EOF

if [ "$https_conflicted" = "True" ] || [ "$tls_conflicted" = "True" ] ||
  [ "$https_accepted" = "False" ] || [ "$tls_accepted" = "False" ] ||
  [ "$http_route_accepted" = "False" ] || [ "$tls_route_accepted" = "False" ]; then
  echo "PASS: same-port same-hostname HTTPS/TLS conflict is rejected or marked conflicted"
  exit 0
fi

echo "FAIL: same-port same-hostname HTTPS/TLS conflict was accepted; expected rejection/conflict" >&2
exit 1
