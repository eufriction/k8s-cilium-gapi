# gRPC `ext_proc` with `ExtensionRef`

A `GRPCRoute` sends gRPC traffic through a Coraza WAF `ext_proc` service before
reaching the gRPC backend. This scenario verifies that Cilium's
`CiliumEnvoyExtProcFilter` `ExtensionRef` support is applied to GRPCRoute
traffic, not only HTTPRoute traffic.

The Coraza processor is configured with the same lightweight rules used by the
HTTP WAF scenarios. For gRPC traffic this scenario verifies successful routing
and proves the Envoy `ext_proc` filter is invoked by checking that the
per-filter Envoy metric increases after gRPC requests.

## Resources

| Resource                                                            | Namespace        | Purpose                                          |
| ------------------------------------------------------------------- | ---------------- | ------------------------------------------------ |
| `Issuer/grpc-ext-proc-selfsigned`                                   | `gateway-system` | Self-signed issuer for the Gateway certificate   |
| `Certificate/grpc-ext-proc-gateway-certificate`                     | `gateway-system` | TLS certificate for `grpc-ext-proc.example.test` |
| `Gateway/grpc-ext-proc-gateway`                                     | `gateway-system` | HTTPS listener for gRPC traffic on port 443      |
| `CiliumEnvoyExtProcFilter/grpc-coraza-waf`                          | `grpc-backend-a` | Filter config pointing to the WAF Service        |
| `ReferenceGrant/allow-grpc-backend-a-ext-proc-filter-to-coraza-waf` | `gateway-system` | Allows the filter to reference the WAF Service   |
| `GRPCRoute/grpc-ext-proc-route`                                     | `grpc-backend-a` | Routes gRPC traffic through the ext_proc filter  |
| `Deployment/coraza-waf-extproc`                                     | `gateway-system` | Coraza WAF `ext_proc` gRPC service               |
| `Pod/grpc-api`                                                      | `grpc-backend-a` | gRPC test backend                                |

## Verification

What `verify.sh` checks:

1. gRPC backend pod, WAF deployment, and Gateway certificate are Ready.
2. Gateway is Accepted.
3. GRPCRoute is Accepted and has `ResolvedRefs=True`.
4. Listener `grpcs` reports 1 attached route.
5. gRPC requests to `grpc.testing.TestService/UnaryCall` route to
   `grpc-backend-a`.
6. Cilium Envoy exposes per-filter `ext_proc` metrics for the generated
   `ceepf.grpc_backend_a.grpc_coraza_waf` stat prefix, and the counter
   increases after gRPC traffic.

## Prerequisites

This scenario requires Cilium built from the `feat/httproute-extension-ref`
branch, or a release that includes `CiliumEnvoyExtProcFilter` support. The Helm
value `gatewayAPI.enableExtensionRefFilters=true` must be set.

This scenario also requires cert-manager; the scenario `start` task installs it
via `//:cert-manager:install`.

## Run

```sh
mise run //scenarios/06-extensions/grpc-ext-proc:start
```
