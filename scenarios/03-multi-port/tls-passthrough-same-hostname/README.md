# Scenario 35 — TLS passthrough same hostname, split ports

Two TLS Passthrough listeners on the **same hostname** (`tls.example.test`) but **different ports** (443, 9443). Each listener forwards to a separate `backend-mtls` instance via TLSRoute with explicit `sectionName`.

**Bug:** [cilium#42898](https://github.com/cilium/cilium/issues/42898) — second TLSRoute silently stops routing when both listeners share a hostname.

| Resource                       | Namespace | Port | Backend                  |
| ------------------------------ | --------- | ---- | ------------------------ |
| TLSRoute `backend-a-tls-route` | backend-a | 443  | backend-mtls (backend-a) |
| TLSRoute `backend-b-tls-route` | backend-b | 9443 | backend-mtls (backend-b) |

Each namespace has its own PKI (self-signed CA). mTLS with the correct CA proves which backend handled the connection.

## Resources

| Resource                                      | Namespace      | Purpose                                           |
| --------------------------------------------- | -------------- | ------------------------------------------------- |
| Gateway `tls-passthrough-split-ports-gateway` | gateway-system | Two TLS passthrough listeners on ports 443 & 9443 |
| TLSRoute `backend-a-tls-route`                | backend-a      | TLS passthrough on port 443 → backend-mtls        |
| TLSRoute `backend-b-tls-route`                | backend-b      | TLS passthrough on port 9443 → backend-mtls       |
| Pod `backend-mtls`                            | backend-a      | Envoy with backend-a mTLS certs                   |
| Pod `backend-mtls`                            | backend-b      | Envoy with backend-b mTLS certs                   |

## Run

```sh
mise run //scenarios/03-multi-port/tls-passthrough-same-hostname:start
```
