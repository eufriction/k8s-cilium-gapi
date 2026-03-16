# Shared-Port HTTP + gRPC with Allowed Routes

> **⚠️ Known Broken** — Cilium does not support multiple `allowedRoutes.kinds` entries on a single listener. See [Known Issues](#known-issues) below.

This scenario combines the **single shared-port** layout of [`21-http-grpc-shared-port`](../21-http-grpc-shared-port/README.md) with **explicit `allowedRoutes.kinds`** restrictions on the Gateway listener.

The Gateway has a single HTTPS listener on port `443` that explicitly allows both `HTTPRoute` and `GRPCRoute`:

| Listener | Port | Allowed Kinds             |
| -------- | ---- | ------------------------- |
| `https`  | 443  | `HTTPRoute` + `GRPCRoute` |

It deploys:

- `backend-http` and `backend-grpc` into `backend-a`
- `backend-http` and `backend-grpc` into `backend-b`
- one `netshoot-client` pod in `client`
- one shared Gateway in `gateway-system` with a **single** HTTPS listener on port `443`

The Gateway exposes:

- `HTTPS` on `443` for two `HTTPRoute`s (`backend.example.test`, `backend-b.example.test`)
- `gRPC` on `443` for two `GRPCRoute`s (`backend-grpc.example.test`, `backend-grpc-b.example.test`)

## Purpose

Test whether Cilium's Gateway API implementation correctly handles a **single listener** with `allowedRoutes.kinds` listing **multiple route types**. This is the intersection of two features:

1. **Shared-port routing** (scenario 21) — HTTPRoute and GRPCRoute on the same listener/port, differentiated by hostname
2. **Kind-restricted allowed routes** (scenario 22) — explicit `allowedRoutes.kinds` declarations

Where scenario 22 tests per-listener kind isolation across **separate ports** (and works), this scenario tests whether a single listener can explicitly declare that it accepts **both** `HTTPRoute` and `GRPCRoute` simultaneously.

## Status

**Broken on Cilium 1.19.1.** Routes fail to attach when a single listener declares multiple `allowedRoutes.kinds` entries. Cilium only recognises the first kind in the list and rejects routes of any other kind with `NotAllowedByListeners`.

This is distinct from the scenario 22 bug ([cilium#42013](https://github.com/cilium/cilium/issues/42013)), which was about kind restrictions not being scoped per-listener. That bug is fixed. This bug is about Cilium not supporting **multiple kinds on the same listener** — a valid Gateway API configuration that Cilium silently mishandles.

### Comparison with working scenarios

| Scenario                                       | `allowedRoutes.kinds`                      | Result on 1.19.1 |
| ---------------------------------------------- | ------------------------------------------ | ---------------- |
| [21](../21-http-grpc-shared-port/README.md)    | None (implicit — accepts all kinds)        | ✅ Works         |
| [22](../22-http-grpc-allowed-routes/README.md) | One kind per listener, separate ports      | ✅ Works         |
| **23**                                         | **Two kinds on one listener, shared port** | **❌ Broken**    |

## Difference from Other Scenarios

| Scenario                                                                | Ports       | Listeners            | `allowedRoutes.kinds`          |
| ----------------------------------------------------------------------- | ----------- | -------------------- | ------------------------------ |
| [20-http-grpc](../20-http-grpc/README.md)                               | 443 + 50051 | 2 (one per protocol) | None (implicit)                |
| [21-http-grpc-shared-port](../21-http-grpc-shared-port/README.md)       | 443         | 1 (shared)           | None (implicit)                |
| [22-http-grpc-allowed-routes](../22-http-grpc-allowed-routes/README.md) | 443 + 50051 | 2 (one per protocol) | One kind per listener          |
| **23-http-grpc-shared-port-allowed-routes**                             | **443**     | **1 (shared)**       | **Both kinds on one listener** |

## Known Issues

| Issue                                          | Description                                                                                                                                                                                                                        | Status                   |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------ |
| Multiple `allowedRoutes.kinds` on one listener | Cilium only honours the first kind entry in `allowedRoutes.kinds`. When a listener lists both `HTTPRoute` and `GRPCRoute`, only `HTTPRoute` (the first entry) is accepted. `GRPCRoute`s are rejected with `NotAllowedByListeners`. | Open as of Cilium 1.19.1 |

**Root cause:** Cilium's Gateway API implementation does not iterate over all entries in the `allowedRoutes.kinds` list for a single listener. It appears to match only the first kind, causing any subsequent kinds to be treated as not allowed.

**Workaround:** Either omit `allowedRoutes.kinds` entirely (scenario 21 — the listener implicitly accepts all supported kinds) or use separate listeners on different ports with one kind each (scenario 22).

### Diagnostic commands

```sh
# Check which kinds the listener reports as supported
kubectl get gateway shared-port-allowed-routes-gateway -n gateway-system \
  -o jsonpath='{range .status.listeners[*]}listener={.name}  supportedKinds={.supportedKinds[*].kind}{"\n"}{end}'

# Check route acceptance status
kubectl get httproute -A -o jsonpath='{range .items[*]}{.metadata.name}: {.status.parents[0].conditions[?(@.type=="Accepted")].reason}{"\n"}{end}'
kubectl get grpcroute -A -o jsonpath='{range .items[*]}{.metadata.name}: {.status.parents[0].conditions[?(@.type=="Accepted")].reason}{"\n"}{end}'
```

## Apply

```sh
mise run scenario:23:start
mise run scenario:23:verify
```

`scenario:23:start` installs `cert-manager` first if it is not already present, then issues a self-signed certificate in `gateway-system`.

The `scenario:23:verify` task is expected to **fail** at the route attachment stage. It prints diagnostic output pointing to this known issue.

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

For the split-port variant with per-listener kind restrictions (works), see [`scenarios/22-http-grpc-allowed-routes`](../22-http-grpc-allowed-routes/README.md).
For the shared-port variant without kind restrictions (works), see [`scenarios/21-http-grpc-shared-port`](../21-http-grpc-shared-port/README.md).
