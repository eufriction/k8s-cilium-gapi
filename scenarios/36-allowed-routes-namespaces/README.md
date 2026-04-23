# Scenario 36 — allowedRoutes.namespaces per-listener enforcement

Tests that `allowedRoutes.namespaces` is evaluated **independently per listener** when an HTTPRoute omits `sectionName`.

**Bug:** [cilium#42159](https://github.com/cilium/cilium/issues/42159) — one listener's namespace policy is incorrectly applied to all listeners.

| Listener          | Port | `namespaces.from` | Expected `attachedRoutes`                         |
| ----------------- | ---- | ----------------- | ------------------------------------------------- |
| `http-restricted` | 80   | `Same`            | 0 (route is in `backend-a`, not `gateway-system`) |
| `http-open`       | 8080 | `All`             | 1                                                 |

The HTTPRoute in `backend-a` references the Gateway without `sectionName`. Per the Gateway API spec, each listener should independently evaluate its namespace policy.
