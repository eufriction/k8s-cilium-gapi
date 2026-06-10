# HTTP `ext_proc` WAF with `ExtensionRef`

All HTTP traffic passes through a Coraza WAF `ext_proc` service before reaching
the backend. The WAF inspects request headers and query parameters, blocking
common attack patterns (SQL injection, XSS, path traversal) while allowing
legitimate requests through.

This scenario demonstrates a Gateway API `ExtensionRef` filter that references a
`CiliumEnvoyExtProcFilter` in the route namespace. The filter then references
the WAF Service in `gateway-system`, which is allowed by a `ReferenceGrant`.

## Resources

| Resource                                                       | Namespace        | Purpose                                           |
| -------------------------------------------------------------- | ---------------- | ------------------------------------------------- |
| `Gateway/waf-gateway`                                          | `gateway-system` | HTTP listener on port 80                          |
| `CiliumEnvoyExtProcFilter/coraza-waf`                          | `backend-a`      | Filter config pointing to the WAF Service         |
| `ReferenceGrant/allow-backend-a-ext-proc-filter-to-coraza-waf` | `gateway-system` | Allows the filter to reference the WAF Service    |
| `HTTPRoute/waf-route`                                          | `backend-a`      | Routes all traffic through the WAF to the backend |
| `Deployment/coraza-waf-extproc`                                | `gateway-system` | Coraza WAF `ext_proc` gRPC service                |
| `Pod/api`                                                      | `backend-a`      | `go-httpbin` backend                              |

## Verification

What `verify.sh` checks:

1. Backend pod and WAF deployment are Ready.
2. Gateway is Accepted.
3. HTTPRoute is Accepted and has `ResolvedRefs=True`.
4. Listener `http` reports 1 attached route.
5. Clean request to `/headers` passes through the WAF (`x-waf-result` header injected).
6. SQL injection attempt (`?q=union select 1 from users`) returns HTTP 403.
7. XSS attempt (`?q=<script>alert(1)</script>`) returns HTTP 403.
8. Path traversal attempt (`/../../etc/passwd`) returns HTTP 403.
9. Legitimate request with query parameters passes the WAF.
10. Cilium Envoy exposes per-filter `ext_proc` metrics for the generated
    `ceepf.backend_a.coraza_waf` stat prefix, and the counter increases after
    WAF traffic.

## Prerequisites

This scenario requires Cilium built from the `feat/httproute-extension-ref`
branch, or a release that includes `CiliumEnvoyExtProcFilter` support. The Helm
value `gatewayAPI.enableExtensionRefFilters=true` must be set.

## Run

```sh
mise run //scenarios/06-extensions/http-ext-proc-waf:start
```
