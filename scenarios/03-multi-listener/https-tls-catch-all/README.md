# Catch-all HTTPS termination and TLS passthrough on different ports

This scenario tests that a single Gateway can serve both HTTPS-terminated and
TLS-passthrough traffic with **catch-all Gateway listener hostnames**, using
`api.example.test` as the requested Host/SNI, on **different ports**: HTTPS
termination on `443` and TLS passthrough on `9443`. The `HTTPRoute` is also
catch-all; the `TLSRoute` keeps an explicit hostname because `TLSRoute` requires
`spec.hostnames` to contain valid DNS hostnames.

The port is the sole protocol discriminator. mTLS succeeding on port 9443
**proves** the Gateway did not terminate TLS. If it had, the certificate would
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

| Listener | Protocol | Port   | Hostname  | TLS mode    |
| -------- | -------- | ------ | --------- | ----------- |
| `https`  | HTTPS    | `443`  | catch-all | Terminate   |
| `tls`    | TLS      | `9443` | catch-all | Passthrough |

## Routes

| Kind        | Name                    | Namespace   | Listener      | Backend             |
| ----------- | ----------------------- | ----------- | ------------- | ------------------- |
| `HTTPRoute` | `backend-a-https-route` | `backend-a` | `https` (443) | api:80              |
| `TLSRoute`  | `backend-b-tls-route`   | `backend-b` | `tls` (9443)  | `backend-mtls:9443` |

## Verification

What `verify.sh` checks:

1. All pods and certificates reach Ready state.
2. Gateway is Accepted.
3. `HTTPRoute/backend-a-https-route` and `TLSRoute/backend-b-tls-route` are Accepted.
4. Listener `https` reports 1 attached route; listener `tls` reports 1 attached route.
5. HTTPS termination: the catch-all Gateway listener/HTTPRoute accepts `curl` to `api.example.test:443`.
6. TLS passthrough: the catch-all Gateway listener plus explicit `TLSRoute` hostname accepts mTLS `curl` to `api.example.test:9443` (using backend-b's own CA and client cert).
7. TLSRoute status message is validated.

## Related scenarios

| Scenario                                                                      | Description                                        |
| ----------------------------------------------------------------------------- | -------------------------------------------------- |
| [`https-tls-same-hostname`](../https-tls-same-hostname/README.md)             | Same protocol mix but with explicit same hostname  |
| [`https-tls-shared-port`](../https-tls-shared-port/README.md)                 | Same protocol mix but on **shared** port 443       |
| [`tls-passthrough-same-hostname`](../tls-passthrough-same-hostname/README.md) | TLS-only passthrough on split ports, same hostname |
| [`http-grpc-same-hostname`](../http-grpc-same-hostname/README.md)             | HTTPS + gRPC on split ports, same hostname         |

## Run

```sh
mise run //scenarios/03-multi-listener/https-tls-catch-all:start
```
