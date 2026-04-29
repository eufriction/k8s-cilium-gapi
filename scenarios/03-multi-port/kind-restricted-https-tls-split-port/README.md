# kind-restricted-https-tls-split-port — HTTPS + TLS passthrough with `allowedRoutes.kinds` on split ports

Same topology as [https-tls-same-hostname-split-port](../https-tls-same-hostname-split-port/README.md)
but with explicit `allowedRoutes.kinds` on each listener — the HTTPS listener
only accepts `HTTPRoute`, the TLS listener only accepts `TLSRoute`. A deliberate
wrong-kind `HTTPRoute` targeting the TLS listener is included as a negative test
to confirm per-listener kind enforcement.

## Resources

| Resource                                               | Namespace        | Purpose                                                                 |
| ------------------------------------------------------ | ---------------- | ----------------------------------------------------------------------- |
| `Gateway/kind-restricted-https-tls-split-port-gateway` | `gateway-system` | Two listeners with kind restrictions                                    |
| `HTTPRoute/backend-a-https-route`                      | `backend-a`      | HTTPS traffic on port 443 → api:80                                      |
| `TLSRoute/backend-b-tls-route`                         | `backend-b`      | TLS passthrough on port 9443 → backend-mtls:9443                        |
| `HTTPRoute/wrong-kind-http-route`                      | `backend-a`      | Negative test — HTTPRoute targeting `tls` listener (should be rejected) |
| `Pod/api`                                              | `backend-a`      | HTTP backend                                                            |
| `Pod/backend-mtls`                                     | `backend-b`      | mTLS backend (TLS passthrough target)                                   |

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

What `verify.sh` checks:

1. All pods and certificates are ready.
2. Gateway is `Accepted`.
3. `backend-a-https-route` (HTTPRoute) and `backend-b-tls-route` (TLSRoute) are `Accepted`.
4. HTTPS termination on port 443 — `curl` to `api.example.test:443` succeeds (HTTPRoute on `https` listener).
5. TLS passthrough on port 9443 — mTLS `curl` to `api.example.test:9443` succeeds, proving the Gateway did not terminate TLS.
6. **Negative: wrong-kind rejection** — `wrong-kind-http-route` (HTTPRoute targeting the `tls` listener) has `Accepted=False` or no parent status.
7. `attachedRoutes` counts — `https` listener reports 1 (`HTTPRoute` only); `tls` listener reports 1 (`TLSRoute` only).
8. TLSRoute status message is well-formed.

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
