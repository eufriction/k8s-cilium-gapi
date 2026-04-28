# Scenario 26 — TLSRoute without sectionName on mixed-listener Gateway

Three-listener Gateway (HTTP/80, HTTPS-Terminate/443, TLS-Passthrough/443).
The TLSRoute **omits `sectionName`** and should auto-attach only to the TLS
listener per the Gateway API spec.

On Cilium 1.19.2, the TLSRoute incorrectly attaches to all three listeners,
creating duplicate Envoy FilterChains that silently break passthrough traffic.

## Resources

| Resource                         | Namespace      | Purpose                                         |
| -------------------------------- | -------------- | ----------------------------------------------- |
| Gateway `mixed-listener-gateway` | gateway-system | HTTP/80 + HTTPS/443 + TLS/443                   |
| HTTPRoute `backend-a-web-route`  | backend-a      | HTTP + HTTPS termination → go-httpbin           |
| TLSRoute `backend-b-mtls-route`  | backend-b      | TLS passthrough → backend-mtls (no sectionName) |
| Pod `api`                        | backend-a      | go-httpbin (HTTP backend)                       |
| Pod `backend-mtls`               | backend-b      | Envoy with per-namespace mTLS certs             |

## Upstream bugs

- [cilium#45050](https://github.com/cilium/cilium/issues/45050) — TLSRoutes break on 1.19.2 (duplicate FilterChains)
- [cilium#45371](https://github.com/cilium/cilium/pull/45371) — Fix PR

## Run

```sh
mise run //scenarios/02-listener-policy/no-sectionname:start
```
