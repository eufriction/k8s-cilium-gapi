# Allowed-Routes Kind-Restricted — Mixed Protocols, Same Port

This scenario tests that Cilium honours per-listener `allowedRoutes.kinds`
restrictions when multiple listeners share **port 443** with **different
hostnames** and a mix of protocols. It also includes an HTTP/80 listener
with no explicit kind restrictions (implicit defaults) and an HTTP→HTTPS
redirect route.

| Listener          | Protocol | Port | Hostname              | Allowed Kinds            |
| ----------------- | -------- | ---- | --------------------- | ------------------------ |
| `http`            | HTTP     | 80   | _(none — catch-all)_  | _(implicit — HTTPRoute)_ |
| `https`           | HTTPS    | 443  | `*.http.example.test` | explicit: `HTTPRoute`    |
| `grpcs`           | HTTPS    | 443  | `*.grpc.example.test` | explicit: `GRPCRoute`    |
| `tls-passthrough` | TLS      | 443  | `*.tls.example.test`  | explicit: `TLSRoute`     |

It deploys:

- `backend-http` and `backend-grpc` into `backend-a`
- `backend-http` and `backend-grpc` into `backend-b`
- `backend-mtls` into `backend-a` (TLS-terminating Envoy for passthrough)
- one `netshoot-client` pod in `client`
- one shared Gateway in `gateway-system`

Routes attached to the Gateway:

| Route             | Kind      | Namespace      | Listener          | Purpose                |
| ----------------- | --------- | -------------- | ----------------- | ---------------------- |
| `http-redirect`   | HTTPRoute | gateway-system | `http`            | 301 redirect → HTTPS   |
| `backend-a-https` | HTTPRoute | backend-a      | `https`           | HTTPS termination      |
| `backend-b-https` | HTTPRoute | backend-b      | `https`           | HTTPS termination      |
| `backend-a-grpc`  | GRPCRoute | backend-a      | `grpcs`           | gRPC over TLS          |
| `backend-b-grpc`  | GRPCRoute | backend-b      | `grpcs`           | gRPC over TLS          |
| `backend-a-tls`   | TLSRoute  | backend-a      | `tls-passthrough` | TLS passthrough (mTLS) |

## Purpose

Validate that `CheckGatewayRouteKindAllowed` evaluates only the listener
targeted by `parentRef.sectionName`, not all listeners on the Gateway.

### How the bug manifests

The buggy code iterates **every** listener and calls `SetParentCondition`
on each one. Each call **overwrites** the previous result. Whichever
listener appears **last** in the Gateway spec determines the final
`Accepted` condition for the route — regardless of which listener the
route actually targets via `sectionName`.

With `tls-passthrough` last (`allowedRoutes.kinds: [TLSRoute]`):

- **HTTPRoutes** → `tls-passthrough` sets `Accepted=False` (HTTPRoute ≠ TLSRoute)
- **GRPCRoutes** → `tls-passthrough` sets `Accepted=False` (GRPCRoute ≠ TLSRoute)
- **TLSRoutes** → `tls-passthrough` sets `Accepted=True` (TLSRoute = TLSRoute)

Only TLSRoutes survive. All HTTPRoutes and GRPCRoutes are silently
rejected with `NotAllowedByListeners`, even though their targeted
listeners explicitly allow them.

### What the fix changes

The fixed code filters the loop by `parentRef.SectionName`, so only the
targeted listener is evaluated. It also replaces per-iteration
`SetParentCondition` calls with a single `hasKindRestriction` flag and
early `return true` on match.

### Coverage of community-reported variant

