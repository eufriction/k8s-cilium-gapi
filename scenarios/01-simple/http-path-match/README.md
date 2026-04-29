# http-path-match — Path prefix routing to different backends

This scenario tests path prefix matching in HTTPRoute rules. Two routes on
the same hostname route traffic to different backends based on the URL path.
Requests to `/api/*` are routed to `backend-a`, while all other requests
(`/*` catch-all) are routed to `backend-b`. The more specific `/api` prefix
takes precedence over the `/` catch-all. Each route injects an
`X-Routed-To` header via `RequestHeaderModifier` to confirm which backend
handled the request.

## Resources

| Resource                     | Namespace      | Purpose                                       |
| ---------------------------- | -------------- | --------------------------------------------- |
| Gateway `path-match-gateway` | gateway-system | Single HTTP listener on port 80               |
| HTTPRoute `backend-a-route`  | backend-a      | Matches `PathPrefix: /api` → backend-a        |
| HTTPRoute `backend-b-route`  | backend-b      | Matches `PathPrefix: /` catch-all → backend-b |
| Pod `api`                    | backend-a      | go-httpbin backend                            |
| Pod `api`                    | backend-b      | go-httpbin backend                            |
| Pod `netshoot-client`        | client         | In-cluster debugging client                   |

## Verification

What `verify.sh` checks:

1. All pods are Ready and the Gateway is Accepted.
2. Both HTTPRoutes report Accepted status.
3. Listener `http` has 2 attached routes.
4. `/api/headers` is routed to `backend-a` (confirmed by `X-Routed-To` header).
5. `/headers` is routed to `backend-b` (confirmed by `X-Routed-To` header).
6. `/api/get` is routed to `backend-a`, confirming `/api` prefix takes precedence over `/` catch-all.

## Run

```sh
mise run //scenarios/01-simple/http-path-match:start
```
