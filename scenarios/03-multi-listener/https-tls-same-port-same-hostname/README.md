# Invalid HTTPS and TLS passthrough collision on same port and hostname

One Gateway with two listeners on **port 443** using the **same hostname**:

- **HTTPS** (`api.example.test`): TLS termination, routes to `backend-http` via HTTPRoute.
- **TLS** (`api.example.test`): passthrough, forwards to `backend-mtls` via TLSRoute.

This combination produces identical SNI matchers for HTTPS termination and TLS
passthrough on the same port. Splitting by port cannot fix this configuration;
Cilium should reject it or report a listener conflict instead of accepting both
listeners/routes as if the data plane can serve both correctly.

## Resources

| Resource                                                    | Namespace      | Purpose                                |
| ----------------------------------------------------------- | -------------- | -------------------------------------- |
| Gateway `https-tls-same-port-same-hostname-gateway`         | gateway-system | Invalid HTTPS + TLS same hostname/port |
| Certificate `https-tls-same-port-same-hostname-certificate` | gateway-system | TLS cert for HTTPS listener            |
| HTTPRoute `backend-a-web-route`                             | backend-a      | HTTPS termination route                |
| TLSRoute `backend-b-mtls-route`                             | backend-b      | TLS passthrough route                  |
| Pod `api`                                                   | backend-a      | go-httpbin HTTP backend                |
| Pod `backend-mtls`                                          | backend-b      | Envoy with per-namespace mTLS certs    |

## Verification

What `verify.sh` checks:

1. Certificates are ready so the controller has all required inputs.
2. Gateway/listener and route statuses are reconciled.
3. The scenario passes only if at least one of the following is true:
   - HTTPS listener is not accepted
   - TLS listener is not accepted
   - Either listener is marked conflicted
   - Either route is not accepted

This scenario is expected to fail on implementations that accept the invalid
same-port same-hostname HTTPS/TLS combination.

## Run

```sh
mise run //scenarios/03-multi-listener/https-tls-same-port-same-hostname:start
```
