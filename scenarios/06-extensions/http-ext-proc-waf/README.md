# http-ext-proc-waf — Coraza WAF via ext_proc ExtensionRef

All HTTP traffic passes through a Coraza WAF ext_proc service before
reaching the backend. The WAF inspects request headers and query parameters,
blocking common attack patterns (SQL injection, XSS, path traversal) while
allowing legitimate requests through. This demonstrates the
`CiliumEnvoyExtProcFilter` CRD with `ExtensionRef` applied globally to all
route rules.

## Resources

| Resource                              | Namespace      | Purpose                                        |
| ------------------------------------- | -------------- | ---------------------------------------------- |
| Gateway `waf-gateway`                 | gateway-system | HTTP listener on port 80                       |
| CiliumEnvoyExtProcFilter `coraza-waf` | gateway-system | ext_proc filter config pointing to WAF service |
| HTTPRoute `waf-route`                 | backend-a      | Routes all traffic through WAF to backend      |
| Deployment `coraza-waf-extproc`       | gateway-system | Coraza WAF ext_proc gRPC service               |
| Pod `api`                             | backend-a      | go-httpbin backend                             |

## Verification

What `verify.sh` checks:

1. Backend pod and WAF deployment are Ready.
2. Gateway is Accepted.
3. HTTPRoute is Accepted.
4. Listener `http` reports 1 attached route.
5. Clean request to `/headers` passes through WAF (`x-waf-result` header injected).
6. SQL injection attempt (`?q=union select 1 from users`) returns HTTP 403.
7. XSS attempt (`?q=<script>alert(1)</script>`) returns HTTP 403.
8. Path traversal attempt (`/../../etc/passwd`) returns HTTP 403.
9. Legitimate request with query params passes WAF.

## Prerequisites

This scenario requires Cilium built from the `feat/httproute-extension-ref`
branch (or a release that includes `CiliumEnvoyExtProcFilter` support).
The Helm value `gatewayAPI.enableExtensionRefFilters=true` must be set.

## Run

```k8s-cilium-gapi/scenarios/06-extensions/http-ext-proc-waf/README.md#L43-43
mise run //scenarios/06-extensions/http-ext-proc-waf:start
```
