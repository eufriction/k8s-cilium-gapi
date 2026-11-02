#!/usr/bin/env bash
# Refuse to run the suite over Gateways or load balancers from an earlier run.
set -euo pipefail

for config in scenarios/*/*/mise.toml; do
  [ -f "$config" ] || continue
  if [ ! -f "${config%/mise.toml}/gateway/kustomization.yaml" ]; then
    echo "INFRA: ${config%/mise.toml} needs a gateway/kustomization.yaml for shared-fixture runs" >&2
    exit 2
  fi
done

if ! gateways=$(kubectl get gateways.gateway.networking.k8s.io -A -o json); then
  echo "INFRA: cannot check existing Gateways; suite not started" >&2
  exit 2
fi
if ! services=$(kubectl get services -A -o json); then
  echo "INFRA: cannot check existing Gateway Services; suite not started" >&2
  exit 2
fi
if ! proxies=$(docker ps -a \
  --filter "label=io.x-k8s.cloud-provider-kind.cluster=${KIND_CLUSTER_NAME:-k8s-cilium-gapi}" \
  --filter 'label=io.x-k8s.cloud-provider-kind.loadbalancer.name' \
  --format '{{.Names}}\t{{.Status}}\t{{.Ports}}'); then
  echo "INFRA: cannot check cloud-provider-kind load balancers; suite not started" >&2
  exit 2
fi

gateways=$(printf '%s\n' "$gateways" | jq -r '
  .items[] | select(.spec.gatewayClassName == "cilium")
  | "Gateway/\(.metadata.namespace)/\(.metadata.name)"
')
services=$(printf '%s\n' "$services" | jq -r '
  .items[]
  | select(.metadata.labels["io.cilium.gateway/owning-gateway"] != null)
  | "Service/\(.metadata.namespace)/\(.metadata.name)"
    + (if .metadata.deletionTimestamp then " (terminating)" else "" end)
')

if [ -n "$gateways$services$proxies" ]; then
  echo "INFRA: existing Gateway resources may hold ports needed by the suite:" >&2
  for resources in "$gateways" "$services" "$proxies"; do
    if [ -n "$resources" ]; then
      printf '%s\n' "$resources" >&2
    fi
  done
  echo "Clean up the listed scenarios and wait for their LoadBalancer Services and containers to disappear, then rerun." >&2
  echo "No resources were changed. Shared fixture setup has not started." >&2
  exit 2
fi

echo "PASS: no existing Cilium Gateways, Gateway Services, or cloud-provider-kind load balancers"
