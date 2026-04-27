# Same-Hostname HTTPS + gRPC on Split Ports (443 / 50051)

> **Cilium bug:** [cilium/cilium#44877](https://github.com/cilium/cilium/issues/44877) — HTTPRoute and GRPCRoute with same hostname on different ports fails with `SSL_ERROR_SYSCALL`
>
> **Fix PR:** [cilium/cilium#44889](https://github.com/cilium/cilium/pull/44889) — emit per-port listeners for multi-port HTTPS

This scenario tests that a single Gateway can serve both `HTTPRoute`s and `GRPCRoute`s
when they share **the same hostname** (`api.example.test`) but use **different listeners on
different ports** — HTTPS on `443` and gRPCS on `50051`.

This is the key distinction from scenario 20, where HTTP and gRPC traffic used
_different_ hostnames (`https-a/b.example.test` vs `grpc-a/b.example.test`). Here both
protocols are reached via the same host, with the port acting as the sole
protocol discriminator.

## What is deployed

| Resource                                    | Namespace        | Purpose                    |
| ------------------------------------------- | ---------------- | -------------------------- |
| `pod/api`                                   | `backend-a`      | HTTP backend A             |
| `pod/api`                                   | `backend-b`      | HTTP backend B (path `/b`) |
| `pod/grpc-api`                              | `backend-a`      | gRPC backend A             |
| `pod/grpc-api`                              | `backend-b`      | gRPC backend B             |
| `Gateway/same-hostname-split-ports-gateway` | `gateway-system` | Shared Gateway             |

## Gateway listeners

| Listener | Protocol | Port    | Hostname         |
| -------- | -------- | ------- | ---------------- |
| `https`  | HTTPS    | `443`   | `*.example.test` |
| `grpcs`  | HTTPS    | `50051` | `*.example.test` |

Both listeners use a wildcard hostname. The routes narrow this to
`api.example.test` via their own `hostnames` field.

Both listeners share the same TLS secret and the same wildcard hostname.
The port alone distinguishes HTTP traffic from gRPC traffic.

## Routes

| Kind        | Name                    | Namespace   | Listener        | Match                 |
| ----------- | ----------------------- | ----------- | --------------- | --------------------- |
| `HTTPRoute` | `backend-a-https-route` | `backend-a` | `https` (443)   | `api.example.test /`  |
| `HTTPRoute` | `backend-b-https-route` | `backend-b` | `https` (443)   | `api.example.test /b` |
| `GRPCRoute` | `backend-a-grpc-route`  | `backend-a` | `grpcs` (50051) | `api.example.test`    |
| `GRPCRoute` | `backend-b-grpc-route`  | `backend-b` | `grpcs` (50051) | `api.example.test`    |

## Purpose

Validates that Cilium correctly handles the combination of:

1. Two listeners on the **same hostname** but **different ports**.
2. `HTTPRoute`s attached to the HTTPS listener on port `443`.
3. `GRPCRoute`s attached to the HTTPS listener on port `50051`.

## ⚠️ Known Issue — Cilium Bug ([#44877](https://github.com/cilium/cilium/issues/44877))

All HTTPS routes are bucketed under a single "secure" key, so listeners on
different ports (e.g. 443 and 50051) share one Envoy `RouteConfiguration`.
This causes Envoy to NACK the listener update and drop all HTTPS connections
with `SSL_ERROR_SYSCALL` / `wrong version number`.

The fix in [cilium/cilium#44889](https://github.com/cilium/cilium/pull/44889)
splits the key by numeric port (gated on `NeedsPerPortHTTPSListeners()`) so
single-port Gateways and Ingress are unchanged.

### Envoy config snapshots

Two full Envoy config dumps are checked in as point-in-time snapshots for
reference when debugging [#44877](https://github.com/cilium/cilium/issues/44877):

| File                                                                           | State                                                       | Description                                                                     |
| ------------------------------------------------------------------------------ | ----------------------------------------------------------- | ------------------------------------------------------------------------------- |
| [`cilium-envoy-config-dump.broken.yaml`](cilium-envoy-config-dump.broken.yaml) | Before fix                                                  | Single shared `RouteConfiguration` for all HTTPS ports — Envoy NACKs the update |
| [`cilium-envoy-config-dump.fixed.yaml`](cilium-envoy-config-dump.fixed.yaml)   | After [#44889](https://github.com/cilium/cilium/pull/44889) | Per-port `RouteConfiguration` — Envoy accepts and routes correctly              |

### Why scenario 20 is unaffected

Scenario 20 uses _different_ hostnames per protocol (`https-a/b.example.test` vs
`grpc-a/b.example.test`). The routes land in _different_ virtual hosts, so the port
collision never occurs.

## Apply

```sh
mise run scenario:24:start
mise run scenario:24:verify
```

`scenario:24:start` installs `cert-manager` first if it is not already present,
then issues a self-signed wildcard certificate in `gateway-system`.

## Manual checks

HTTPS (port 443):

```sh
# backend-a — root path
curl -kfsS --resolve "api.example.test:443:127.0.0.1" \
  https://api.example.test/headers

# backend-b — /b prefix
curl -kfsS --resolve "api.example.test:443:127.0.0.1" \
  https://api.example.test/b/headers
```

gRPC (port 50051):

```sh
# backend-a
grpcurl -insecure \
  -authority api.example.test \
  -proto apps/backend-grpc/proto/grpc/testing/testservice.proto \
  -d '{"response_size":32,"fill_server_id":true}' \
  localhost:50051 \
  grpc.testing.TestService/UnaryCall

# backend-b
grpcurl -insecure \
  -authority api.example.test \
  -proto apps/backend-grpc/proto/grpc/testing/testservice.proto \
  -d '{"response_size":32,"fill_server_id":true}' \
  localhost:50051 \
  grpc.testing.TestService/UnaryCall
```

> **Note:** Both gRPC backends share the same hostname and expose the same
> `TestService/UnaryCall` method. Requests are load-balanced across
> `backend-a` and `backend-b` by the Gateway. Inspect `server_id` in the
> response to confirm which backend replied.

## Related scenarios

| Scenario                                                                  | Description                                                      |
| ------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| [http-grpc-split-port](../../01-simple/http-grpc-split-port/README.md)    | HTTP + gRPC, same Gateway, **different** hostnames               |
| [http-grpc-shared-port](../../01-simple/http-grpc-shared-port/README.md)  | HTTP + gRPC on the **same** port 443, no `allowedRoutes.kinds`   |
| [kinds-split-port](../../02-listener-policy/kinds-split-port/README.md)   | HTTP + gRPC with explicit `allowedRoutes.kinds`, separate ports  |
| [kinds-shared-port](../../02-listener-policy/kinds-shared-port/README.md) | HTTP + gRPC, same port, `allowedRoutes.kinds` — known Cilium bug |
