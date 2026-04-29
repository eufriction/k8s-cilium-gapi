# https-tls-same-hostname-split-port — HTTPS termination + TLS passthrough on same hostname, different ports

This scenario tests that a single Gateway can serve both HTTPS-terminated and
TLS-passthrough traffic on the **same hostname** (`api.example.test`) but
**different ports** — HTTPS termination on `443` and TLS passthrough on `9443`.

The port is the sole protocol discriminator. mTLS succeeding on port 9443
**proves** the Gateway did not terminate TLS — if it had, the certificate would
be the Gateway cert (wrong CA) and the mTLS handshake would fail.

## Resources

| Resource                               | Namespace        | Purpose                                                       |
| -------------------------------------- | ---------------- | ------------------------------------------------------------- |
| `Gateway/https-tls-split-port-gateway` | `gateway-system` | Two listeners: HTTPS terminate (443) + TLS passthrough (9443) |
| `HTTPRoute/backend-a-https-route`      | `backend-a`      | Routes HTTPS traffic on port 443 to `api:80`                  |
| `TLSRoute/backend-b-tls-route`         | `backend-b`      | Routes TLS passthrough on port 9443 to `backend-mtls:9443`    |
| `pod/api`                              | `backend-a`      | HTTP backend                                                  |
| `pod/backend-mtls`                     | `backend-b`      | mTLS backend with its own PKI                                 |

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

## Verification

What `verify.sh` checks:

1. All pods and certificates reach Ready state.
2. Gateway is Accepted.
3. `HTTPRoute/backend-a-https-route` and `TLSRoute/backend-b-tls-route` are Accepted.
4. Listener `https` reports 1 attached route; listener `tls` reports 1 attached route.
5. HTTPS termination — `curl` to `api.example.test:443` succeeds.
6. TLS passthrough — mTLS `curl` to `api.example.test:9443` succeeds (using backend-b's own CA and client cert).
7. TLSRoute status message is validated.

## Related scenarios

| Scenario                                                                    | Description                                        |
| --------------------------------------------------------------------------- | -------------------------------------------------- |
| [https-tls-shared-port](../../01-simple/https-tls-shared-port/README.md)    | Same protocol mix but on **shared** port 443       |
| [tls-passthrough-same-hostname](../tls-passthrough-same-hostname/README.md) | TLS-only passthrough on split ports, same hostname |
| [http-grpc-same-hostname](../http-grpc-same-hostname/README.md)             | HTTPS + gRPC on split ports, same hostname         |

## Run

```sh
mise run //scenarios/03-multi-port/https-tls-same-hostname-split-port:start
```
