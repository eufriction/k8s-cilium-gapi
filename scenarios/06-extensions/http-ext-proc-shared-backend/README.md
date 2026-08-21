# `http-ext-proc-shared-backend`: shared backend cluster identity

This scenario verifies that a Service used both as a normal `HTTPRoute` backend
and as a `CiliumEnvoyExtProcFilter.backendRef` receives separate Envoy clusters.

The ordinary route needs the normal upstream protocol, while the ext_proc
backend is a gRPC service and needs HTTP/2. Both references intentionally use
the same Service and port:

```text
ext-proc-shared-backend:shared:8080
```

The scenario has no live backend pods. It validates the generated
`CiliumEnvoyConfig` so that the test does not require one endpoint to implement
both ordinary HTTP and the ext_proc gRPC protocol.

## Resources

| Resource                                           | Namespace                 | Purpose                                        |
| -------------------------------------------------- | ------------------------- | ---------------------------------------------- |
| `Service/shared`                                   | `ext-proc-shared-backend` | Shared ordinary/ext_proc backend identity      |
| `CiliumEnvoyExtProcFilter/shared-backend-ext-proc` | `ext-proc-shared-backend` | Ext_proc reference to `shared:8080`            |
| `Gateway/shared-backend-gateway`                   | `gateway-system`          | HTTP listener receiving the route              |
| `HTTPRoute/shared-backend-route`                   | `ext-proc-shared-backend` | Uses the Service as route and ext_proc backend |

## Verification

`verify.sh` checks that the generated CEC contains:

1. Exactly one ordinary cluster named `ext-proc-shared-backend:shared:8080`.
2. The ordinary cluster uses `httpProtocolOptions` and not HTTP/2 options.
3. Exactly one ext_proc cluster named `grpc:ext-proc-shared-backend:shared:8080`.
4. The ext_proc cluster uses `http2ProtocolOptions` and not HTTP/1.1 options.
5. The serialized ext_proc `envoyGrpc.clusterName` points to the `grpc:` cluster.
6. The generated HTTP route points to the ordinary cluster.

## Prerequisites

This scenario requires Cilium with `CiliumEnvoyExtProcFilter` support and
`gatewayAPI.enableExtensionRefFilters=true`. It is skipped on released
versions without the required ext_proc support; branch builds run it.

## Run

```sh
mise run //scenarios/06-extensions/http-ext-proc-shared-backend:start
```
