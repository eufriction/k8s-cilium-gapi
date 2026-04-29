# http-grpc-same-hostname — HTTPS + gRPC on same hostname, split ports (443 / 50051)

This scenario tests that a single Gateway can serve both `HTTPRoute`s and `GRPCRoute`s
when they share **the same hostname** (`api.example.test`) but use **different listeners on
different ports** — HTTPS on `443` and gRPCS on `50051`. The port is the sole protocol
discriminator.

Both listeners use a wildcard hostname (`*.example.test`) and the same TLS secret.
The routes narrow the hostname to `api.example.test` via their own `hostnames` field.

## Resources

| Resource                                    | Namespace        | Purpose                           |
| ------------------------------------------- | ---------------- | --------------------------------- |
| `pod/api`                                   | `backend-a`      | HTTP backend A                    |
| `pod/api`                                   | `backend-b`      | HTTP backend B (path `/b`)        |
| `pod/grpc-api`                              | `backend-a`      | gRPC backend A                    |
| `pod/grpc-api`                              | `backend-b`      | gRPC backend B                    |
| `Gateway/same-hostname-split-ports-gateway` | `gateway-system` | Shared Gateway (ports 443, 50051) |

### Gateway listeners

| Listener | Protocol | Port    | Hostname         |
| -------- | -------- | ------- | ---------------- |
| `https`  | HTTPS    | `443`   | `*.example.test` |
| `grpcs`  | HTTPS    | `50051` | `*.example.test` |

### Routes

| Kind        | Name                    | Namespace   | Listener        | Match                 |
| ----------- | ----------------------- | ----------- | --------------- | --------------------- |
| `HTTPRoute` | `backend-a-https-route` | `backend-a` | `https` (443)   | `api.example.test /`  |
| `HTTPRoute` | `backend-b-https-route` | `backend-b` | `https` (443)   | `api.example.test /b` |
| `GRPCRoute` | `backend-a-grpc-route`  | `backend-a` | `grpcs` (50051) | `api.example.test`    |
| `GRPCRoute` | `backend-b-grpc-route`  | `backend-b` | `grpcs` (50051) | `api.example.test`    |

## Verification

What `verify.sh` checks:

1. All pods, certificates, gateway, and routes reach Ready/Accepted status.
2. Listener status assertions — both `https` and `grpcs` listeners report correct `attachedRoutes` counts.
3. **HTTPS on port 443** — `curl` to `api.example.test:443/headers` returns successfully (backend-a).
4. **HTTPS on port 443, path /b** — `curl` to `api.example.test:443/b/headers` returns successfully (backend-b).
5. **gRPC distribution on port 50051** — sends multiple gRPC `UnaryCall` requests and verifies traffic is distributed across both `backend-a` and `backend-b` (neither receives zero requests).
6. **Negative: per-port listener isolation** — an HTTP `curl` to path `/b` on the gRPC port (`50051`) must return `404` or `415`, not `200`. A `200` indicates HTTPRoute path prefixes leaked from port 443 to port 50051.

## Related scenarios

| Scenario                                                                  | Description                                                     |
| ------------------------------------------------------------------------- | --------------------------------------------------------------- |
| [http-grpc-split-port](../../01-simple/http-grpc-split-port/README.md)    | HTTP + gRPC, same Gateway, **different** hostnames              |
| [http-grpc-shared-port](../../01-simple/http-grpc-shared-port/README.md)  | HTTP + gRPC on the **same** port 443                            |
| [kinds-split-port](../../02-listener-policy/kinds-split-port/README.md)   | HTTP + gRPC with explicit `allowedRoutes.kinds`, separate ports |
| [kinds-shared-port](../../02-listener-policy/kinds-shared-port/README.md) | HTTP + gRPC on the same port with `allowedRoutes.kinds`         |

## Run

```sh
mise run //scenarios/03-multi-port/http-grpc-same-hostname:start
```
