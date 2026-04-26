# namespace-restricted-split-port — Namespace restriction on split HTTP ports

Tests that `allowedRoutes.namespaces` is evaluated **independently per listener**
when two HTTP listeners are on different ports (80, 8080) with different hostnames.

**Bug:** [cilium#42159](https://github.com/cilium/cilium/issues/42159) — one listener's
namespace policy is incorrectly applied to all listeners.

| Listener          | Port | Hostname                  | `namespaces.from` | Expected `attachedRoutes`                         |
| ----------------- | ---- | ------------------------- | ----------------- | ------------------------------------------------- |
| `http-restricted` | 80   | `restricted.example.test` | `Same`            | 0 (route is in `backend-a`, not `gateway-system`) |
| `http-open`       | 8080 | `open.example.test`       | `All`             | 1                                                 |

The HTTPRoute in `backend-a` targets the gateway **without `sectionName`** and
specifies `hostnames: [open.example.test]`. Per the Gateway API spec, each listener
should independently evaluate its namespace policy.

## Difference from `namespaces/`

The [`namespaces`](../namespaces/README.md) scenario uses HTTP on split ports
(80/8080) **without hostnames**. This scenario adds explicit hostnames to each
listener, testing whether hostname-based listener matching affects the namespace
policy evaluation path.

## Note

Port 8080 is not mapped to the host in the kind cluster config, so this scenario
verifies via `attachedRoutes` status only (no traffic test).

## Run

```sh
mise run //scenarios/02-listener-policy/namespace-restricted-split-port:start
```
