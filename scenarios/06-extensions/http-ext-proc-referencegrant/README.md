# `http-ext-proc-referencegrant` - `ext_proc` cross-namespace ref blocked without a valid ReferenceGrant

This scenario verifies that a `CiliumEnvoyExtProcFilter.spec.backendRef` that
crosses namespaces is **rejected** when the deployed `ReferenceGrant` does not
cover the actual target Service.

A `ReferenceGrant` is intentionally deployed with the correct `from` group/kind
but the wrong target Service name (`ext-proc-other` instead of
`coraza-waf-extproc`). This proves that the grant-matching logic is enforced
with specificity - a nearby but non-covering grant must not unblock the
reference.

## Resources

| Resource                                                          | Namespace        | Purpose                                                          |
| ----------------------------------------------------------------- | ---------------- | ---------------------------------------------------------------- |
| Gateway `rg-gateway`                                              | `gateway-system` | HTTP listener on port 80                                         |
| `CiliumEnvoyExtProcFilter/coraza-waf`                             | `backend-a`      | Filter pointing to `coraza-waf-extproc` in `gateway-system`      |
| `ReferenceGrant/allow-backend-a-ext-proc-filter-to-other-service` | `gateway-system` | Wrong grant - permits `ext-proc-other`, not `coraza-waf-extproc` |
| `HTTPRoute/rg-route`                                              | `backend-a`      | Route using the ext_proc filter via `ExtensionRef`               |
| `Deployment/coraza-waf-extproc`                                   | `gateway-system` | Coraza WAF ext_proc gRPC service (physically present)            |
| `Pod/api`                                                         | `backend-a`      | go-httpbin backend                                               |

## Verification

What `verify.sh` checks:

1. Backend pod and WAF deployment are Ready.
2. Gateway is Accepted.
3. HTTPRoute is Accepted (`Accepted=True`—listener accepts the route).
4. HTTPRoute has `ResolvedRefs=False` with `reason=RefNotPermitted`.
5. Listener `http` reports 1 attached route.
6. Data plane fails closed (HTTP 500) due to default failure mode.

## Prerequisites

This scenario requires Cilium with `CiliumEnvoyExtProcFilter` support
(`gatewayAPI.enableExtensionRefFilters=true`). Released profiles that do not
include this support are skipped via `SCENARIO_SKIP_VERSIONS`.

## Run

```sh
mise run //scenarios/06-extensions/http-ext-proc-referencegrant:start
```
