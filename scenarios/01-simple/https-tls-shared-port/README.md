# https-tls-shared-port — HTTPS termination + TLS passthrough on same port

One Gateway with two listeners on **port 443** using disjoint hostnames:

- **HTTPS** (`web.example.test`) — TLS termination, routes to `backend-http` via HTTPRoute.
- **TLS** (`mtls-b.example.test`) — passthrough, forwards to `backend-mtls` via TLSRoute.

mTLS succeeding on the passthrough side proves the Gateway did not terminate TLS — if it had, the certificate would be the Gateway cert (wrong CA) and the mTLS handshake would fail.

## Resources

| Resource                                                | Namespace      | Purpose                             |
| ------------------------------------------------------- | -------------- | ----------------------------------- |
| Gateway `https-tls-same-port-gateway`                   | gateway-system | Two listeners on port 443           |
| Certificate `https-tls-shared-port-gateway-certificate` | gateway-system | TLS cert for HTTPS listener         |
| HTTPRoute `backend-a-web-route`                         | backend-a      | HTTPS termination → go-httpbin      |
| TLSRoute `backend-b-mtls-route`                         | backend-b      | TLS passthrough → backend-mtls      |
| Pod `api`                                               | backend-a      | go-httpbin (HTTP backend)           |
| Pod `backend-mtls`                                      | backend-b      | Envoy with per-namespace mTLS certs |

## Verification

What `verify.sh` checks:

1. All pods and certificates reach Ready state.
2. Gateway is Accepted.
3. HTTPRoute and TLSRoute are Accepted by their parent Gateway.
4. Per-listener `attachedRoutes` counts are correct (1 each for `https` and `tls`).
5. HTTPS termination works — `web.example.test` returns a successful response on port 443.
6. TLS passthrough works — `mtls-b.example.test` completes a full mTLS handshake on port 443 using the backend's own CA and client certificate.
7. TLSRoute Accepted status message is correct.

## Related scenarios

- [no-sectionname](../../02-listener-policy/no-sectionname/README.md) — variant where the TLSRoute omits `sectionName`.

## Run

```sh
mise run //scenarios/01-simple/https-tls-shared-port:start
```
