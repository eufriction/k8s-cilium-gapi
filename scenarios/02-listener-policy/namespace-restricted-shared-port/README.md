# namespace-restricted-shared-port — Namespace restriction on shared HTTPS port

Tests that `allowedRoutes.namespaces` is evaluated **independently per listener**
when two HTTPS listeners share port 443 with different hostnames.

**Bug:** [cilium#42159](https://github.com/cilium/cilium/issues/42159) — one listener's
namespace policy is incorrectly applied to all listeners.

| Listener           | Port | Hostname                  | `namespaces.from` | Expected `attachedRoutes`                         |
| ------------------ | ---- | ------------------------- | ----------------- | ------------------------------------------------- |
| `https-restricted` | 443  | `restricted.example.test` | `Same`            | 0 (route is in `backend-a`, not `gateway-system`) |
| `https-open`       | 443  | `open.example.test`       | `All`             | 1                                                 |

The HTTPRoute in `backend-a` targets the gateway **without `sectionName`**. Per the
Gateway API spec, each listener should independently evaluate its namespace policy.

## Difference from `namespaces/`

The [`namespaces`](../namespaces/README.md) scenario uses HTTP on split ports (80/8080).
This scenario uses HTTPS on a **shared port** (443) with different hostnames, testing
whether the Cilium operator correctly evaluates namespace restrictions when listeners
share a port but differ by hostname.

## Run

```sh
mise run //scenarios/02-listener-policy/namespace-restricted-shared-port:start
```
