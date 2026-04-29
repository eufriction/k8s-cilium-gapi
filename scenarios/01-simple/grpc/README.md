# grpc — Multi-namespace GRPCRoute with TLS termination

A single TLS-terminating Gateway on port 443 routes gRPC traffic to two
backend namespaces based on hostname. `grpc-a.example.test` routes to
`grpc-backend-a` and `grpc-b.example.test` routes to `grpc-backend-b`.
The Gateway terminates TLS using a self-signed cert-manager certificate;
backends receive plaintext gRPC on port 9000.

## Resources

| Resource                                               | Namespace      | Purpose                                   |
| ------------------------------------------------------ | -------------- | ----------------------------------------- |
| Gateway `grpc-multi-namespace-gateway`                 | gateway-system | TLS-terminating listener on port 443      |
| Certificate `grpc-multi-namespace-gateway-certificate` | gateway-system | Self-signed TLS cert for the gateway      |
| GRPCRoute `grpc-backend-a-route`                       | grpc-backend-a | Routes `grpc-a.example.test` to backend-a |
| GRPCRoute `grpc-backend-b-route`                       | grpc-backend-b | Routes `grpc-b.example.test` to backend-b |
| Pod `grpc-api`                                         | grpc-backend-a | gRPC test server (reports `serverId`)     |
| Pod `grpc-api`                                         | grpc-backend-b | gRPC test server (reports `serverId`)     |
| Pod `netshoot-client`                                  | grpc-client    | In-cluster debugging client               |

## Verification

What `verify.sh` checks:

1. All pods and the TLS certificate reach Ready state.
2. Gateway is Accepted.
3. Both GRPCRoutes are Accepted by the gateway.
4. Listener `grpcs` reports 2 attached routes.
5. 10 consecutive gRPC requests to `grpc-a.example.test:443` all route to `grpc-backend-a`.
6. 10 consecutive gRPC requests to `grpc-b.example.test:443` all route to `grpc-backend-b`.
7. GRPCRoute Accepted status message is correct for both routes.

## Run

```sh
mise run //scenarios/01-simple/grpc:start
```
