# 20 · HTTPS + gRPC split-port Gateway

One Gateway serving HTTPS (443) and gRPC-over-TLS (50051) across two backend namespaces. Combines scenarios 01 and 02.

## Layout

| Component                    | Namespace                |
| ---------------------------- | ------------------------ |
| HTTPRoute × 2, GRPCRoute × 2 | `backend-a`, `backend-b` |
| Gateway + TLS cert           | `gateway-system`         |
| netshoot client              | `client`                 |

## Run

```sh
mise run //scenarios/20-http-grpc:start        # deploy + verify
DELETE=1 mise run //scenarios/20-http-grpc:start  # deploy + verify + teardown
```

Cert-manager is installed automatically if absent.

## Known issue — duplicate `serverNames` NACK (≥ 1.19.2)

Commit [`9ee2db2b32`](https://github.com/cilium/cilium/commit/9ee2db2b32) removed `slices.SortedUnique()` from `toFilterChainMatch()`. When ports 443 and 50051 share a hostname (`*.example.test`) and TLS secret, the operator produces duplicate `serverNames` entries. Envoy rejects this permanently:

```
multiple filter chains with overlapping matching rules are defined
```

Works on **1.19.1** (dedup still present). Fixed on `fix/allowed-routes` branch (restores `SortedUnique`).

**Refs:** [#31122](https://github.com/cilium/cilium/issues/31122), [#37609](https://github.com/cilium/cilium/issues/37609). Also affects scenarios [22](../22-http-grpc-allowed-routes/README.md) and [24](../24-http-grpc-same-hostname-split-ports/README.md).

## Manual check

```sh
# HTTPS
curl -k --resolve "https-a.example.test:443:127.0.0.1" https://https-a.example.test/headers
curl -k --resolve "https-b.example.test:443:127.0.0.1" https://https-b.example.test/headers

# gRPC
grpcurl -insecure -authority grpc-a.example.test \
  -d '{"response_size":32,"fill_server_id":true}' \
  localhost:50051 grpc.testing.TestService/UnaryCall
```
