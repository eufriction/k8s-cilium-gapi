# tls-passthrough-same-hostname — TLS passthrough on split ports with shared hostname

Two TLS Passthrough listeners on the **same hostname** (`tls.example.test`) but
**different ports** (443, 9443). Each listener forwards to a separate
`backend-mtls` instance via a TLSRoute with explicit `sectionName`. Each
namespace has its own PKI (self-signed CA), so successful mTLS with the correct
CA proves which backend handled the connection and that the Gateway did not
terminate TLS.

## Resources

| Resource                                      | Namespace        | Purpose                                           |
| --------------------------------------------- | ---------------- | ------------------------------------------------- |
| Gateway `tls-passthrough-split-ports-gateway` | `gateway-system` | Two TLS passthrough listeners on ports 443 & 9443 |
| TLSRoute `backend-a-tls-route`                | `backend-a`      | TLS passthrough on port 443 → backend-mtls        |
| TLSRoute `backend-b-tls-route`                | `backend-b`      | TLS passthrough on port 9443 → backend-mtls       |
| Pod `backend-mtls`                            | `backend-a`      | Envoy with backend-a mTLS certs                   |
| Pod `backend-mtls`                            | `backend-b`      | Envoy with backend-b mTLS certs                   |

## Gateway listeners

| Listener   | Protocol | Port   | Hostname           | TLS mode    |
| ---------- | -------- | ------ | ------------------ | ----------- |
| `tls-443`  | TLS      | `443`  | `tls.example.test` | Passthrough |
| `tls-9443` | TLS      | `9443` | `tls.example.test` | Passthrough |

## Routes

| Kind       | Name                  | Namespace   | Listener          | Backend                  |
| ---------- | --------------------- | ----------- | ----------------- | ------------------------ |
| `TLSRoute` | `backend-a-tls-route` | `backend-a` | `tls-443` (443)   | backend-mtls (backend-a) |
| `TLSRoute` | `backend-b-tls-route` | `backend-b` | `tls-9443` (9443) | backend-mtls (backend-b) |

## Verification

What `verify.sh` checks:

1. All pods and mTLS certificates (both namespaces) are Ready.
2. Gateway `tls-passthrough-split-ports-gateway` is Accepted.
3. Both TLSRoutes (`backend-a-tls-route`, `backend-b-tls-route`) are Accepted.
4. Listener `tls-443` reports `attachedRoutes = 1` (TLSRoute only).
5. Listener `tls-9443` reports `attachedRoutes = 1` (TLSRoute only).
6. **TLS passthrough on port 443** — mTLS curl with backend-a's CA and client cert succeeds, proving traffic reached backend-a without Gateway TLS termination.
7. **TLS passthrough on port 9443** — mTLS curl with backend-b's CA and client cert succeeds, proving traffic reached backend-b without Gateway TLS termination.
8. TLSRoute status message assertions for both routes.

## Related scenarios

| Scenario                                                                              | Description                                                       |
| ------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| [https-tls-same-hostname-split-port](../https-tls-same-hostname-split-port/README.md) | HTTPS termination + TLS passthrough on split ports, same hostname |
| [http-grpc-same-hostname](../http-grpc-same-hostname/README.md)                       | HTTPS + gRPC on split ports, same hostname                        |

## Run

```sh
mise run //scenarios/03-multi-port/tls-passthrough-same-hostname:start
```
