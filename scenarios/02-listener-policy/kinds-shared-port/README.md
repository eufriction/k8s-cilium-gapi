# kinds-shared-port — Single listener with multiple allowed route kinds

Tests whether a single HTTPS listener can declare multiple entries in
`allowedRoutes.kinds` (both `HTTPRoute` and `GRPCRoute`) and correctly
accept routes of each type. HTTPRoutes and GRPCRoutes share port 443,
differentiated by hostname.

## Resources

| Resource                                     | Namespace             | Purpose                                                            |
| -------------------------------------------- | --------------------- | ------------------------------------------------------------------ |
| Gateway `shared-port-allowed-routes-gateway` | gateway-system        | Single HTTPS listener on port 443, kinds: `[HTTPRoute, GRPCRoute]` |
| HTTPRoute (×2)                               | backend-a / backend-b | HTTPS termination → go-httpbin                                     |
| GRPCRoute (×2)                               | backend-a / backend-b | gRPC over TLS → backend-grpc                                       |
| Certificate (self-signed)                    | gateway-system        | Shared TLS cert                                                    |
| Pod `api` (×2)                               | backend-a / backend-b | go-httpbin (HTTP backend)                                          |
| Pod `grpc-api` (×2)                          | backend-a / backend-b | gRPC test service                                                  |

| Listener | Port | Allowed Kinds             |
| -------- | ---- | ------------------------- |
| `https`  | 443  | `HTTPRoute` + `GRPCRoute` |

## Verification

What `verify.sh` checks:

1. All four routes are accepted by the `https` listener (2 HTTPRoutes, 2 GRPCRoutes)
2. Listener status reports `attachedRoutes=4` with `supportedKinds: [GRPCRoute, HTTPRoute]`
3. gRPC hostname affinity — `backend-grpc.example.test` routes exclusively to backend-a (10/10 requests)
4. gRPC hostname affinity — `backend-grpc-b.example.test` routes exclusively to backend-b (10/10 requests)
5. HTTPS traffic to `backend.example.test` reaches backend-a
6. HTTPS traffic to `backend-b.example.test` reaches backend-b

## Related scenarios

- [`01-simple/http-grpc-shared-port`](../../01-simple/http-grpc-shared-port/README.md) — same layout, no kind restrictions (implicit defaults)
- [`kinds-split-port`](../kinds-split-port/README.md) — one kind per listener on separate ports

## Run

```sh
mise run //scenarios/02-listener-policy/kinds-shared-port:start
```
