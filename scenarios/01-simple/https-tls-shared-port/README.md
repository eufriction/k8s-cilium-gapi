# Scenario 25 — HTTPS termination + TLS passthrough on same port

One Gateway, two listeners on **port 443** with disjoint hostnames:

- `HTTPS / web.example.test` — TLS termination, routes to `backend-http` via HTTPRoute
- `TLS / mtls-b.example.test` — passthrough, forwards to `backend-mtls` via TLSRoute

mTLS succeeding on the passthrough side **proves** the Gateway did not terminate TLS — if it had, the certificate would be the Gateway cert (wrong CA) and the mTLS handshake would fail.

## Resources

| Resource                              | Namespace      | Purpose                             |
| ------------------------------------- | -------------- | ----------------------------------- |
| Gateway `https-tls-same-port-gateway` | gateway-system | Two listeners on port 443           |
| HTTPRoute `backend-a-web-route`       | backend-a      | HTTPS termination → go-httpbin      |
| TLSRoute `backend-b-mtls-route`       | backend-b      | TLS passthrough → backend-mtls      |
| Pod `api`                             | backend-a      | go-httpbin (HTTP backend)           |
| Pod `backend-mtls`                    | backend-b      | Envoy with per-namespace mTLS certs |

## Status

✅ Passes on 1.19.3. This scenario validates that HTTPS termination and TLS passthrough coexist on the same port when listeners have disjoint hostnames.

See [scenario 26](../26-tlsroute-no-sectionname/README.md) for the variant where the TLSRoute omits `sectionName` (triggers [cilium#45050](https://github.com/cilium/cilium/issues/45050)).

## Run

```sh
mise run //scenarios/01-simple/https-tls-shared-port:start
```
