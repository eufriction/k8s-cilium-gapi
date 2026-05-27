# https-ext-auth-http - HTTPS HTTPRoute with HTTP ExternalAuth

This scenario verifies Gateway API `ExternalAuth` on a TLS-terminated HTTPS
`HTTPRoute` using an HTTP-speaking Envoy ext_authz backend. The route includes
an unauthenticated public rule, two rules sharing the same auth configuration,
and one variant rule that uses the same auth service with a different auth path
and allowed request header. Each rule rewrites its scenario path prefix to `/`
before forwarding to go-httpbin.

## Resources

| Resource                                                     | Namespace      | Purpose                                      |
| ------------------------------------------------------------ | -------------- | -------------------------------------------- |
| Gateway `ext-auth-http-gateway`                              | gateway-system | HTTPS listener on port 443                   |
| Certificate `https-ext-auth-http-gateway-certificate`        | gateway-system | Self-signed TLS cert for the gateway         |
| HTTPRoute `ext-auth-http-route`                              | backend-a      | Routes public and HTTP-authenticated traffic |
| ReferenceGrant `allow-backend-a-httproute-to-external-authz` | auth           | Allows cross-namespace auth service refs     |
| Deployment `external-authz`                                  | auth           | HTTP/gRPC Envoy ext_authz test service       |
| Pod `api`                                                    | backend-a      | go-httpbin backend                           |

## Verification

What `verify.sh` checks:

1. Backend pod, auth deployment, and TLS certificate are ready.
2. Gateway is Accepted.
3. HTTPRoute is Accepted.
4. Listener `https` reports 1 attached route.
5. `/public` succeeds without an ExternalAuth result header.
6. `/http-auth` without `X-Authz-Token: allow` is denied with HTTP 403.
7. `/http-auth` with `X-Authz-Token: allow` succeeds and forwards `X-Ext-Authz-Result: allowed-http` to the backend.
8. `/http-auth-shared` succeeds with the same auth config.
9. `/http-auth-variant` is denied without `X-Debug-Token: demo` and succeeds with it.

## Prerequisites

This scenario requires Cilium and Gateway API CRDs with experimental
`HTTPRoute` `ExternalAuth` support. Released profiles that do not include this
support are skipped via `SCENARIO_SKIP_VERSIONS`.

## Run

```sh
mise run //scenarios/06-extensions/https-ext-auth-http:start
```
