#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "aggregate ext_proc ordering conflicts require a branch build"

require_crd ciliumenvoyextprocfilters.cilium.io \
  "run against a branch build with ext_proc support"
require_crd listenersets.gateway.networking.k8s.io \
  "install Gateway API with ListenerSet support"

namespace=ext-proc-ordering
controller=io.cilium/gateway-controller

assert_route_parent() {
  local kind="$1" route="$2" parent_kind="$3" parent_name="$4"
  local section="$5" port="$6" expected_status="$7" expected_reason="$8"
  local json
  json=$(kubectl get "$kind/$route" -n "$namespace" -o json 2>/dev/null) || return 1

  if ! jq -e \
    --arg controller "$controller" \
    --arg parent_kind "$parent_kind" \
    --arg parent_name "$parent_name" \
    --arg parent_namespace "$namespace" \
    --arg section "$section" \
    --argjson port "$port" \
    --arg status "$expected_status" \
    --arg reason "$expected_reason" '
      [
        .status.parents[]?
        | select(
            .controllerName == $controller
            and .parentRef.group == "gateway.networking.k8s.io"
            and .parentRef.kind == $parent_kind
            and .parentRef.name == $parent_name
            and .parentRef.namespace == $parent_namespace
            and (.parentRef.sectionName // "") == $section
            and (.parentRef.port // 0) == $port
          )
        | select(
            ([.conditions[]? | select(.type == "Accepted" and .status == $status and .reason == $reason)] | length) == 1
            and ([.conditions[]? | select(.type == "ResolvedRefs" and .status == "True")] | length) == 1
          )
      ]
      | length == 1
    ' <<<"$json" >/dev/null; then
    echo "FAIL: ${kind}/${route} parent ${parent_kind}/${parent_name}:${section}:${port} does not have Accepted=${expected_status}/${expected_reason}" >&2
    jq '.status.parents' <<<"$json" >&2
    return 1
  fi

  echo "PASS: ${kind}/${route} parent ${parent_kind}/${parent_name}:${section}:${port} has Accepted=${expected_status}/${expected_reason} and ResolvedRefs=True"
}

assert_route_parent_absent() {
  local kind="$1" route="$2" parent_kind="$3" parent_name="$4"
  local section="$5" port="$6"
  local json
  json=$(kubectl get "$kind/$route" -n "$namespace" -o json 2>/dev/null) || return 1

  if jq -e \
    --arg controller "$controller" \
    --arg parent_kind "$parent_kind" \
    --arg parent_name "$parent_name" \
    --arg parent_namespace "$namespace" \
    --arg section "$section" \
    --argjson port "$port" '
      any(
        .status.parents[]?;
        .controllerName == $controller
        and .parentRef.group == "gateway.networking.k8s.io"
        and .parentRef.kind == $parent_kind
        and .parentRef.name == $parent_name
        and .parentRef.namespace == $parent_namespace
        and (.parentRef.sectionName // "") == $section
        and (.parentRef.port // 0) == $port
      )
    ' <<<"$json" >/dev/null; then
    echo "FAIL: ${kind}/${route} still reports parent ${parent_kind}/${parent_name}:${section}:${port}" >&2
    jq '.status.parents' <<<"$json" >&2
    return 1
  fi

  echo "PASS: ${kind}/${route} no longer reports parent ${parent_kind}/${parent_name}:${section}:${port}"
}

assert_route_parent_rejected_without_conflict() {
  local kind="$1" route="$2" parent_name="$3" section="$4" port="$5"
  local json
  json=$(kubectl get "$kind/$route" -n "$namespace" -o json 2>/dev/null) || return 1

  if ! jq -e \
    --arg controller "$controller" \
    --arg parent_name "$parent_name" \
    --arg parent_namespace "$namespace" \
    --arg section "$section" \
    --argjson port "$port" '
      [
        .status.parents[]?
        | select(
            .controllerName == $controller
            and .parentRef.group == "gateway.networking.k8s.io"
            and .parentRef.kind == "Gateway"
            and .parentRef.name == $parent_name
            and .parentRef.namespace == $parent_namespace
            and (.parentRef.sectionName // "") == $section
            and (.parentRef.port // 0) == $port
          )
        | select(
            ([.conditions[]? | select(.type == "Accepted" and .status == "False" and .reason != "OrderingConflict")] | length) == 1
            and ([.conditions[]? | select(.type == "ResolvedRefs" and .status == "True")] | length) == 1
          )
      ]
      | length == 1
    ' <<<"$json" >/dev/null; then
    echo "FAIL: ${kind}/${route} rejected parent ${parent_name}:${section}:${port} was lost or overwritten" >&2
    jq '.status.parents' <<<"$json" >&2
    return 1
  fi

  echo "PASS: ${kind}/${route} rejected parent remains Accepted=False with ResolvedRefs=True"
}

restore_route_precedence() {
  local run_status=$? restore_status=0
  trap - EXIT

  if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
    exit "$run_status"
  fi

  echo "--- Restoring staged Gateway routes ---"
  if ! {
    kubectl delete \
      -f 30-foundation-route.yaml \
      -f 31-compatible-route.yaml \
      -f 32-conflicting-routes.yaml \
      --ignore-not-found --wait=true --timeout=60s >/dev/null &&
      sleep 1 &&
      kubectl apply -f 30-foundation-route.yaml >/dev/null &&
      sleep 1 &&
      kubectl apply -f 31-compatible-route.yaml >/dev/null &&
      sleep 1 &&
      kubectl apply -f 32-conflicting-routes.yaml >/dev/null
  }; then
    restore_status=1
    echo "FAIL: could not restore staged Gateway routes" >&2
  fi

  if ((run_status == 0 && restore_status != 0)); then
    run_status=$restore_status
  fi
  exit "$run_status"
}

wait_gateway ordering-gateway "$namespace"
wait_gateway ordering-other-gateway "$namespace"
kubectl wait listenerset/ordering-listeners -n "$namespace" \
  --for='jsonpath={.status.conditions[?(@.type=="Accepted")].status}=True' \
  --timeout="${GW_READY_TIMEOUT:-30}s"

foundation_timestamp=$(kubectl get httproute/00-b-before-c -n "$namespace" -o jsonpath='{.metadata.creationTimestamp}')
compatible_timestamp=$(kubectl get httproute/01-a-before-b -n "$namespace" -o jsonpath='{.metadata.creationTimestamp}')
conflict_timestamp=$(kubectl get httproute/http-reverse-conflict -n "$namespace" -o jsonpath='{.metadata.creationTimestamp}')
if ! [[ "$foundation_timestamp" < "$compatible_timestamp" ]] || ! [[ "$compatible_timestamp" < "$conflict_timestamp" ]]; then
  echo "FAIL: route creation timestamps do not preserve the intended precedence" >&2
  printf '  foundation=%s\n  compatible=%s\n  conflict=%s\n' \
    "$foundation_timestamp" "$compatible_timestamp" "$conflict_timestamp" >&2
  exit 1
fi
echo "PASS: route creation timestamps preserve foundation, compatible, conflict precedence"

# B<C followed by A<B is compatible and must produce A,B,C. The cycle rule
# C<D<A loses atomically, but its unique D node remains in the HCM chain.
retry_until 30 assert_cec_ext_proc_order cilium-gateway-ordering-gateway \
  "$namespace" "$namespace" order-a order-b order-c losing-only-d
retry_until 30 assert_cec_ext_proc_order cilium-gateway-ordering-other-gateway \
  "$namespace" "$namespace" order-c losing-only-d order-a

retry_until 30 assert_route_parent httproute 00-b-before-c \
  Gateway ordering-gateway direct 8080 True Accepted
retry_until 30 assert_route_parent httproute 01-a-before-b \
  Gateway ordering-gateway direct 8080 True Accepted
retry_until 30 assert_route_parent httproute http-reverse-conflict \
  Gateway ordering-gateway direct 8080 True OrderingConflict
retry_until 30 assert_route_parent grpcroute grpc-cycle-conflict \
  Gateway ordering-gateway direct 8080 True OrderingConflict
retry_until 30 assert_route_parent grpcroute grpc-cycle-conflict \
  ListenerSet ordering-listeners delegated 8080 True OrderingConflict
retry_until 30 assert_route_parent grpcroute grpc-cycle-conflict \
  Gateway ordering-other-gateway isolated 8081 True Accepted
retry_until 30 assert_route_parent_rejected_without_conflict grpcroute \
  grpc-cycle-conflict ordering-gateway missing 8080

echo "PASS: conflicts are scoped to accepted parents in one Gateway aggregate domain"

# Force Gateway B to reconcile after Gateway A has recorded an ordering
# conflict. Removing B first makes the later parent addition a deterministic
# aggregate-specific update instead of relying on initial informer ordering.
# Restore the staged inputs on both success and failure so standalone :verify
# runs remain repeatable.
trap restore_route_precedence EXIT
kubectl patch grpcroute/grpc-cycle-conflict -n "$namespace" --type=json \
  -p='[{"op":"replace","path":"/spec/parentRefs","value":[{"group":"gateway.networking.k8s.io","kind":"Gateway","name":"ordering-gateway","namespace":"ext-proc-ordering","sectionName":"direct","port":8080},{"group":"gateway.networking.k8s.io","kind":"ListenerSet","name":"ordering-listeners","namespace":"ext-proc-ordering","sectionName":"delegated","port":8080},{"group":"gateway.networking.k8s.io","kind":"Gateway","name":"ordering-gateway","namespace":"ext-proc-ordering","sectionName":"missing","port":8080}]}]' >/dev/null
retry_until 30 assert_route_parent grpcroute grpc-cycle-conflict \
  Gateway ordering-gateway direct 8080 True OrderingConflict
retry_until 30 assert_route_parent grpcroute grpc-cycle-conflict \
  ListenerSet ordering-listeners delegated 8080 True OrderingConflict
retry_until 30 assert_route_parent_absent grpcroute grpc-cycle-conflict \
  Gateway ordering-other-gateway isolated 8081

echo "PASS: Gateway A retains its conflict while Gateway B is absent"

kubectl patch grpcroute/grpc-cycle-conflict -n "$namespace" --type=json \
  -p='[{"op":"replace","path":"/spec/parentRefs","value":[{"group":"gateway.networking.k8s.io","kind":"Gateway","name":"ordering-gateway","namespace":"ext-proc-ordering","sectionName":"direct","port":8080},{"group":"gateway.networking.k8s.io","kind":"ListenerSet","name":"ordering-listeners","namespace":"ext-proc-ordering","sectionName":"delegated","port":8080},{"group":"gateway.networking.k8s.io","kind":"Gateway","name":"ordering-other-gateway","namespace":"ext-proc-ordering","sectionName":"isolated","port":8081},{"group":"gateway.networking.k8s.io","kind":"Gateway","name":"ordering-gateway","namespace":"ext-proc-ordering","sectionName":"missing","port":8080}]}]' >/dev/null
retry_until 30 assert_route_parent grpcroute grpc-cycle-conflict \
  Gateway ordering-gateway direct 8080 True OrderingConflict
retry_until 30 assert_route_parent grpcroute grpc-cycle-conflict \
  ListenerSet ordering-listeners delegated 8080 True OrderingConflict
retry_until 30 assert_route_parent grpcroute grpc-cycle-conflict \
  Gateway ordering-other-gateway isolated 8081 True Accepted

echo "PASS: Gateway B reconciliation preserves Gateway A's aggregate-specific OrderingConflict"

# Normal reconciliation must clear stale conflict reasons after declarations
# become compatible or the winning constraint disappears.
kubectl patch httproute/http-reverse-conflict -n "$namespace" --type=json \
  -p='[{"op":"replace","path":"/spec/rules/0/filters","value":[{"type":"ExtensionRef","extensionRef":{"group":"cilium.io","kind":"CiliumEnvoyExtProcFilter","name":"order-a"}},{"type":"ExtensionRef","extensionRef":{"group":"cilium.io","kind":"CiliumEnvoyExtProcFilter","name":"order-b"}}]}]' >/dev/null
retry_until 30 assert_route_parent httproute http-reverse-conflict \
  Gateway ordering-gateway direct 8080 True Accepted
retry_until 30 assert_route_parent grpcroute grpc-cycle-conflict \
  Gateway ordering-gateway direct 8080 True OrderingConflict
retry_until 30 assert_route_parent grpcroute grpc-cycle-conflict \
  ListenerSet ordering-listeners delegated 8080 True OrderingConflict

kubectl delete -f 30-foundation-route.yaml --wait=true --timeout=60s >/dev/null
retry_until 30 assert_route_parent grpcroute grpc-cycle-conflict \
  Gateway ordering-gateway direct 8080 True Accepted
retry_until 30 assert_route_parent grpcroute grpc-cycle-conflict \
  ListenerSet ordering-listeners delegated 8080 True Accepted
retry_until 30 assert_cec_ext_proc_order cilium-gateway-ordering-gateway \
  "$namespace" "$namespace" order-c losing-only-d order-a order-b
retry_until 30 assert_cec_ext_proc_order cilium-gateway-ordering-other-gateway \
  "$namespace" "$namespace" order-c losing-only-d order-a

echo "PASS: stale OrderingConflict reasons clear and translation remains deterministic"
