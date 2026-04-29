# namespaces — allowedRoutes.namespaces per-listener enforcement

Tests that `allowedRoutes.namespaces` is evaluated **independently per listener**
when an HTTPRoute omits `sectionName`. The Gateway has two HTTP listeners on
separate ports with different namespace policies:

| Listener          | Port | `namespaces.from` | Expected `attachedRoutes`                         |
| ----------------- | ---- | ----------------- | ------------------------------------------------- |
| `http-restricted` | 80   | `Same`            | 0 (route is in `backend-a`, not `gateway-system`) |
| `http-open`       | 8080 | `All`             | 1                                                 |

The HTTPRoute in `backend-a` references the Gateway without `sectionName`. Per the
Gateway API spec, each listener should independently evaluate its namespace policy.
The restricted listener should reject the cross-namespace route while the open
listener accepts it.

## Resources

| Resource                            | Namespace      | Purpose                                    |
| ----------------------------------- | -------------- | ------------------------------------------ |
| Gateway `allowed-routes-ns-gateway` | gateway-system | Two HTTP listeners with different NS rules |
| HTTPRoute                           | backend-a      | Targets gateway without sectionName        |
| Pod `api`                           | backend-a      | go-httpbin (HTTP backend)                  |

## Verification

What `verify.sh` checks:

1. Listener status — `http-restricted` has 0 attached routes; `http-open` has 1
2. HTTP traffic to `web.example.test` on port 8080 succeeds (open listener)
3. Negative test — `restricted.example.test` on port 80 returns 404 (no routes attached)

## Related scenarios

- [namespace-restricted-split-port](../namespace-restricted-split-port/README.md) — split ports with explicit hostnames on each listener
- [namespace-restricted-shared-port](../namespace-restricted-shared-port/README.md) — shared HTTPS port with different hostnames

## Run

```sh
mise run //scenarios/02-listener-policy/namespaces:start
```
