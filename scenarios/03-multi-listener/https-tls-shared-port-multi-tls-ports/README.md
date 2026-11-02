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
do not have a Gateway API protocol conflict.

## Naming

All three TLS-passthrough hostnames resolve to the same `backend-mtls` pod in
`backend-b`. The port is the only thing that distinguishes them, so listeners,
hostnames, and routes are all named after it: listener `tls-9443` serves
`mtls-9443.example.test` through `backend-b-mtls-9443-route`. The one server
certificate carries all three names.

`web.example.test` is the odd one out by design: it is the HTTP backend in
`backend-a` reached through HTTPS termination, and it shares port `443` with
`mtls-443.example.test`. That collision is the subject of the test.

## Resources

| Resource                                                | Namespace        | Purpose                                              |
| ------------------------------------------------------- | ---------------- | ---------------------------------------------------- |
| `Gateway/https-tls-shared-port-multi-tls-ports-gateway` | `gateway-system` | Two split TLS ports plus a shared HTTPS/TLS port     |
| `HTTPRoute/backend-a-web-route`                         | `backend-a`      | HTTPS termination on `web.example.test:443`          |
| `TLSRoute/backend-b-mtls-50051-route`                   | `backend-b`      | TLS passthrough on `mtls-50051.example.test:50051`   |
| `TLSRoute/backend-b-mtls-9443-route`                    | `backend-b`      | TLS passthrough on `mtls-9443.example.test:9443`     |
| `TLSRoute/backend-b-mtls-443-route`                     | `backend-b`      | TLS passthrough on `mtls-443.example.test:443`       |
| `pod/api`                                               | `backend-a`      | HTTP backend                                         |
| `pod/backend-mtls`                                      | `backend-b`      | mTLS backend with SANs for all passthrough hostnames |

## Gateway listeners

| Listener    | Protocol | Port    | Hostname                  | TLS mode    |
| ----------- | -------- | ------- | ------------------------- | ----------- |
| `tls-50051` | TLS      | `50051` | `mtls-50051.example.test` | Passthrough |
| `tls-9443`  | TLS      | `9443`  | `mtls-9443.example.test`  | Passthrough |
| `https-443` | HTTPS    | `443`   | `web.example.test`        | Termination |
| `tls-443`   | TLS      | `443`   | `mtls-443.example.test`   | Passthrough |

## Routes

| Kind        | Name                         | Namespace   | Listener              | Backend             |
| ----------- | ---------------------------- | ----------- | --------------------- | ------------------- |
| `HTTPRoute` | `backend-a-web-route`        | `backend-a` | `https-443` (`443`)   | `api:80`            |
| `TLSRoute`  | `backend-b-mtls-50051-route` | `backend-b` | `tls-50051` (`50051`) | `backend-mtls:9443` |
| `TLSRoute`  | `backend-b-mtls-9443-route`  | `backend-b` | `tls-9443` (`9443`)   | `backend-mtls:9443` |
| `TLSRoute`  | `backend-b-mtls-443-route`   | `backend-b` | `tls-443` (`443`)     | `backend-mtls:9443` |

## Verification

What `verify.sh` checks:

1. All backend pods and certificates reach Ready state.
2. The Gateway is Accepted and all four routes are Accepted with
   `ResolvedRefs=True`.
3. Each listener reports exactly one attached route.
4. `web.example.test:443` reaches the HTTP backend through HTTPS termination.
5. `mtls-50051.example.test:50051`, `mtls-9443.example.test:9443`, and
   `mtls-443.example.test:443` each complete an mTLS handshake with the
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
