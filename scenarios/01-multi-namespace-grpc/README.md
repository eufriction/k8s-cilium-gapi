# Host-Network Multi-Namespace TLS GRPCRoute

This scenario deploys the reusable `backend-grpc` app base twice, in `grpc-backend-a` and `grpc-backend-b`, plus one `netshoot-client` pod in `grpc-client` and a single TLS-terminating Gateway in `gateway-system`.

The Gateway listener terminates TLS on port `443`, which is exposed on your machine as `localhost:443` through kind `extraPortMappings`.

## Purpose

This is the fixed-port host-network variant of the gRPC setup for multi-namespace routing. It gives you one Gateway with two `GRPCRoute` objects, each selecting a different backend namespace by hostname.

## Apply

```sh
mise run scenario:01:start
mise run scenario:01:verify
```

`scenario:01:start` installs `cert-manager` first if it is not already present, then issues a self-signed certificate in `gateway-system`.

## Manual Check

Use the checked-in proto descriptor instead of relying on reflection:

```sh
grpcurl -insecure \
  -authority grpc-a.example.test \
  -proto apps/backend-grpc/proto/grpc/testing/testservice.proto \
  -d '{"response_size":32,"fill_server_id":true}' \
  localhost:443 \
  grpc.testing.TestService/UnaryCall

grpcurl -insecure \
  -authority grpc-b.example.test \
  -proto apps/backend-grpc/proto/grpc/testing/testservice.proto \
  -d '{"response_size":32,"fill_server_id":true}' \
  localhost:443 \
  grpc.testing.TestService/UnaryCall
```

If you need direct backend checks from inside the cluster:

```sh
kubectl exec -n grpc-client pod/netshoot-client -- \
  grpcurl -plaintext \
  -d '{"response_size":32,"fill_server_id":true}' \
  grpc-api.grpc-backend-a.svc.cluster.local:9000 \
  grpc.testing.TestService/UnaryCall

kubectl exec -n grpc-client pod/netshoot-client -- \
  grpcurl -plaintext \
  -d '{"response_size":32,"fill_server_id":true}' \
  grpc-api.grpc-backend-b.svc.cluster.local:9000 \
  grpc.testing.TestService/UnaryCall
```
