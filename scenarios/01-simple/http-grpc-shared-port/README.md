# Shared-Port HTTP + gRPC

This scenario serves HTTPRoute and GRPCRoute traffic on a **single HTTPS listener on port `443`** with distinct hostnames. The Gateway API spec allows this — routes with non-overlapping hostnames on the same listener are not conflicted.

It deploys:

- `backend-http` and `backend-grpc` into `backend-a`
- `backend-http` and `backend-grpc` into `backend-b`
- one `netshoot-client` pod in `client`
- one shared Gateway in `gateway-system` with a **single** HTTPS listener on port `443`

The Gateway exposes:

- `HTTPS` on `443` for two `HTTPRoute`s (`backend.example.test`, `backend-b.example.test`)
- `gRPC` on `443` for two `GRPCRoute`s (`backend-grpc.example.test`, `backend-grpc-b.example.test`)

## Purpose

Compared to [`http-grpc-split-port`](../http-grpc-split-port/README.md) (which uses separate ports `443` and `50051`), this scenario deliberately collapses everything onto **one port** to validate that Cilium can handle mixed HTTP/1.1 and gRPC (HTTP/2) traffic on the same HTTPS listener.

## Status

Verified working on **Cilium 1.19.1**. Both HTTPRoute (HTTP/1.1) and GRPCRoute (HTTP/2) traffic are correctly routed through a single shared HTTPS listener.

### Historical context

[cilium/cilium#43679](https://github.com/cilium/cilium/issues/43679) reported that Cilium's Envoy translator forces HTTP/2 on the upstream cluster when a GRPCRoute is present on the same listener, breaking HTTP/1.1 HTTPRoute backends. This scenario was originally created to surface that limitation. As of Cilium 1.19.1, the issue does not reproduce — both protocols work correctly on a shared port.

## Apply

```sh
mise run scenario:21:start
mise run scenario:21:verify
```

`scenario:21:start` installs `cert-manager` first if it is not already present, then issues a self-signed certificate in `gateway-system`.

## Manual Check

HTTPS:

```sh
curl -k --resolve "backend.example.test:443:127.0.0.1" https://backend.example.test/headers
curl -k --resolve "backend-b.example.test:443:127.0.0.1" https://backend-b.example.test/headers
```

gRPC:

```sh
grpcurl -insecure \
  -authority backend-grpc.example.test \
  -proto apps/backend-grpc/proto/grpc/testing/testservice.proto \
  -d '{"response_size":32,"fill_server_id":true}' \
  localhost:443 \
  grpc.testing.TestService/UnaryCall

grpcurl -insecure \
  -authority backend-grpc-b.example.test \
  -proto apps/backend-grpc/proto/grpc/testing/testservice.proto \
  -d '{"response_size":32,"fill_server_id":true}' \
  localhost:443 \
  grpc.testing.TestService/UnaryCall
```

For the split-port variant, see [`scenarios/01-simple/http-grpc-split-port`](../http-grpc-split-port/README.md).
For the shared-port variant with explicit `allowedRoutes.kinds`, see [`scenarios/02-listener-policy/kinds-shared-port`](../../02-listener-policy/kinds-shared-port/README.md).
