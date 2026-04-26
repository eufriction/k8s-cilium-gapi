# HTTPS + TLS Passthrough Same Hostname on Split Ports (443 / 9443)

> **Cilium bugs:**
>
> - [cilium/cilium#44889](https://github.com/cilium/cilium/pull/44889) — per-port CEC listener separation
> - [cilium/cilium#45371](https://github.com/cilium/cilium/pull/45371) — TLS passthrough ingestion

This scenario tests that a single Gateway can serve both HTTPS-terminated and
TLS-passthrough traffic on the **same hostname** (`api.example.test`) but
**different ports** — HTTPS termination on `443` and TLS passthrough on `9443`.

The port is the sole protocol discriminator. mTLS succeeding on port 9443
**proves** the Gateway did not terminate TLS — if it had, the certificate would
be the Gateway cert (wrong CA) and the mTLS handshake would fail.

## Gateway listeners

| Listener | Protocol | Port   | Hostname           | TLS mode    |
| -------- | -------- | ------ | ------------------ | ----------- |
| `https`  | HTTPS    | `443`  | `api.example.test` | Terminate   |
| `tls`    | TLS      | `9443` | `api.example.test` | Passthrough |

## Routes

| Kind        | Name                    | Namespace   | Listener      | Backend           |
| ----------- | ----------------------- | ----------- | ------------- | ----------------- |
| `HTTPRoute` | `backend-a-https-route` | `backend-a` | `https` (443) | api:80            |
| `TLSRoute`  | `backend-b-tls-route`   | `backend-b` | `tls` (9443)  | backend-mtls:9443 |

## Status

⚠️ **Broken on all released versions** — requires per-port listener separation
([#44889](https://github.com/cilium/cilium/pull/44889)) and TLS passthrough
ingestion fix ([#45371](https://github.com/cilium/cilium/pull/45371)).

## Related scenarios

| Scenario                                                                    | Description                                          |
| --------------------------------------------------------------------------- | ---------------------------------------------------- |
| [https-tls-shared-port](../../01-simple/https-tls-shared-port/README.md)    | Same protocol mix but on **shared** port 443 (works) |
| [tls-passthrough-same-hostname](../tls-passthrough-same-hostname/README.md) | TLS-only passthrough on split ports, same hostname   |
| [http-grpc-same-hostname](../http-grpc-same-hostname/README.md)             | HTTPS + gRPC on split ports, same hostname           |

## Run

```sh
mise run //scenarios/03-multi-port/https-tls-same-hostname-split-port:start
```
