# `https-ext-auth-grpc` - HTTPS HTTPRoute with gRPC `ExternalAuth`

This scenario verifies Gateway API `ExternalAuth` on a TLS-terminated HTTPS
`HTTPRoute` using a gRPC-speaking Envoy ext_authz backend. The route includes
an unauthenticated public rule and two rules sharing the same gRPC auth
configuration. Each rule rewrites its scenario path prefix to `/` before
forwarding to go-httpbin.

## Resources

| Resource                                                     | Namespace      | Purpose                                      |
| ------------------------------------------------------------ | -------------- | -------------------------------------------- |
| Gateway `ext-auth-grpc-gateway`                              | gateway-system | HTTPS listener on port 443                   |
| Certificate `https-ext-auth-grpc-gateway-certificate`        | gateway-system | Self-signed TLS cert for the gateway         |
| HTTPRoute `ext-auth-grpc-route`                              | backend-a      | Routes public and gRPC-authenticated traffic |
| ReferenceGrant `allow-backend-a-httproute-to-ext-authz-grpc` | auth           | Allows cross-namespace auth service refs     |
| Deployment `external-authz`                                  | auth           | HTTP/gRPC Envoy ext_authz test service       |
| Pod `api`                                                    | backend-a      | go-httpbin backend                           |

## Verification

What `verify.sh` checks:

1. Backend pod, auth deployment, and TLS certificate are ready.
2. Gateway is Accepted.
3. HTTPRoute is Accepted.
4. Listener `https` reports 1 attached route.
5. `/public` succeeds without an ExternalAuth result header.
6. `/grpc-auth` without `X-Authz-Token: allow` is denied with HTTP 403.
7. `/grpc-auth` with `X-Authz-Token: allow` succeeds and forwards `X-Ext-Authz-Result: allowed-grpc` to the backend.
8. `/grpc-auth-shared` succeeds with the same gRPC auth config.

## Prerequisites

This scenario requires Cilium and Gateway API CRDs with experimental
`HTTPRoute` `ExternalAuth` support. Released profiles that do not include this
support are skipped via `SCENARIO_SKIP_VERSIONS`.

## Run

```sh
mise run //scenarios/06-extensions/https-ext-auth-grpc:start
```
