# `http-ext-proc-ext-auth` - `ext_proc` WAF and ExternalAuth coexistence on the same route

This scenario verifies that a `CiliumEnvoyExtProcFilter` (`ExtensionRef`) and
an `ExternalAuth` filter can coexist on the same `HTTPRoute` rule. It exercises
the `TypedPerFilterConfig` merge path in Cilium's translation layer: both
filters must produce independent per-route config entries without clobbering
each other.

A public path serves as a baseline with no filters. A protected path carries
both a Coraza WAF `ext_proc` filter and an HTTP `ExternalAuth` filter on the
same rule, and the verify script confirms both are independently active.

## Resources

| Resource                                                       | Namespace        | Purpose                                           |
| -------------------------------------------------------------- | ---------------- | ------------------------------------------------- |
| Gateway `ext-proc-ext-auth-gateway`                            | `gateway-system` | HTTP listener on port 80                          |
| `CiliumEnvoyExtProcFilter/coraza-waf`                          | `backend-a`      | Coraza WAF ext_proc filter                        |
| `ReferenceGrant/allow-backend-a-ext-proc-filter-to-coraza-waf` | `gateway-system` | Allows the ext_proc filter to cross namespaces    |
| `ReferenceGrant/allow-backend-a-httproute-to-external-authz`   | `auth`           | Allows the HTTPRoute ExternalAuth ref to cross ns |
| `HTTPRoute/ext-proc-ext-auth-route`                            | `backend-a`      | `/public` (no filters) and `/protected` (both)    |
| `Deployment/coraza-waf-extproc`                                | `gateway-system` | Coraza WAF gRPC ext_proc service                  |
| `Deployment/external-authz`                                    | `auth`           | HTTP/gRPC ext_authz service                       |
| `Pod/api`                                                      | `backend-a`      | go-httpbin backend                                |

## Verification

What `verify.sh` checks:

1. Backend pod, WAF deployment, and auth deployment are Ready.
2. Gateway is Accepted.
3. HTTPRoute is Accepted with `ResolvedRefs=True`.
4. Listener `http` reports 1 attached route.
5. `/public` returns 200 with neither `x-waf-result` nor `x-ext-authz-result` (no filters on this path).
6. `/protected` with `X-Authz-Token: allow` returns 200 with **both** `x-waf-result` (WAF processed) and `x-ext-authz-result` (auth allowed) - confirms coexistence.
7. `/protected` without token returns 403 (ExternalAuth denies).
8. `/protected` with SQL injection and valid token returns 403 (WAF blocks).

## Prerequisites

Requires a Cilium build with `CiliumEnvoyExtProcFilter` CRD and
`gatewayAPI.enableExtensionRefFilters=true`, plus `ExternalAuth` support on
`HTTPRoute`. Released profiles that do not include this support are skipped via
`SCENARIO_SKIP_VERSIONS`.

## Run

```sh
mise run //scenarios/06-extensions/http-ext-proc-ext-auth:start
```
