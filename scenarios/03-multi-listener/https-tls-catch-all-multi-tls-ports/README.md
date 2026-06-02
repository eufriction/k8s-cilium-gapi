# Catch-all HTTPS termination and multi-port TLS passthrough

This scenario tests that a single Gateway can serve HTTPS-terminated traffic and
multiple TLS-passthrough listeners with **catch-all Gateway listener hostnames**.
All requests use `api.example.test` as the requested Host/SNI.

The Gateway exposes HTTPS termination on port `443` and TLS passthrough on ports
`50051` and `9443`. The `HTTPRoute` is catch-all; both `TLSRoute`s keep an
explicit hostname because `TLSRoute` requires `spec.hostnames` to contain valid
DNS hostnames.

The port is the sole protocol discriminator. mTLS succeeding on both TLS
passthrough ports **proves** the Gateway did not terminate TLS. If it had, the
certificate would be the Gateway cert (wrong CA) and the mTLS handshake would
fail.

## Resources

| Resource                                   | Namespace        | Purpose                                                     |
| ------------------------------------------ | ---------------- | ----------------------------------------------------------- |
| `Gateway/https-tls-multi-tls-port-gateway` | `gateway-system` | One HTTPS listener and two TLS passthrough listeners        |
| `HTTPRoute/backend-a-https-route`          | `backend-a`      | Routes HTTPS traffic on port 443 to `api:80`                |
| `TLSRoute/backend-b-tls-route-50051`       | `backend-b`      | Routes TLS passthrough on port 50051 to `backend-mtls:9443` |
| `TLSRoute/backend-b-tls-route-9443`        | `backend-b`      | Routes TLS passthrough on port 9443 to `backend-mtls:9443`  |
| `pod/api`                                  | `backend-a`      | HTTP backend                                                |
| `pod/backend-mtls`                         | `backend-b`      | mTLS backend with its own PKI                               |

## Gateway listeners

| Listener    | Protocol | Port    | Hostname  | TLS mode    |
| ----------- | -------- | ------- | --------- | ----------- |
| `https`     | HTTPS    | `443`   | catch-all | Terminate   |
| `tls-50051` | TLS      | `50051` | catch-all | Passthrough |
| `tls-9443`  | TLS      | `9443`  | catch-all | Passthrough |

## Routes

| Kind        | Name                        | Namespace   | Listener      | Backend             |
| ----------- | --------------------------- | ----------- | ------------- | ------------------- |
| `HTTPRoute` | `backend-a-https-route`     | `backend-a` | `https` (443) | `api:80`            |
| `TLSRoute`  | `backend-b-tls-route-50051` | `backend-b` | `tls-50051`   | `backend-mtls:9443` |
| `TLSRoute`  | `backend-b-tls-route-9443`  | `backend-b` | `tls-9443`    | `backend-mtls:9443` |

## Verification

What `verify.sh` checks:

1. All pods and certificates reach Ready state.
2. Gateway is Accepted.
3. `HTTPRoute/backend-a-https-route` and both `TLSRoute`s are Accepted and have `ResolvedRefs=True`.
4. Listener `https` reports 1 attached route; listeners `tls-50051` and `tls-9443` each report 1 attached route.
5. HTTPS termination: the catch-all Gateway listener/HTTPRoute accepts `curl` to `api.example.test:443`.
6. TLS passthrough: both catch-all TLS listeners plus explicit `TLSRoute` hostnames accept mTLS `curl` to `api.example.test:50051` and `api.example.test:9443`.
7. TLSRoute status messages are validated.

## Related scenarios

| Scenario                                                                      | Description                                      |
| ----------------------------------------------------------------------------- | ------------------------------------------------ |
| [`https-tls-catch-all`](../https-tls-catch-all/README.md)                     | Same protocol mix but with one TLS listener port |
| [`https-tls-same-hostname`](../https-tls-same-hostname/README.md)             | Same protocol mix but with explicit hostname     |
| [`tls-passthrough-same-hostname`](../tls-passthrough-same-hostname/README.md) | TLS-only passthrough on split ports              |
| [`tls-split-port`](../tls-split-port/README.md)                               | TLS-only passthrough on two listener ports       |

## Run

```sh
mise run //scenarios/03-multi-listener/https-tls-catch-all-multi-tls-ports:start
```
