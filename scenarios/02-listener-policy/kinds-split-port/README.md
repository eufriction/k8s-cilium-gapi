# kinds-split-port — Per-listener `allowedRoutes.kinds` on separate ports

Tests that per-listener `allowedRoutes.kinds` restrictions work correctly when
each listener uses a **separate port**. The Gateway has two HTTPS listeners,
each restricted to a single route kind:

| Listener | Port  | Allowed Kind |
| -------- | ----- | ------------ |
| `https`  | 443   | `HTTPRoute`  |
| `grpcs`  | 50051 | `GRPCRoute`  |

This prevents cross-attachment (e.g. a GRPCRoute on the HTTPS listener).

It deploys:

- `backend-http` and `backend-grpc` into `backend-a`
- `backend-http` and `backend-grpc` into `backend-b`
- one shared Gateway in `gateway-system` with per-listener kind restrictions

## Resources

| Resource                         | Namespace      | Purpose                             |
| -------------------------------- | -------------- | ----------------------------------- |
| Gateway `allowed-routes-gateway` | gateway-system | Two listeners, one kind each        |
| HTTPRoute (×2)                   | backend-a / -b | HTTPS termination → go-httpbin      |
| GRPCRoute (×2)                   | backend-a / -b | gRPC TLS termination → backend-grpc |
| Certificate (self-signed)        | gateway-system | Shared TLS cert for both listeners  |
| Pod `api` (×2)                   | backend-a / -b | go-httpbin (HTTP backend)           |
| Pod `grpc-api` (×2)              | backend-a / -b | gRPC test service                   |

## Verification

What `verify.sh` checks:

1. All four routes (2 HTTPRoute, 2 GRPCRoute) are accepted by the gateway
2. Per-listener `attachedRoutes` and `supportedKinds` are correct (`https` → 2 HTTPRoute, `grpcs` → 2 GRPCRoute)
3. HTTPS traffic to `https-a.example.test` and `https-b.example.test` on port 443 succeeds
4. gRPC affinity: `grpc-a.example.test` always routes to `backend-a`, `grpc-b.example.test` always routes to `backend-b` (10 iterations each on port 50051)
5. Negative test: HTTP hostname returns 404 on the gRPC port (50051), confirming per-port listener isolation

## Run

```sh
mise run //scenarios/02-listener-policy/kinds-split-port:start
```

## See also

- [`01-simple/http-grpc-split-port`](../../01-simple/http-grpc-split-port/README.md) — same layout, no kind restrictions
- [`kinds-shared-port`](../kinds-shared-port/README.md) — shared port, both kinds on one listener
