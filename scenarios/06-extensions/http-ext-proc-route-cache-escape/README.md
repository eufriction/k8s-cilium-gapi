# `http-ext-proc-route-cache-escape` - `ext_proc` must not move a request to another route

Envoy's external processing filter lets a processor rewrite request headers and
ask Envoy to clear its route cache. Clearing the cache re-runs route matching
against the rewritten headers, so a processor attached to one `HTTPRoute` rule
can move a request onto a different rule and leave behind the filters the
original rule declared.

Gateway API's model assumes a rule's filters govern that rule's traffic. This
scenario probes that assumption: the protected rule declares an `ExternalAuth`
filter, the public rule declares none, and the processor tries to cross from one
to the other. `ext_proc` runs before `ext_authz` in Cilium's filter chain, so a
successful crossing skips authorization completely.

The processor is `route-mutator-extproc`, which rewrites `:path` from
`/anything/protected` to `/anything/public` and sets `clear_route_cache`. Envoy
permits `:path` mutations by default; `:authority`, `:method`, `:scheme`, and
`host` are protected, which is why the crossing has to happen within one
hostname.

## Expected outcome

Cilium must pin `route_cache_action: RETAIN` on every generated `ext_proc`
filter. The processor may still rewrite `:path`, but the route selected before
processing is the route that serves the request.

Until that is in place this scenario **fails**: `/anything/protected` returns
200 from the public rule with no authorization.

## Resources

| Resource                                                          | Namespace        | Purpose                                                  |
| ----------------------------------------------------------------- | ---------------- | -------------------------------------------------------- |
| Gateway `route-cache-escape-gateway`                              | `gateway-system` | HTTP listener on port 80                                 |
| `CiliumEnvoyExtProcFilter/route-mutator`                          | `backend-a`      | ext_proc filter pointing at the path-rewriting processor |
| `ReferenceGrant/allow-backend-a-ext-proc-filter-to-route-mutator` | `gateway-system` | Allows the ext_proc filter to cross namespaces           |
| `ReferenceGrant/allow-backend-a-httproute-to-external-authz`      | `auth`           | Allows the HTTPRoute `ExternalAuth` ref to cross         |
| `HTTPRoute/route-cache-escape-route`                              | `backend-a`      | `/anything/public` (no filters), `/anything/protected`   |
| `Deployment/route-mutator-extproc`                                | `gateway-system` | Rewrites `:path` and clears the route cache              |
| `Deployment/external-authz`                                       | `auth`           | HTTP ext_authz service                                   |
| `Pod/api`                                                         | `backend-a`      | go-httpbin backend                                       |

## Shared fixture

With `FIXTURE_DEPLOYED=true`, the runner uses `gateway/kustomization.yaml`.
It reuses the fixture's namespaces, HTTP backend, and authorization service,
and deploys only the route mutator and scenario-specific Gateway resources.
Cleanup removes that same overlay, leaving the shared fixture intact even when
verification fails. Standalone runs use the full root kustomization.

## Verification

What `verify.sh` checks:

1. Backend pod, processor, and auth service are Ready.
2. Gateway is Accepted and the HTTPRoute has `ResolvedRefs=True`.
3. `/anything/public` serves without a token and carries no `x-route-mutator`
   header, confirming the processor is scoped to the other rule.
4. `/anything/protected` without a token returns 403. The processor's rewrite
   and cache clear must not hand the request to the unauthenticated rule.
5. `/anything/protected` with a valid token returns 200 showing
   `x-route-mutator: rewrote`, `x-served-by: protected-rule`, an
   `x-ext-authz-result` header, and an upstream URL of `/anything/public/data`.
   Together these prove the mutation happened and routing still did not move.
6. The generated `CiliumEnvoyConfig` pins the `ext_proc` route cache action to
   `RETAIN`, so a regression is reported against the field rather than against a
   request.

## Not covered

Envoy's `mutation_rules.disallow_is_error` governs what happens when a processor
attempts a mutation Envoy refuses, such as rewriting `:authority`. By default
the mutation is silently dropped. That is a separate failure mode and needs its
own scenario.

## Prerequisites

Requires a Cilium build with the `CiliumEnvoyExtProcFilter` CRD and
`gatewayAPI.enableExtensionRefFilters=true`, plus `ExternalAuth` support on
`HTTPRoute`.

## Run

```sh
mise run //scenarios/06-extensions/http-ext-proc-route-cache-escape:start
```
