# HTTP Path-Based Routing

This scenario tests path prefix matching in HTTPRoute rules. Two routes on
the same hostname route traffic to different backends based on the URL path.

## What it proves

1. Cilium correctly evaluates `matches[].path` with `type: PathPrefix`.
2. Requests to `/api/*` are routed to `backend-a`.
3. Requests to `/*` (catch-all) are routed to `backend-b`.
4. The more specific `/api` prefix takes precedence over the `/` catch-all.
5. `RequestHeaderModifier` filter correctly injects `X-Routed-To` header
   to verify which backend received the request.

## Run

```sh
mise run //scenarios/01-simple/http-path-match:start
```

With cleanup:

```sh
mise run //scenarios/01-simple/http-path-match:start -- --delete
```

## Resources

| Kind      | Name                 | Namespace      |
| --------- | -------------------- | -------------- |
| Gateway   | `path-match-gateway` | gateway-system |
| HTTPRoute | `backend-a-route`    | backend-a      |
| HTTPRoute | `backend-b-route`    | backend-b      |
| Pod       | `api`                | backend-a      |
| Pod       | `api`                | backend-b      |
| Pod       | `netshoot-client`    | client         |
