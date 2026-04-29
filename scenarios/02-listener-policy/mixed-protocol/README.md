# mixed-protocol — HTTP + HTTPS + TLS Passthrough on shared port (no explicit kinds)

Three-listener Gateway with **no explicit `allowedRoutes.kinds`** on any
listener. Tests that implicit kind defaults (derived from listener protocol)
are evaluated correctly per-listener when mixing HTTP, HTTPS Terminate, and
TLS Passthrough protocols.

All listeners use `allowedRoutes.namespaces.from: Same`, so routes live in
`gateway-system` and use cross-namespace `backendRefs` with ReferenceGrants.

| Listener | Protocol          | Port | Hostname            |
| -------- | ----------------- | ---- | ------------------- |
| `http`   | HTTP              | 80   | _(any)_             |
| `https`  | HTTPS (Terminate) | 443  | `app.example.test`  |
| `tls`    | TLS (Passthrough) | 443  | `mtls.example.test` |

## Resources

| Resource                         | Namespace      | Purpose                                        |
| -------------------------------- | -------------- | ---------------------------------------------- |
| Gateway `mixed-protocol-gateway` | gateway-system | HTTP/80 + HTTPS/443 + TLS/443                  |
| HTTPRoute `backend-a-app-route`  | gateway-system | HTTPS termination → api in backend-a           |
| HTTPRoute `http-redirect`        | gateway-system | HTTP → HTTPS redirect (301)                    |
| TLSRoute `backend-b-mtls-route`  | gateway-system | TLS passthrough → backend-mtls in backend-b    |
| ReferenceGrant                   | backend-a      | Allow HTTPRoute from gateway-system → Services |
| ReferenceGrant                   | backend-b      | Allow TLSRoute from gateway-system → Services  |
| Pod `api`                        | backend-a      | go-httpbin (HTTP backend)                      |
| Pod `backend-mtls`               | backend-b      | Envoy with per-namespace mTLS certs            |

## Verification

What `verify.sh` checks:

1. All three routes (HTTPRoute `backend-a-app-route`, HTTPRoute `http-redirect`, TLSRoute `backend-b-mtls-route`) reach `Accepted=True`
2. Per-listener `attachedRoutes` counts are correct (1 each for `http`, `https`, `tls`)
3. HTTPS termination — `curl` to `app.example.test:443` succeeds
4. HTTP → HTTPS redirect — `curl` to `app.example.test:80` returns 301
5. TLS passthrough — mTLS `curl` to `mtls.example.test:443` succeeds
6. Status message assertions for HTTPRoute and TLSRoute accepted messages

## Run

```sh
mise run //scenarios/02-listener-policy/mixed-protocol:start
```
