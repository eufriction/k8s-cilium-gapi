# namespace-restricted-shared-port — Namespace restriction on shared HTTPS port

Tests that `allowedRoutes.namespaces` is evaluated **independently per listener**
when two HTTPS listeners share port 443 with different hostnames. A route from
a cross-namespace should only attach to the listener that allows it (`from: All`),
not to the one restricted to `Same`.

## Resources

| Resource                         | Namespace      | Purpose                                                           |
| -------------------------------- | -------------- | ----------------------------------------------------------------- |
| Gateway `ns-shared-port-gateway` | gateway-system | Two HTTPS listeners on port 443 with different namespace policies |
| HTTPRoute                        | backend-a      | Targets gateway without `sectionName`                             |
| Certificate (self-signed)        | gateway-system | TLS cert for both listeners                                       |
| Pod `api`                        | backend-a      | go-httpbin (HTTP backend)                                         |

## Listeners

| Listener           | Port | Hostname                  | `namespaces.from` | Expected `attachedRoutes`                         |
| ------------------ | ---- | ------------------------- | ----------------- | ------------------------------------------------- |
| `https-restricted` | 443  | `restricted.example.test` | `Same`            | 0 (route is in `backend-a`, not `gateway-system`) |
| `https-open`       | 443  | `open.example.test`       | `All`             | 1                                                 |

The HTTPRoute in `backend-a` targets the gateway **without `sectionName`**. Per the
Gateway API spec, each listener should independently evaluate its namespace policy.

## Verification

What `verify.sh` checks:

1. **Listener status** — restricted listener (`https-restricted`) has 0 attached routes; open listener (`https-open`) has 1
2. **HTTPS traffic on open listener** — `curl` to `open.example.test:443` succeeds

## Related scenarios

- [`namespaces`](../namespaces/README.md) — same concept with HTTP on split ports (80/8080), no hostnames
- [`namespace-restricted-split-port`](../namespace-restricted-split-port/README.md) — split ports with explicit hostnames

## Run

```sh
mise run //scenarios/02-listener-policy/namespace-restricted-shared-port:start
```
