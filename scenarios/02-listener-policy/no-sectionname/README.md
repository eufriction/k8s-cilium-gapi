# no-sectionname — TLSRoute without sectionName on mixed-listener Gateway

Three-listener Gateway (HTTP/80, HTTPS-Terminate/443, TLS-Passthrough/443).
The TLSRoute **omits `sectionName`** and should auto-attach only to the
compatible TLS listener per the Gateway API spec. The HTTPRoute attaches to
both the HTTP and HTTPS listeners.

This scenario verifies that a TLSRoute without an explicit `sectionName` is
matched only to the listener whose protocol is compatible (TLS Passthrough),
and does not incorrectly attach to HTTP or HTTPS listeners — which would
create duplicate Envoy FilterChains and break passthrough traffic.

## Resources

| Resource                         | Namespace      | Purpose                                         |
| -------------------------------- | -------------- | ----------------------------------------------- |
| Gateway `mixed-listener-gateway` | gateway-system | HTTP/80 + HTTPS/443 + TLS/443                   |
| HTTPRoute `backend-a-web-route`  | backend-a      | HTTP + HTTPS termination → go-httpbin           |
| TLSRoute `backend-b-mtls-route`  | backend-b      | TLS passthrough → backend-mtls (no sectionName) |
| Pod `api`                        | backend-a      | go-httpbin (HTTP backend)                       |
| Pod `backend-mtls`               | backend-b      | Envoy with per-namespace mTLS certs             |

## Verification

What `verify.sh` checks:

1. All routes are accepted (HTTPRoute on both HTTP and HTTPS parents, TLSRoute on TLS parent)
2. Per-listener `attachedRoutes` and `supportedKinds` are correct (`http`=1, `https`=1, `tls`=1)
3. HTTPS termination — `web.example.test` responds on port 443
4. TLS passthrough — `mtls.example.test` mTLS succeeds on port 443
5. HTTP listener — `web.example.test` responds on port 80
6. TLSRoute has exactly 1 parent (attached only to the `tls` listener, not HTTP or HTTPS)
7. TLSRoute accepted status message matches expected value

## Run

```sh
mise run //scenarios/02-listener-policy/no-sectionname:start
```
