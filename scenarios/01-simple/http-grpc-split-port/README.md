# http-grpc-split-port — HTTPS + gRPC on separate ports

One Gateway serving HTTPS (port 443) and gRPC-over-TLS (port 50051) across two
backend namespaces. Each protocol gets its own listener and port, with HTTPRoutes
on 443 and GRPCRoutes on 50051. This validates that Cilium correctly isolates
routes to their respective listeners when multiple TLS ports share a hostname
wildcard and TLS secret.

## Resources

| Resource                                     | Namespace            | Purpose                                           |
| -------------------------------------------- | -------------------- | ------------------------------------------------- |
| Gateway `https-grpc-multi-namespace-gateway` | gateway-system       | Two TLS listeners: `https` (443), `grpcs` (50051) |
| Certificate `https-grpc-gateway-certificate` | gateway-system       | Wildcard TLS cert for both listeners              |
| HTTPRoute `backend-a-https-route`            | backend-a            | HTTPS → go-httpbin (backend-a)                    |
| HTTPRoute `backend-b-https-route`            | backend-b            | HTTPS → go-httpbin (backend-b)                    |
| GRPCRoute `backend-a-grpc-route`             | backend-a            | gRPC → backend-grpc (backend-a)                   |
| GRPCRoute `backend-b-grpc-route`             | backend-b            | gRPC → backend-grpc (backend-b)                   |
| Pod `api`                                    | backend-a, backend-b | go-httpbin HTTP backends                          |
| Pod `grpc-api`                               | backend-a, backend-b | gRPC test-service backends                        |
| Pod `netshoot-client`                        | client               | In-cluster debugging                              |

## Verification

What `verify.sh` checks:

1. All pods and the TLS certificate reach Ready state.
2. Gateway is Accepted.
3. All four routes (2 HTTPRoute + 2 GRPCRoute) are Accepted.
4. Listener `https` reports 2 attached routes; listener `grpcs` reports 2 attached routes.
5. HTTPS backend-a responds on port 443 (`https-a.example.test`).
6. HTTPS backend-b responds on port 443 (`https-b.example.test`).
7. gRPC affinity: `grpc-a.example.test:50051` routes all 10 requests to backend-a.
8. gRPC affinity: `grpc-b.example.test:50051` routes all 10 requests to backend-b.
9. Per-port listener isolation: HTTP hostname returns 404 on gRPC port 50051 (routes must not leak across ports).

## Related scenarios

- [`http-grpc-shared-port`](../http-grpc-shared-port/README.md) — same protocols collapsed onto a single port.

## Run

```sh
mise run //scenarios/01-simple/http-grpc-split-port:start
```
