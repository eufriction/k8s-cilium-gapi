# Host-Network Multi-Namespace HTTPS + gRPC

This scenario combines the existing multi-namespace HTTPS and gRPC patterns into one Gateway.

It deploys:

- `backend-http` and `backend-grpc` into `backend-a`
- `backend-http` and `backend-grpc` into `backend-b`
- one `netshoot-client` pod in `client`
- one shared Gateway in `gateway-system`

The Gateway exposes:

- `HTTPS` on `443` for two `HTTPRoute`s
- `gRPC` with TLS termination on `50051` for two `GRPCRoute`s

## Purpose

This is the first multi-protocol scenario in the `20+` series. It is the direct combination of scenario 01 and scenario 02, keeping the same multi-namespace fan-out pattern but serving both HTTPS and gRPC from one Gateway.

## Apply

```sh
mise run scenario:20:start
mise run scenario:20:verify
```

`scenario:20:start` installs `cert-manager` first if it is not already present, then issues a self-signed certificate in `gateway-system`.

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

For the single-protocol gRPC variant, see [`scenarios/02-grpc`](../02-grpc/README.md).
