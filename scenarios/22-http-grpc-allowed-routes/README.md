# Allowed-Routes Kind-Restricted HTTPS + gRPC

This scenario mirrors the split-port layout of [`20-http-grpc`](../20-http-grpc/README.md) but adds **explicit `allowedRoutes.kinds`** restrictions on each Gateway listener:

| Listener | Port  | Allowed Kind |
| -------- | ----- | ------------ |
| `https`  | 443   | `HTTPRoute`  |
| `grpcs`  | 50051 | `GRPCRoute`  |

By restricting each listener to a single route kind the Gateway becomes more explicit about what it accepts. This is the recommended practice when a Gateway serves multiple protocols, because it prevents accidental cross-attachment (e.g. a GRPCRoute attaching to the HTTPS listener or vice-versa).

It deploys:

- `backend-http` and `backend-grpc` into `backend-a`
- `backend-http` and `backend-grpc` into `backend-b`
- one `netshoot-client` pod in `client`
- one shared Gateway in `gateway-system`

The Gateway exposes:

- `HTTPS` on `443` for two `HTTPRoute`s (kind-restricted)
- `gRPC` with TLS termination on `50051` for two `GRPCRoute`s (kind-restricted)

## Purpose

Validate that Cilium's Gateway API implementation honours `allowedRoutes.kinds` correctly when each listener restricts to a **single** route kind. When a listener specifies `kinds: [{kind: HTTPRoute}]`, only HTTPRoutes should be accepted; likewise `kinds: [{kind: GRPCRoute}]` should accept only GRPCRoutes.

## Status

Verified working on **Cilium 1.19.1**. Each listener correctly accepts only the declared route kind, and both HTTPS and gRPC traffic are routed as expected.

## Difference from Scenario 20

Scenario 20 uses the same two-port split but relies only on `allowedRoutes.namespaces.from: All` without any kind restriction. This scenario adds the `kinds` field to exercise that part of the Gateway API spec.

## Historical Context

This scenario was originally expected to fail due to bugs in `allowedRoutes.kinds` handling:

| Issue                                                         | Title                                         | Affected Versions | Status                                                                    |
| ------------------------------------------------------------- | --------------------------------------------- | ----------------- | ------------------------------------------------------------------------- |
| [cilium#42013](https://github.com/cilium/cilium/issues/42013) | `allowedRoutes.kinds` not scoped per-listener | ≤ 1.18.x          | Fixed in 1.19.0 via [#43802](https://github.com/cilium/cilium/pull/43802) |
| [cilium#39021](https://github.com/cilium/cilium/issues/39021) | GRPCRoute not in listener Supported Kinds     | ≤ 1.17.x          | Fixed in 1.19.0 via [#41232](https://github.com/cilium/cilium/pull/41232) |
| [cilium#40922](https://github.com/cilium/cilium/issues/40922) | GRPCRoute unable to attach                    | ≤ 1.16.x          | Same root cause as #39021                                                 |
| [cilium#34288](https://github.com/cilium/cilium/issues/34288) | Multiple `allowedRoutes` selectors broken     | ≤ 1.16.0          | Fixed                                                                     |

The root cause was that Cilium evaluated kind restrictions **globally** across all listeners instead of per-listener. The fix ([#43802](https://github.com/cilium/cilium/pull/43802)) shipped in **v1.19.0** and this scenario now passes cleanly.

## Apply

```sh
mise run scenario:22:start
mise run scenario:22:verify
```

`scenario:22:start` installs `cert-manager` first if it is not already present, then issues a self-signed certificate in `gateway-system`.

## Manual Check

HTTPS:

```sh
curl -k --resolve "https-a.example.test:443:127.0.0.1" https://https-a.example.test/headers
curl -k --resolve "https-b.example.test:443:127.0.0.1" https://https-b.example.test/headers
```

gRPC:

```sh
grpcurl -insecure \
  -authority grpc-a.example.test \
  -proto apps/backend-grpc/proto/grpc/testing/testservice.proto \
  -d '{"response_size":32,"fill_server_id":true}' \
  localhost:50051 \
  grpc.testing.TestService/UnaryCall

grpcurl -insecure \
  -authority grpc-b.example.test \
  -proto apps/backend-grpc/proto/grpc/testing/testservice.proto \
  -d '{"response_size":32,"fill_server_id":true}' \
  localhost:50051 \
  grpc.testing.TestService/UnaryCall
```

For the variant without kind restrictions, see [`scenarios/20-http-grpc`](../20-http-grpc/README.md).
For the shared-port variant with multiple kinds on one listener, see [`scenarios/23-http-grpc-shared-port-allowed-routes`](../23-http-grpc-shared-port-allowed-routes/README.md).
