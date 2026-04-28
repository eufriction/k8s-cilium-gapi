# Scenario 36 — allowedRoutes.namespaces per-listener enforcement

Tests that `allowedRoutes.namespaces` is evaluated **independently per listener** when an HTTPRoute omits `sectionName`.

**Bug:** [cilium#42159](https://github.com/cilium/cilium/issues/42159) — one listener's namespace policy is incorrectly applied to all listeners.

| Listener          | Port | `namespaces.from` | Expected `attachedRoutes`                         |
| ----------------- | ---- | ----------------- | ------------------------------------------------- |
| `http-restricted` | 80   | `Same`            | 0 (route is in `backend-a`, not `gateway-system`) |
| `http-open`       | 8080 | `All`             | 1                                                 |

The HTTPRoute in `backend-a` references the Gateway without `sectionName`. Per the Gateway API spec, each listener should independently evaluate its namespace policy.

## Verification

1. **`attachedRoutes` status** — restricted listener (port 80) has 0 attached routes;
   open listener (port 8080) has 1.
2. **Traffic on port 8080** — `curl` to `web.example.test:8080` succeeds (open listener).
3. **Negative on port 80** — `curl` to `restricted.example.test:80` returns 404
   (no routes attached to the restricted listener). The negative test uses a
   non-matching hostname because Cilium's data plane merges Envoy filter chains
   across listeners sharing the same IP, leaking the open-listener route onto
   port 80 for the same hostname ([cilium#42159](https://github.com/cilium/cilium/issues/42159) data-plane half).
