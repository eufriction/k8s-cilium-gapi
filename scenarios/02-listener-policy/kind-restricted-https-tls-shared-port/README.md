# kind-restricted-https-tls-shared-port — Kind restriction on mixed HTTPS + TLS passthrough

Tests per-listener `allowedRoutes.kinds` when an HTTPS termination listener and a TLS
passthrough listener share port 443 with different hostnames. Each listener explicitly
restricts which route kind it accepts. The HTTPRoute targets the `https` listener via
`sectionName`, and the TLSRoute targets the `tls` listener via `sectionName`. Both
routes should be accepted independently based on their targeted listener's kind policy.

| Listener | Port | Hostname              | Protocol | `allowedRoutes.kinds` |
| -------- | ---- | --------------------- | -------- | --------------------- |
| `https`  | 443  | `web.example.test`    | HTTPS    | `[HTTPRoute]`         |
| `tls`    | 443  | `mtls-b.example.test` | TLS      | `[TLSRoute]`          |

## Resources

| Resource                         | Namespace      | Purpose                                 |
| -------------------------------- | -------------- | --------------------------------------- |
| Gateway `kind-https-tls-gateway` | gateway-system | HTTPS/443 + TLS/443, per-listener kinds |
| HTTPRoute `backend-a-web-route`  | backend-a      | HTTPS termination → go-httpbin          |
| TLSRoute `backend-b-mtls-route`  | backend-b      | TLS passthrough → backend-mtls (mTLS)   |
| Pod `api`                        | backend-a      | go-httpbin (HTTP backend)               |
| Pod `backend-mtls`               | backend-b      | Envoy with per-namespace mTLS certs     |

## Verification

What `verify.sh` checks:

1. HTTPRoute `backend-a-web-route` is accepted by the `https` listener
2. TLSRoute `backend-b-mtls-route` is accepted by the `tls` listener
3. Per-listener `attachedRoutes` and `supportedKinds` are correct (`https` → 1 HTTPRoute, `tls` → 1 TLSRoute)
4. HTTPS termination — `curl` to `web.example.test:443` succeeds
5. TLS passthrough — mTLS `curl` to `mtls-b.example.test:443` succeeds

## Related scenarios

- [`https-tls-shared-port`](../../01-simple/https-tls-shared-port/README.md) — same topology without explicit `allowedRoutes.kinds` (protocol implicitly determines allowed route type)

## Run

```sh
mise run //scenarios/02-listener-policy/kind-restricted-https-tls-shared-port:start
```
