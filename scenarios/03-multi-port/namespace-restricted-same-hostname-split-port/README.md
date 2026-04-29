# namespace-restricted-same-hostname-split-port — per-listener namespace restriction on same hostname

This scenario tests that `allowedRoutes.namespaces` is evaluated **independently
per listener** when two HTTPS listeners share the **same hostname**
(`api.example.test`) but use **different ports** (443, 50051).

A cross-namespace HTTPRoute targets the Gateway without `sectionName`. Both
listeners match the hostname, but the restricted listener (`Same` namespace)
should reject the cross-namespace route while the open listener (`All`
namespaces) accepts it. Traffic on the restricted listener's port must return
404, proving that the route did not leak across listeners.

## Resources

| Resource                                                 | Namespace        | Purpose                                                           |
| -------------------------------------------------------- | ---------------- | ----------------------------------------------------------------- |
| `Gateway/ns-restricted-same-hostname-split-port-gateway` | `gateway-system` | Two HTTPS listeners with different namespace policies             |
| `HTTPRoute/backend-a-cross-ns-route`                     | `backend-a`      | Cross-namespace route (no `sectionName`) targeting both listeners |
| `Pod/api`                                                | `backend-a`      | HTTP backend                                                      |

## Gateway listeners

| Listener           | Protocol | Port    | Hostname           | `namespaces.from` |
| ------------------ | -------- | ------- | ------------------ | ----------------- |
| `https-restricted` | HTTPS    | `443`   | `api.example.test` | `Same`            |
| `https-open`       | HTTPS    | `50051` | `api.example.test` | `All`             |

## Routes

| Kind        | Name                       | Namespace   | sectionName | Expected attachment            |
| ----------- | -------------------------- | ----------- | ----------- | ------------------------------ |
| `HTTPRoute` | `backend-a-cross-ns-route` | `backend-a` | _(none)_    | Only `https-open` (port 50051) |

## Verification

What `verify.sh` checks:

1. Pod and certificate readiness.
2. Gateway is accepted.
3. `https-restricted` listener reports `attachedRoutes = 0` (cross-namespace route rejected).
4. `https-open` listener reports `attachedRoutes = 1` (cross-namespace route accepted).
5. HTTPS traffic on port 50051 succeeds (open listener serves the route).
6. **Negative:** HTTPS traffic on port 443 returns 404 (restricted listener has no attached routes — per-port isolation enforced).

## Related scenarios

| Scenario                                                                                                | Description                                                     |
| ------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| [namespace-restricted-split-port](../../02-listener-policy/namespace-restricted-split-port/README.md)   | Namespace restriction on split HTTP ports (different hostnames) |
| [namespace-restricted-shared-port](../../02-listener-policy/namespace-restricted-shared-port/README.md) | Namespace restriction on shared HTTPS port                      |
| [http-grpc-same-hostname](../http-grpc-same-hostname/README.md)                                         | Split ports, same hostname (no namespace restriction)           |

## Run

```sh
mise run //scenarios/03-multi-port/namespace-restricted-same-hostname-split-port:start
```
