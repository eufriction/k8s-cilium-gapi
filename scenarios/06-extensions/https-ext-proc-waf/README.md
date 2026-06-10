# HTTPS `ext_proc` WAF with `ExtensionRef`

HTTPS traffic is terminated at the Gateway and then passed through a Coraza WAF
`ext_proc` service before reaching the backend. The WAF inspects the decrypted
request headers and query parameters, blocking common attack patterns (SQL
injection, XSS, path traversal) while allowing legitimate requests through.

This scenario demonstrates a Gateway API `ExtensionRef` filter that references a
`CiliumEnvoyExtProcFilter` in the route namespace. The filter then references
the WAF Service in `gateway-system`, which is allowed by a `ReferenceGrant`.

## Resources

| Resource                                                             | Namespace        | Purpose                                           |
| -------------------------------------------------------------------- | ---------------- | ------------------------------------------------- |
| `Issuer/https-ext-proc-waf-selfsigned`                               | `gateway-system` | Self-signed issuer for the Gateway certificate    |
| `Certificate/https-ext-proc-waf-gateway-certificate`                 | `gateway-system` | TLS certificate for `app.example.test`            |
| `Gateway/https-waf-gateway`                                          | `gateway-system` | HTTPS listener on port 443                        |
| `CiliumEnvoyExtProcFilter/https-coraza-waf`                          | `backend-a`      | Filter config pointing to the WAF Service         |
| `ReferenceGrant/allow-backend-a-https-ext-proc-filter-to-coraza-waf` | `gateway-system` | Allows the filter to reference the WAF Service    |
| `HTTPRoute/https-waf-route`                                          | `backend-a`      | Routes all traffic through the WAF to the backend |
| `Deployment/coraza-waf-extproc`                                      | `gateway-system` | Coraza WAF `ext_proc` gRPC service                |
| `Pod/api`                                                            | `backend-a`      | `go-httpbin` backend                              |

## Verification

What `verify.sh` checks:

1. Backend pod, WAF deployment, and Gateway certificate are Ready.
2. Gateway is Accepted.
3. HTTPRoute is Accepted and has `ResolvedRefs=True`.
4. Listener `https` reports 1 attached route.
5. Clean HTTPS request to `/headers` passes through the WAF (`x-waf-result`
   header injected).
6. SQL injection attempt (`?q=union select 1 from users`) returns HTTP 403.
7. XSS attempt (`?q=<script>alert(1)</script>`) returns HTTP 403.
8. Path traversal attempt (`/../../etc/passwd`) returns HTTP 403.
9. Legitimate HTTPS request with query parameters passes the WAF.
10. Cilium Envoy exposes per-filter `ext_proc` metrics for the generated
    `ceepf.backend_a.https_coraza_waf` stat prefix, and the counter increases
    after WAF traffic.

## Prerequisites

This scenario requires Cilium built from the `feat/httproute-extension-ref`
branch, or a release that includes `CiliumEnvoyExtProcFilter` support. The Helm
value `gatewayAPI.enableExtensionRefFilters=true` must be set.

This scenario also requires cert-manager; the scenario `start` task installs it
via `//:cert-manager:install`.

## Run

```sh
mise run //scenarios/06-extensions/https-ext-proc-waf:start
```
