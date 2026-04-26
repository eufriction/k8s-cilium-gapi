# Namespace-Restricted Same-Hostname HTTPS on Split Ports (443 / 50051)

> **Cilium bugs:**
>
> - [cilium/cilium#42159](https://github.com/cilium/cilium/issues/42159) — `allowedRoutes.namespaces` per-listener enforcement
> - [cilium/cilium#44889](https://github.com/cilium/cilium/pull/44889) — per-port CEC listener separation

This scenario tests that `allowedRoutes.namespaces` is evaluated **independently
per listener** when two HTTPS listeners share the **same hostname**
(`api.example.test`) but use **different ports** (443, 50051).

## Gateway listeners

| Listener           | Protocol | Port    | Hostname           | `namespaces.from` |
| ------------------ | -------- | ------- | ------------------ | ----------------- |
| `https-restricted` | HTTPS    | `443`   | `api.example.test` | `Same`            |
| `https-open`       | HTTPS    | `50051` | `api.example.test` | `All`             |

## Routes

| Kind        | Name                       | Namespace   | sectionName | Expected attachment            |
| ----------- | -------------------------- | ----------- | ----------- | ------------------------------ |
| `HTTPRoute` | `backend-a-cross-ns-route` | `backend-a` | _(none)_    | Only `https-open` (port 50051) |

The HTTPRoute targets the gateway **without `sectionName`** and specifies
`hostnames: [api.example.test]`. Both listeners match the hostname, but the
restricted listener should reject the cross-namespace route.

## Verification

1. `https-restricted` listener: `attachedRoutes = 0`
2. `https-open` listener: `attachedRoutes = 1`
3. HTTPS traffic on port 50051 succeeds

## Status

⚠️ **Broken on all released versions** — requires namespace restriction fix
([#42159](https://github.com/cilium/cilium/issues/42159)) and per-port listener
separation ([#44889](https://github.com/cilium/cilium/pull/44889)).

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
