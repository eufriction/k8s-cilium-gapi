# tls-split-port — Two TLS passthrough listeners on separate ports

Two TLS passthrough listeners on different ports (`9443` and `50051`), each with
a distinct hostname and independent mTLS CA chain. The Gateway does not terminate
TLS — each backend's Envoy sidecar terminates TLS and enforces client certificate
verification against its own namespace-scoped CA.

## Resources

| Resource                         | Namespace      | Purpose                                               |
| -------------------------------- | -------------- | ----------------------------------------------------- |
| Gateway `tls-split-port-gateway` | gateway-system | Two TLS passthrough listeners on ports 9443 and 50051 |
| TLSRoute `backend-a-mtls-route`  | backend-a      | Passthrough to backend-mtls on port 9443              |
| TLSRoute `backend-b-mtls-route`  | backend-b      | Passthrough to backend-mtls on port 50051             |
| Pod `backend-mtls`               | backend-a      | Envoy with per-namespace mTLS certs                   |
| Pod `backend-mtls`               | backend-b      | Envoy with per-namespace mTLS certs                   |
| Certificate (CA, server, client) | backend-a      | Independent PKI for backend-a                         |
| Certificate (CA, server, client) | backend-b      | Independent PKI for backend-b                         |

## Verification

What `verify.sh` checks:

1. All pods and certificates are ready
2. Gateway is accepted
3. Both TLSRoutes are accepted
4. Listener `mtls-a` reports 1 attached TLSRoute; listener `mtls-b` reports 1 attached TLSRoute
5. `mtls-a.example.test:9443` — backend-a accepts correct client cert
6. `mtls-b.example.test:50051` — backend-b accepts correct client cert
7. backend-a rejects requests with missing client cert (mTLS enforcement)
8. backend-b rejects requests with missing client cert (mTLS enforcement)
9. TLSRoute accepted status message is correct for both routes

## Run

```sh
mise run //scenarios/01-simple/tls-split-port:start
```