This scenario also covers the configuration reported by
[@dinoshauer](https://github.com/cilium/cilium/issues/45559#issuecomment-4302047885):
a Gateway with HTTP, HTTPS (Terminate), and TLS (Passthrough) listeners
where only the TLS listener has explicit `allowedRoutes.kinds`. In that
configuration, the implicit-default HTTP/HTTPS listeners (no explicit
kinds) are skipped by the loop, but the TLS listener's explicit
`kinds: [TLSRoute]` still poisons all HTTPRoutes via the overwrite bug.

The `http` listener in this scenario has **no explicit `allowedRoutes.kinds`**
(only `namespaces.from: All`), reproducing that exact pattern.

## Status

**Broken** on Cilium ≤ 1.19.3 and current main.
**Fixed** on the `fix/allowed-routes` branch build (operator-only patch).
Fix tracked in [cilium#45559](https://github.com/cilium/cilium/issues/45559).

### Confirmed on 1.19.3 (2-listener variant)

| Route               | Expected | Actual                | Result |
| ------------------- | -------- | --------------------- | ------ |
| HTTPRoute backend-a | Accepted | NotAllowedByListeners | FAIL   |
| HTTPRoute backend-b | Accepted | NotAllowedByListeners | FAIL   |
| GRPCRoute backend-a | Accepted | Accepted              | PASS   |
| GRPCRoute backend-b | Accepted | Accepted              | PASS   |

With only 2 listeners (`https` → HTTPRoute, `grpcs` → GRPCRoute), the
last listener (`grpcs`) overwrites the Accepted condition. HTTPRoutes
are rejected; GRPCRoutes pass because the last listener allows them.

### Confirmed on fix/allowed-routes branch (2-listener variant)

| Route               | Expected | Actual   | Result |
| ------------------- | -------- | -------- | ------ |
| HTTPRoute backend-a | Accepted | Accepted | PASS   |
| HTTPRoute backend-b | Accepted | Accepted | PASS   |
| GRPCRoute backend-a | Accepted | Accepted | PASS   |
| GRPCRoute backend-b | Accepted | Accepted | PASS   |

All routes accepted. HTTPS and gRPC data-plane traffic verified — both
backends respond correctly, gRPC affinity 10/10 per hostname.

### Expected on buggy version (4-listener variant)

With the expanded 4-listener Gateway (`tls-passthrough` last), the bug
is even more severe — **only TLSRoutes** should be accepted:

| Route               | Expected | Predicted (buggy)     |
| ------------------- | -------- | --------------------- |
| HTTPRoute redirect  | Accepted | NotAllowedByListeners |
| HTTPRoute backend-a | Accepted | NotAllowedByListeners |
| HTTPRoute backend-b | Accepted | NotAllowedByListeners |
| GRPCRoute backend-a | Accepted | NotAllowedByListeners |
| GRPCRoute backend-b | Accepted | NotAllowedByListeners |
| TLSRoute backend-a  | Accepted | Accepted              |

## Difference from Other Scenarios

| Scenario | Ports                 | Hostnames        | Kind Restriction               | Protocols                     |
| -------- | --------------------- | ---------------- | ------------------------------ | ----------------------------- |
| 21       | 443 (shared)          | shared wildcard  | none (implicit)                | HTTPS                         |
| 22       | 443 + 50051           | shared wildcard  | per-listener, per-port         | HTTPS                         |
| 23       | 443 (shared)          | shared wildcard  | both kinds on one listener     | HTTPS                         |
| 25       | 443 (shared)          | per-listener     | none (implicit)                | HTTPS + TLS Passthrough       |
| **27**   | **80 + 443 (shared)** | **per-listener** | **per-listener, per-hostname** | **HTTP + HTTPS + gRPC + TLS** |

## Apply

```
mise run scenario:27:start
mise run scenario:27:verify
```

`scenario:27:start` installs `cert-manager` first if it is not already
present, then issues certificates in `gateway-system` (gateway TLS) and
`backend-a` (mTLS PKI for TLS passthrough).

## Manual Check

HTTP redirect (port 80):

```
curl -v --resolve "http-a.http.example.test:80:127.0.0.1" http://http-a.http.example.test/headers
# Expect: 301 redirect → https://http-a.http.example.test:443/headers
```

HTTPS (port 443):

```
curl -k --resolve "http-a.http.example.test:443:127.0.0.1" https://http-a.http.example.test/headers
curl -k --resolve "http-b.http.example.test:443:127.0.0.1" https://http-b.http.example.test/headers
```

gRPC (port 443):

```
grpcurl -insecure \
  -authority grpc-a.grpc.example.test \
  -proto apps/backend-grpc/proto/grpc/testing/testservice.proto \
  -d '{"response_size":32,"fill_server_id":true}' \
  localhost:443 \
  grpc.testing.TestService/UnaryCall

grpcurl -insecure \
  -authority grpc-b.grpc.example.test \
  -proto apps/backend-grpc/proto/grpc/testing/testservice.proto \
  -d '{"response_size":32,"fill_server_id":true}' \
  localhost:443 \
  grpc.testing.TestService/UnaryCall
```

TLS passthrough / mTLS (port 443):

```
# Extract certs from cluster
kubectl get secret backend-a-mtls-server -n backend-a -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/a-ca.crt
kubectl get secret backend-a-mtls-client -n backend-a -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/a-client.crt
kubectl get secret backend-a-mtls-client -n backend-a -o jsonpath='{.data.tls\.key}' | base64 -d > /tmp/a-client.key

curl --resolve "tls-a.tls.example.test:443:127.0.0.1" \
  --cacert /tmp/a-ca.crt --cert /tmp/a-client.crt --key /tmp/a-client.key \
  https://tls-a.tls.example.test:443/
```
