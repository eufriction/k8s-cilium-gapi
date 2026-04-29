# https — HTTPS termination with multi-namespace HTTPRoutes

One Gateway terminates TLS on port 443 via a self-signed cert-manager certificate,
routing to two HTTPRoute backends in separate namespaces by hostname
(`https-a.example.test`, `https-b.example.test`). This is the HTTPS counterpart
to the plaintext `http` scenario and establishes the simplest possible
TLS-termination pattern.

## Resources

| Resource                                | Namespace      | Purpose                                    |
| --------------------------------------- | -------------- | ------------------------------------------ |
| Gateway `https-multi-namespace-gateway` | gateway-system | TLS-terminating listener on port 443       |
| Certificate `https-gateway-certificate` | gateway-system | Self-signed wildcard TLS cert              |
| HTTPRoute `backend-a-https-route`       | backend-a      | Routes `https-a.example.test` to backend-a |
| HTTPRoute `backend-b-https-route`       | backend-b      | Routes `https-b.example.test` to backend-b |
| Pod `api`                               | backend-a      | go-httpbin backend                         |
| Pod `api`                               | backend-b      | go-httpbin backend                         |
| Pod `netshoot-client`                   | client         | In-cluster debugging client                |

## Verification

What `verify.sh` checks:

1. All pods and the TLS certificate reach Ready state.
2. Gateway is Accepted.
3. Both HTTPRoutes are Accepted by the gateway.
4. Listener `https` reports 2 attached routes.
5. HTTPS request to `https-a.example.test` succeeds.
6. HTTPS request to `https-b.example.test` succeeds.
7. Both HTTPRoutes report `Accepted HTTPRoute` in their status message.

## Related scenarios

- [`http`](../http/README.md) — plaintext HTTP variant

## Run

```sh
mise run //scenarios/01-simple/https:start
```
