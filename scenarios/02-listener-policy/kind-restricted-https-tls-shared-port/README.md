# kind-restricted-https-tls-shared-port — Kind restriction on mixed HTTPS + TLS passthrough

Tests per-listener `allowedRoutes.kinds` when an HTTPS termination listener and a TLS
passthrough listener share port 443 with different hostnames.

**Bug:** [cilium#45559](https://github.com/cilium/cilium/issues/45559) —
`CheckGatewayRouteKindAllowed` overwrites Accepted condition across listeners.

| Listener | Port | Hostname              | Protocol | `allowedRoutes.kinds` |
| -------- | ---- | --------------------- | -------- | --------------------- |
| `https`  | 443  | `web.example.test`    | HTTPS    | `[HTTPRoute]`         |
| `tls`    | 443  | `mtls-b.example.test` | TLS      | `[TLSRoute]`          |

The HTTPRoute targets the `https` listener via `sectionName`, the TLSRoute targets
the `tls` listener via `sectionName`. With the bug, the TLS listener's kind check
(`TLSRoute` only) overwrites the Accepted condition for the HTTPRoute.

## Difference from `https-tls-shared-port`

The [`https-tls-shared-port`](../../01-simple/https-tls-shared-port/README.md)
scenario has the same topology but without explicit `allowedRoutes.kinds` — the
protocol implicitly determines the allowed route type and it passes. This scenario
adds explicit kind restrictions per listener, which triggers the #45559 bug.

## Run

```sh
mise run //scenarios/02-listener-policy/kind-restricted-https-tls-shared-port:start
```
