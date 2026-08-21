#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}/../../.." && pwd)"
source "${REPO_ROOT}/lib/verify-helpers.sh"

skip_on_versions "${SCENARIO_SKIP_VERSIONS:-}" "ext_proc ExtensionRef requires branch build"
require_crd ciliumenvoyextprocfilters.cilium.io \
  "run against a branch build with ext_proc support"

namespace=ext-proc-shared-backend
gateway_ns="gateway-system"
gateway=shared-backend-gateway
route=shared-backend-route
cec_name=cilium-gateway-${gateway}
ordinary_cluster="${namespace}:shared:8080"
grpc_cluster="grpc:${ordinary_cluster}"

wait_gateway "$gateway" "$gateway_ns"
wait_route httproute "$route" "$namespace"
wait_route httproute "$route" "$namespace" ResolvedRefs
assert_listener_status "$gateway" "$gateway_ns" http 1 HTTPRoute GRPCRoute

assert_shared_backend_clusters() {
  local cec_json
  cec_json=$(kubectl get "cec/${cec_name}" -n "$gateway_ns" -o json 2>/dev/null) || return 1

  if ! jq -e \
    --arg ordinary "$ordinary_cluster" \
    --arg grpc "$grpc_cluster" '
      def envoy_clusters:
        [
          .spec.resources[]?
          | .. | objects
          | select(."@type"? == "type.googleapis.com/envoy.config.cluster.v3.Cluster")
        ];
      def cluster($name): [envoy_clusters[] | select(.name? == $name)];
      def http_options($name):
        cluster($name)[0].typedExtensionProtocolOptions?
        ["envoy.extensions.upstreams.http.v3.HttpProtocolOptions"]?;

      (cluster($ordinary) | length) == 1
      and (cluster($grpc) | length) == 1
      and (http_options($ordinary).explicitHttpConfig.httpProtocolOptions? != null)
      and (http_options($ordinary).explicitHttpConfig.http2ProtocolOptions? == null)
      and (http_options($grpc).explicitHttpConfig.http2ProtocolOptions? != null)
      and (http_options($grpc).explicitHttpConfig.httpProtocolOptions? == null)
      and (
        [
          .spec.resources[]?
          | .. | objects
          | select(.grpcService?.envoyGrpc?.clusterName? == $grpc)
        ]
        | length
      ) >= 1
      and (
        [
          .spec.resources[]?
          | .. | objects
          | select(.route?.cluster? == $ordinary)
        ]
        | length
      ) >= 1
    ' <<<"$cec_json" >/dev/null; then
    echo "FAIL: CEC ${cec_name} does not keep ordinary and ext_proc clusters protocol-specific" >&2
    echo "Generated clusters:" >&2
    jq -c '
      [
        .spec.resources[]?
        | .. | objects
        | select(."@type"? == "type.googleapis.com/envoy.config.cluster.v3.Cluster")
        | {
            name,
            httpOptions: .typedExtensionProtocolOptions?
              ["envoy.extensions.upstreams.http.v3.HttpProtocolOptions"]?
              .explicitHttpConfig?
          }
      ]
    ' <<<"$cec_json" >&2
    echo "Generated ext_proc cluster references:" >&2
    jq -r '
      .spec.resources[]?
      | .. | objects
      | .grpcService?.envoyGrpc?.clusterName?
      | select(. != null)
    ' <<<"$cec_json" >&2
    return 1
  fi

  echo "PASS: ${cec_name} separates HTTP cluster ${ordinary_cluster} from gRPC cluster ${grpc_cluster}"
}

retry_until 30 kubectl get "cec/${cec_name}" -n "$gateway_ns" >/dev/null
retry_until 30 assert_shared_backend_clusters
