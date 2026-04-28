# Kind-Restricted HTTPS + TLS Passthrough on Split Ports (443 / 9443)

> **Cilium bugs:**
>
> - [cilium/cilium#45559](https://github.com/cilium/cilium/issues/45559) — `allowedRoutes.kinds` per-listener scoping
> - [cilium/cilium#44889](https://github.com/cilium/cilium/pull/44889) — per-port CEC listener separation
> - [cilium/cilium#45371](https://github.com/cilium/cilium/pull/45371) — TLS passthrough ingestion

Same topology as [https-tls-same-hostname-split-port](../https-tls-same-hostname-split-port/README.md)
but with explicit `allowedRoutes.kinds` on each listener — the HTTPS listener
only accepts `HTTPRoute`, the TLS listener only accepts `TLSRoute`.

## Gateway listeners

| Listener | Protocol | Port   | Hostname           | TLS mode    | Allowed kinds |
| -------- | -------- | ------ | ------------------ | ----------- | ------------- |
| `https`  | HTTPS    | `443`  | `api.example.test` | Terminate   | `HTTPRoute`   |
| `tls`    | TLS      | `9443` | `api.example.test` | Passthrough | `TLSRoute`    |

## Routes

| Kind        | Name                    | Namespace   | Listener      | Backend                                |
| ----------- | ----------------------- | ----------- | ------------- | -------------------------------------- |
| `HTTPRoute` | `backend-a-https-route` | `backend-a` | `https` (443) | api:80                                 |
| `TLSRoute`  | `backend-b-tls-route`   | `backend-b` | `tls` (9443)  | backend-mtls:9443                      |
| `HTTPRoute` | `wrong-kind-http-route` | `backend-a` | `tls` (9443)  | _(negative test — should be rejected)_ |

## Verification

1. **HTTPS traffic on port 443** — `curl` to `api.example.test:443` succeeds (HTTPRoute on https listener).
2. **TLS passthrough on port 9443** — mTLS `curl` to `api.example.test:9443` succeeds (TLSRoute on tls listener).
3. **Negative: wrong-kind rejection** — `wrong-kind-http-route` (HTTPRoute targeting the `tls` listener) has `Accepted=False` or no parent status.
4. **`attachedRoutes` counts** — https listener has 1 (HTTPRoute only); tls listener has 1 (TLSRoute only).

## Status

⚠️ **Broken on all released versions** — requires kind-restriction fix
([#45559](https://github.com/cilium/cilium/issues/45559)), per-port listener
separation ([#44889](https://github.com/cilium/cilium/pull/44889)), and TLS
passthrough ingestion fix ([#45371](https://github.com/cilium/cilium/pull/45371)).

## Related scenarios

| Scenario                                                                                                          | Description                                       |
| ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| [https-tls-same-hostname-split-port](../https-tls-same-hostname-split-port/README.md)                             | Same topology without kind restriction            |
| [kind-restricted-https-tls-shared-port](../../02-listener-policy/kind-restricted-https-tls-shared-port/README.md) | HTTPS + TLS with kind restriction on shared port  |
| [kinds-split-port](../../02-listener-policy/kinds-split-port/README.md)                                           | HTTPS + gRPC with kind restriction on split ports |

## Run

```sh
mise run //scenarios/03-multi-port/kind-restricted-https-tls-split-port:start
```
