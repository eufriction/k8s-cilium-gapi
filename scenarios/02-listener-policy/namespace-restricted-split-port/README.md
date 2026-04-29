# namespace-restricted-split-port — Namespace restriction on split HTTP ports

Tests that `allowedRoutes.namespaces` is evaluated **independently per listener**
when two HTTP listeners are on different ports (80, 8080) with different hostnames.
An HTTPRoute in `backend-a` targets the gateway **without `sectionName`**. Per the
Gateway API spec, the restricted listener (`Same`) should reject the cross-namespace
route while the open listener (`All`) should accept it.

## Resources

| Resource                        | Namespace      | Purpose                                 |
| ------------------------------- | -------------- | --------------------------------------- |
| Gateway `ns-split-port-gateway` | gateway-system | Two HTTP listeners on ports 80 and 8080 |
| HTTPRoute                       | backend-a      | Targets gateway without `sectionName`   |
| Pod `api`                       | backend-a      | go-httpbin (HTTP backend)               |

| Listener          | Port | Hostname                  | `namespaces.from` | Expected `attachedRoutes` |
| ----------------- | ---- | ------------------------- | ----------------- | ------------------------- |
| `http-restricted` | 80   | `restricted.example.test` | `Same`            | 0                         |
| `http-open`       | 8080 | `open.example.test`       | `All`             | 1                         |

## Verification

What `verify.sh` checks:

1. `attachedRoutes` status — restricted listener (port 80) has 0 attached routes; open listener (port 8080) has 1
2. HTTP traffic to `open.example.test:8080` succeeds (open listener accepts cross-namespace route)
3. Restricted listener on port 80 returns 404 for `restricted.example.test` (no routes attached)

## Related scenarios

- [`namespaces`](../namespaces/README.md) — same concept on split ports without explicit hostnames
- [`namespace-restricted-shared-port`](../namespace-restricted-shared-port/README.md) — same concept on shared HTTPS port 443

## Run

```sh
mise run //scenarios/02-listener-policy/namespace-restricted-split-port:start
```
