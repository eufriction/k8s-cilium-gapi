# Scenario 22 — HTTPS + gRPC with per-listener `allowedRoutes.kinds`

Same split-port layout as [scenario 20](../../01-simple/http-grpc-split-port/README.md) but each
Gateway listener restricts to a **single** route kind:

| Listener | Port  | Allowed Kind |
| -------- | ----- | ------------ |
| `https`  | 443   | `HTTPRoute`  |
| `grpcs`  | 50051 | `GRPCRoute`  |

This prevents cross-attachment (e.g. a GRPCRoute on the HTTPS listener).

## Resources

| Resource                         | Namespace      | Purpose                             |
| -------------------------------- | -------------- | ----------------------------------- |
| Gateway `allowed-routes-gateway` | gateway-system | Two listeners, one kind each        |
| HTTPRoute (×2)                   | backend-a / -b | HTTPS termination → go-httpbin      |
| GRPCRoute (×2)                   | backend-a / -b | gRPC TLS termination → backend-grpc |
| Certificate (self-signed)        | gateway-system | Shared TLS cert for both listeners  |
| Pod `api` (×2)                   | backend-a / -b | go-httpbin (HTTP backend)           |
| Pod `backend-grpc` (×2)          | backend-a / -b | gRPC test service                   |

## Status

⚠️ **Broken on all tested versions** — [cilium#45559](https://github.com/cilium/cilium/issues/45559)

Gateway status looks correct (each listener reports the right `supportedKinds`),
but the CiliumEnvoyConfig collapses both ports into one Envoy listener via
`additionalAddresses` and drops all HTTPRoute backends. HTTPS returns 404 even
though HTTPRoutes show `Accepted: True`.

Distinct from [#44824](https://github.com/cilium/cilium/issues/44824)
(shared-port `allowedRoutes.kinds`, fixed ≥1.19.3) — the separate-port variant
fails at the listener-merging level. See `cec-dump.broken.yaml` for evidence.

## Run

```sh
mise run //scenarios/02-listener-policy/kinds-split-port:start
```

## See also

- [Scenario 20](../../01-simple/http-grpc-split-port/README.md) — same layout, no kind restrictions (passes)
- [Scenario 23](../kinds-shared-port/README.md) — shared port, both kinds on one listener
