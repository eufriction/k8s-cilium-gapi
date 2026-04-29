# kinds-multi-listener — Per-listener kind restrictions across four protocols

Tests that per-listener `allowedRoutes.kinds` restrictions are evaluated
independently when multiple listeners share port 443 with different hostnames
and protocols. A fourth listener on port 80 uses implicit kind defaults (no
explicit `allowedRoutes.kinds`).

## Listeners

| Listener          | Protocol | Port | Hostname              | Allowed Kinds            |
| ----------------- | -------- | ---- | --------------------- | ------------------------ |
| `http`            | HTTP     | 80   | _(none — catch-all)_  | _(implicit — HTTPRoute)_ |
| `https`           | HTTPS    | 443  | `*.http.example.test` | explicit: `HTTPRoute`    |
| `grpcs`           | HTTPS    | 443  | `*.grpc.example.test` | explicit: `GRPCRoute`    |
| `tls-passthrough` | TLS      | 443  | `*.tls.example.test`  | explicit: `TLSRoute`     |

## Resources

| Resource          | Kind      | Namespace      | Listener          | Purpose                |
| ----------------- | --------- | -------------- | ----------------- | ---------------------- |
| `http-redirect`   | HTTPRoute | gateway-system | `http`            | 301 redirect → HTTPS   |
| `backend-a-https` | HTTPRoute | backend-a      | `https`           | HTTPS termination      |
| `backend-b-https` | HTTPRoute | backend-b      | `https`           | HTTPS termination      |
| `backend-a-grpc`  | GRPCRoute | backend-a      | `grpcs`           | gRPC over TLS          |
| `backend-b-grpc`  | GRPCRoute | backend-b      | `grpcs`           | gRPC over TLS          |
| `backend-a-tls`   | TLSRoute  | backend-a      | `tls-passthrough` | TLS passthrough (mTLS) |

Backends deployed:

- `backend-http` and `backend-grpc` into `backend-a`
- `backend-http` and `backend-grpc` into `backend-b`
- `backend-mtls` into `backend-a` (TLS-terminating Envoy for passthrough)
- One shared Gateway in `gateway-system`

## Verification

What `verify.sh` checks:

1. All six routes are Accepted by their targeted listener (HTTPRoute redirect, HTTPRoute ×2, GRPCRoute ×2, TLSRoute ×1)
2. Per-listener `attachedRoutes` and `supportedKinds` are correct (`http`→1 HTTPRoute/GRPCRoute, `https`→2 HTTPRoute, `grpcs`→2 GRPCRoute, `tls-passthrough`→1 TLSRoute)
3. HTTPS termination — both `http-a.http.example.test` and `http-b.http.example.test` respond on port 443
4. gRPC affinity — `grpc-a.grpc.example.test` routes exclusively to backend-a, `grpc-b.grpc.example.test` routes exclusively to backend-b (10 iterations each)
5. HTTP redirect — port 80 returns 301
6. TLS passthrough — `tls-a.tls.example.test` completes mTLS on port 443

## Related scenarios

- [`kinds-split-port`](../kinds-split-port/README.md) — per-listener kind restrictions on separate ports
- [`kinds-shared-port`](../kinds-shared-port/README.md) — both kinds on one listener, shared port
- [`mixed-protocol`](../mixed-protocol/README.md) — same protocol mix without explicit kind restrictions

## Run

```sh
mise run //scenarios/02-listener-policy/kinds-multi-listener:start
```
