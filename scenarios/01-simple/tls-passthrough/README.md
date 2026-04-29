# tls-passthrough — Multi-namespace mTLS with TLS passthrough

This scenario tests TLSRoute passthrough with per-namespace mTLS enforcement.
A single Gateway listener on port 9443 performs TLS passthrough (SNI-based
routing without terminating TLS). Two `backend-mtls` instances in separate
namespaces each run an Envoy sidecar that terminates TLS and enforces client
certificate verification against its own CA.

Each namespace has an independent PKI chain (CA → server cert, client cert).
This proves that the Gateway does not interfere with the TLS handshake and
that cross-namespace client certificates are correctly rejected.

## Resources

| Resource                                        | Namespace      | Purpose                                   |
| ----------------------------------------------- | -------------- | ----------------------------------------- |
| Gateway `mtls-multi-namespace-gateway`          | gateway-system | TLS passthrough listener on port 9443     |
| TLSRoute `backend-a-mtls-route`                 | backend-a      | Routes `mtls-a.example.test` to backend-a |
| TLSRoute `backend-b-mtls-route`                 | backend-b      | Routes `mtls-b.example.test` to backend-b |
| Pod `backend-mtls`                              | backend-a      | Envoy with per-namespace mTLS certs       |
| Pod `backend-mtls`                              | backend-b      | Envoy with per-namespace mTLS certs       |
| Certificate `backend-a-mtls-{ca,server,client}` | backend-a      | CA chain and leaf certs for backend-a     |
| Certificate `backend-b-mtls-{ca,server,client}` | backend-b      | CA chain and leaf certs for backend-b     |
| Pod `netshoot-client`                           | client         | In-cluster debugging client               |

## Verification

What `verify.sh` checks:

1. All pods and certificates reach Ready state
2. Gateway `mtls-multi-namespace-gateway` is Accepted
3. Both TLSRoutes are Accepted by the gateway
4. Listener `mtls` reports 2 attached TLSRoutes
5. `mtls-a.example.test:9443` accepts the correct (backend-a) client certificate
6. `mtls-b.example.test:9443` accepts the correct (backend-b) client certificate
7. `mtls-a.example.test:9443` rejects requests with no client certificate (proves mTLS enforcement)
8. `mtls-b.example.test:9443` rejects backend-a's client certificate (proves cross-namespace CA isolation)
9. TLSRoute Accepted status message is correct for both routes

## Run

```sh
mise run //scenarios/01-simple/tls-passthrough:start
```
