# http-grpc-shared-port — HTTPRoute and GRPCRoute on a single HTTPS listener

This scenario serves HTTPRoute and GRPCRoute traffic on a **single HTTPS listener
on port 443** with distinct hostnames. The Gateway API spec allows this — routes
with non-overlapping hostnames on the same listener are not conflicted.

It deploys `backend-http` and `backend-grpc` into both `backend-a` and `backend-b`,
plus a shared Gateway in `gateway-system` with one HTTPS listener. The goal is to
validate that Cilium can handle mixed HTTP/1.1 and gRPC (HTTP/2) traffic on the
same HTTPS listener.

Compared to [`http-grpc-split-port`](../http-grpc-split-port/README.md) (which uses
separate ports 443 and 50051), this scenario deliberately collapses everything onto
**one port**.

## Resources

| Resource                                      | Namespace            | Purpose                                          |
| --------------------------------------------- | -------------------- | ------------------------------------------------ |
| Gateway `shared-port-gateway`                 | gateway-system       | Single HTTPS listener on port 443                |
| Certificate `shared-port-gateway-certificate` | gateway-system       | TLS cert for the gateway                         |
| HTTPRoute `backend-a-https-route`             | backend-a            | HTTPS → backend-a (`backend.example.test`)       |
| HTTPRoute `backend-b-https-route`             | backend-b            | HTTPS → backend-b (`backend-b.example.test`)     |
| GRPCRoute `backend-a-grpc-route`              | backend-a            | gRPC → backend-a (`backend-grpc.example.test`)   |
| GRPCRoute `backend-b-grpc-route`              | backend-b            | gRPC → backend-b (`backend-grpc-b.example.test`) |
| Pod `api`                                     | backend-a, backend-b | go-httpbin HTTP backends                         |
| Pod `grpc-api`                                | backend-a, backend-b | gRPC test service backends                       |

## Verification

What `verify.sh` checks:

1. All pods and the TLS certificate are ready.
2. Gateway `shared-port-gateway` is accepted.
3. All four routes (2 HTTPRoute, 2 GRPCRoute) are accepted.
4. Listener `https` reports 4 attached routes.
5. `backend-grpc.example.test` routes all gRPC requests to `backend-a` (10 iterations).
6. `backend-grpc-b.example.test` routes all gRPC requests to `backend-b` (10 iterations).
7. HTTPS `backend.example.test` returns a successful response on port 443.
8. HTTPS `backend-b.example.test` returns a successful response on port 443.

## Run

```sh
mise run //scenarios/01-simple/http-grpc-shared-port:start
```

## See also

- [`http-grpc-split-port`](../http-grpc-split-port/README.md) — separate ports for HTTP and gRPC
- [`kinds-shared-port`](../../02-listener-policy/kinds-shared-port/README.md) — shared-port variant with explicit `allowedRoutes.kinds`
