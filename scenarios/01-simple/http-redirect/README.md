# HTTP→HTTPS Redirect

This scenario tests the `RequestRedirect` filter — one of the most common
Gateway API patterns. A single Gateway exposes two listeners:

- **HTTP** (port 80) — serves a redirect-only HTTPRoute that returns `301`
  with `scheme: https`.
- **HTTPS** (port 443) — terminates TLS and forwards to `backend-a`.

## What it proves

1. Cilium honours the `RequestRedirect` filter on an HTTP listener.
2. The redirect preserves the original hostname and path.
3. The HTTPS listener correctly terminates TLS and forwards to the backend.
4. An end-to-end `curl -L` flow (HTTP → 301 → HTTPS → 200) works.

## Run

```sh
mise run //scenarios/01-simple/http-redirect:start
```

With cleanup:

```sh
mise run //scenarios/01-simple/http-redirect:start -- --delete
```

## Resources

| Kind        | Name                           | Namespace      |
| ----------- | ------------------------------ | -------------- |
| Gateway     | `redirect-gateway`             | gateway-system |
| HTTPRoute   | `http-redirect`                | gateway-system |
| HTTPRoute   | `backend-a-route`              | backend-a      |
| Certificate | `redirect-gateway-certificate` | gateway-system |
| Issuer      | `redirect-selfsigned`          | gateway-system |
| Pod         | `api`                          | backend-a      |
| Pod         | `netshoot-client`              | client         |
