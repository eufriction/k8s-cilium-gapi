# Self-Signed TLS Foundation

The repo keeps `cert-manager` separate from `mise run cluster:start`.

That is intentional:

- scenario `00` does not need certificate automation
- TLS controllers and CRDs should only be installed when a TLS scenario needs them
- later scenarios can make `cert-manager:install` an explicit prerequisite instead of hiding that dependency

## Install and Verify

```sh
mise run cert-manager:install
mise run cert-manager:verify
```

`mise run cert-manager:delete` removes the controller when you are done with TLS scenarios.

## Repo Pattern

Use namespaced resources rather than a shared `ClusterIssuer`:

1. Create a scenario-scoped `Issuer` in the namespace that should own certificate issuance.
2. Create a `Certificate` in the same namespace as the workload that consumes the resulting secret.
3. Reference that secret from the Gateway or mount it into the backend app.

That keeps each scenario self-contained and avoids cross-scenario secret coupling.

## TLS Termination

For Gateway-managed termination:

1. Put the `Certificate` in `gateway-system`.
2. Let `cert-manager` write a secret in `gateway-system`.
3. Reference that secret from the Gateway listener with `tls.mode: Terminate`.

## TLS Passthrough

For backend-managed TLS:

1. Put the `Certificate` in the backend app namespace.
2. Mount the generated secret into the backend pod.
3. Use a `TLSRoute` and let the backend terminate TLS itself.

## Insecure Local Testing

Use insecure client flags for local development with self-signed certificates.

HTTPS:

```sh
curl -k --resolve app.example.test:<https-port>:127.0.0.1 \
  https://app.example.test:<https-port>/headers
```

gRPC over TLS:

```sh
grpcurl -insecure \
  -authority grpc.example.test \
  -proto apps/backend-grpc/proto/grpc/testing/testservice.proto \
  -d '{"response_size":32,"fill_server_id":true}' \
  127.0.0.1:<grpc-tls-port> \
  grpc.testing.TestService/UnaryCall
```

TLS handshake inspection:

```sh
openssl s_client -connect 127.0.0.1:<tls-port> -servername app.example.test
```

Replace the placeholder ports with the ports exposed by the scenario you are testing.
