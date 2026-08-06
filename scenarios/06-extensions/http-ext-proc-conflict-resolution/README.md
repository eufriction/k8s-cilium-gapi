# `http-ext-proc-conflict-resolution` - deterministic `ext_proc` ordering

This scenario validates the conflict-resolution rules for Gateway API
`ExtensionRef` filters backed by `CiliumEnvoyExtProcFilter`:

- the older `HTTPRoute` takes precedence over a newer route;
- equal creation timestamps are ordered by namespace and name;
- multiple ext_proc filters on one route retain their declaration order;
- all ext_proc filters are placed before `ext_authz`; and
- an unresolved ExtensionRef fails closed with HTTP 500.

The scenario uses several hostnames on one Gateway so all resolved filters are
combined into one listener-wide Envoy HTTP filter chain. Its `start` task stages
the routes into older, equal-timestamp, and newer groups. It inspects the
`CiliumEnvoyConfig` generated for that Gateway and computes the expected order
from the live route creation timestamps, namespaces, names, and filter indexes.
The `shared-a` and `shared-b` references occur on more than one route so the
check also verifies that deduplication keeps the first occurrence selected by
that precedence order.

## Resources

| Resource                                       | Namespace               | Purpose                                      |
| ---------------------------------------------- | ----------------------- | -------------------------------------------- |
| `Gateway/ext-proc-conflict-resolution-gateway` | `gateway-system`        | HTTP listener on port 80                     |
| `HTTPRoute/00-oldest-route`                    | `backend-a`             | Older route with three ordered ext_proc refs |
| `HTTPRoute/a-tie-route`                        | `backend-a`/`backend-b` | Namespace tie-breaker routes                 |
| `HTTPRoute/b-tie-route`                        | `backend-b`             | Name tie-breaker route                       |
| `HTTPRoute/newest-route`                       | `backend-b`             | Newer route                                  |
| `HTTPRoute/auth-route`                         | `backend-a`             | ext_proc plus Gateway API ExternalAuth       |
| `HTTPRoute/invalid-route`                      | `backend-a`             | Missing ext_proc reference                   |
| `CiliumEnvoyExtProcFilter/*`                   | `backend-a`/`backend-b` | Ordered filter instances                     |
| `Deployment/coraza-waf-extproc`                | `gateway-system`        | ext_proc backend                             |
| `Deployment/external-authz`                    | `auth`                  | HTTP ext_authz backend                       |
| `Pod/api`                                      | `backend-a`/`backend-b` | HTTP backends                                |

## Verification

What `verify.sh` checks:

1. The backend, Coraza WAF, and ExternalAuth workloads are Ready.
2. The Gateway and all seven HTTPRoutes report the expected attachment state.
3. Valid routes report `ResolvedRefs=True`; the missing-reference route reports
   `ResolvedRefs=False` and `BackendNotFound`.
4. The generated CEC contains exactly the expected deduplicated ext_proc filter
   sequence, sorted by creation timestamp, namespace/name, and filter index.
5. Every ext_proc filter appears before the generated `ext_authz` filter in the
   listener HTTP filter chain.
6. The authenticated route reaches the backend with both WAF and auth headers.
7. The invalid route returns HTTP 500 instead of reaching the backend.

## Prerequisites

This scenario requires a Cilium build with `CiliumEnvoyExtProcFilter` support
and `gatewayAPI.enableExtensionRefFilters=true`. Released profiles that do not
include this support are skipped via `SCENARIO_SKIP_VERSIONS`.

## Run

```sh
mise run //scenarios/06-extensions/http-ext-proc-conflict-resolution:start
```
