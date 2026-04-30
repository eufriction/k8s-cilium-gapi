# redirect — HTTP→HTTPS redirect with RequestRedirect filter

A single Gateway exposes two listeners:

- **HTTP** (port 80) — serves a redirect-only HTTPRoute that returns `301`
  with `scheme: https`.
- **HTTPS** (port 443) — terminates TLS and forwards to `backend-a`.

This exercises the `RequestRedirect` filter, one of the most common Gateway API
patterns. The redirect preserves the original hostname and path, and an
end-to-end `curl -L` flow (HTTP → 301 → HTTPS → 200) is verified.

## Resources

| Kind        | Name                           | Namespace      | Purpose                          |
| ----------- | ------------------------------ | -------------- | -------------------------------- |
| Gateway     | `redirect-gateway`             | gateway-system | HTTP (80) + HTTPS (443) listener |
| HTTPRoute   | `http-redirect`                | gateway-system | Redirect-only route on HTTP      |
| HTTPRoute   | `backend-a-route`              | backend-a      | HTTPS route → backend            |
| Certificate | `redirect-gateway-certificate` | gateway-system | Self-signed TLS cert             |
| Issuer      | `redirect-selfsigned`          | gateway-system | cert-manager self-signed issuer  |
| Pod         | `api`                          | backend-a      | go-httpbin backend               |
| Pod         | `netshoot-client`              | client         | In-cluster debug pod             |

## Verification

What `verify.sh` checks:

1. Backend pod and TLS certificate are ready.
2. Gateway is accepted; both HTTPRoutes are accepted.
3. Listener status: `http` has 1 attached route, `https` has 1 attached route.
4. HTTP request returns **301** redirect.
5. Redirect `Location` header points to an `https://` URL.
6. HTTPS endpoint serves traffic directly.
7. End-to-end follow-redirect flow (HTTP → 301 → HTTPS → 200) succeeds.

## Run

```sh
mise run //scenarios/02-http-routing/redirect:start
```
