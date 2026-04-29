# mixed-protocol — HTTP + HTTPS + TLS Passthrough on shared port (no explicit kinds)

Three-listener Gateway with **no explicit `allowedRoutes.kinds`** on any
listener:

| Listener | Protocol          | Port | Hostname            |
| -------- | ----------------- | ---- | ------------------- |
| `http`   | HTTP              | 80   | _(any)_             |
| `https`  | HTTPS (Terminate) | 443  | `app.example.test`  |
| `tls`    | TLS (Passthrough) | 443  | `mtls.example.test` |

All listeners use `allowedRoutes.namespaces.from: Same`, so routes live in
`gateway-system` and use cross-namespace `backendRefs` with ReferenceGrants.

This scenario tests the bug from
[cilium#45559](https://github.com/cilium/cilium/issues/45559) where adding a
TLS Passthrough listener causes HTTPRoutes to be rejected with
`NotAllowedByListeners` because `CheckGatewayRouteKindAllowed` globally
overwrites the Accepted condition.

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

## Upstream bugs

- [cilium#45559](https://github.com/cilium/cilium/issues/45559) — TLS Passthrough listener causes HTTPRoutes to be rejected with `NotAllowedByListeners`

## Run

```sh
mise run //scenarios/02-listener-policy/mixed-protocol:start
```
