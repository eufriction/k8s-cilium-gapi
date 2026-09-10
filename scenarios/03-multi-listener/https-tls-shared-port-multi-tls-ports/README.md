# HTTPS/TLS shared port with multiple TLS passthrough ports

This scenario is a regression test for [Cilium issue #48269](https://github.com/cilium/cilium/issues/48269).
It combines the two conditions that are covered separately by the closest
scenarios: multiple TLS-passthrough ports and disjoint HTTPS/TLS-passthrough
listeners sharing a port on one Gateway.

The Gateway has two independent TLS-passthrough listeners on ports `50051` and
`9443`. It also has an HTTPS-terminated listener and a TLS-passthrough listener
with disjoint hostnames sharing port `443`. The repository's exposed split TLS
ports are used instead of the issue's example ports `8443` and `8883`.

The explicit hostnames ensure that the HTTPS and TLS listeners on port `443`
do not have a Gateway API protocol conflict. The mTLS backend certificate
contains all three passthrough hostnames so each TLS route can be verified
independently.

## Resources

| Resource                                                | Namespace        | Purpose                                              |
| ------------------------------------------------------- | ---------------- | ---------------------------------------------------- |
| `Gateway/https-tls-shared-port-multi-tls-ports-gateway` | `gateway-system` | Two split TLS ports plus a shared HTTPS/TLS port     |
| `HTTPRoute/backend-a-https-route-c`                     | `backend-a`      | HTTPS termination on `web.example.test:443`          |
| `TLSRoute/backend-b-tls-route-a`                        | `backend-b`      | TLS passthrough on `api.example.test:50051`          |
| `TLSRoute/backend-b-tls-route-b`                        | `backend-b`      | TLS passthrough on `tls.example.test:9443`           |
| `TLSRoute/backend-b-tls-route-d`                        | `backend-b`      | TLS passthrough on `mtls-b.example.test:443`         |
| `pod/api`                                               | `backend-a`      | HTTP backend                                         |
| `pod/backend-mtls`                                      | `backend-b`      | mTLS backend with SANs for all passthrough hostnames |

## Gateway listeners

| Listener  | Protocol | Port    | Hostname              | TLS mode    |
| --------- | -------- | ------- | --------------------- | ----------- |
| `tls-a`   | TLS      | `50051` | `api.example.test`    | Passthrough |
| `tls-b`   | TLS      | `9443`  | `tls.example.test`    | Passthrough |
| `https-c` | HTTPS    | `443`   | `web.example.test`    | Termination |
| `tls-d`   | TLS      | `443`   | `mtls-b.example.test` | Passthrough |

## Routes

| Kind        | Name                      | Namespace   | Listener          | Backend             |
| ----------- | ------------------------- | ----------- | ----------------- | ------------------- |
| `HTTPRoute` | `backend-a-https-route-c` | `backend-a` | `https-c` (`443`) | `api:80`            |
| `TLSRoute`  | `backend-b-tls-route-a`   | `backend-b` | `tls-a` (`50051`) | `backend-mtls:9443` |
| `TLSRoute`  | `backend-b-tls-route-b`   | `backend-b` | `tls-b` (`9443`)  | `backend-mtls:9443` |
| `TLSRoute`  | `backend-b-tls-route-d`   | `backend-b` | `tls-d` (`443`)   | `backend-mtls:9443` |

## Verification

What `verify.sh` checks:

1. All backend pods and certificates reach Ready state.
2. The Gateway is Accepted and all four routes are Accepted with
   `ResolvedRefs=True`.
3. Each listener reports exactly one attached route.
4. `web.example.test:443` reaches the HTTP backend through HTTPS termination.
5. `api.example.test:50051`, `tls.example.test:9443`, and
   `mtls-b.example.test:443` each complete an mTLS handshake with the
   passthrough backend.

The four data-plane checks are important: on affected Cilium versions, the
malformed CiliumEnvoyConfig causes every listener on the Gateway to stop
serving even though Gateway and route status can still report success.

## Related scenarios

| Scenario                                                                                  | Difference                                    |
| ----------------------------------------------------------------------------------------- | --------------------------------------------- |
| [`https-tls-catch-all-multi-tls-ports`](../https-tls-catch-all-multi-tls-ports/README.md) | Multi-port TLS, but no shared HTTPS/TLS port  |
| [`https-tls-shared-port`](../https-tls-shared-port/README.md)                             | Shared HTTPS/TLS port, but only one TLS port  |
| [`tls-split-port`](../tls-split-port/README.md)                                           | Two split TLS ports without HTTPS termination |

## Run

```sh
mise run //scenarios/03-multi-listener/https-tls-shared-port-multi-tls-ports:start
```
