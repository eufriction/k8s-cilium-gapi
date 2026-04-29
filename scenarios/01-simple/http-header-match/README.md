# http-header-match — Header-based HTTPRoute routing

This scenario tests header-based matching in HTTPRoute rules. Two routes on
the same hostname route traffic to different backends based on the `X-Version`
request header. A `RequestHeaderModifier` filter injects an `X-Routed-To`
response header to confirm which backend handled the request.

## Resources

| Resource                       | Namespace      | Purpose                                        |
| ------------------------------ | -------------- | ---------------------------------------------- |
| Gateway `header-match-gateway` | gateway-system | Single HTTP listener on port 80                |
| HTTPRoute `backend-a-route`    | backend-a      | Matches `X-Version: v1`, forwards to backend-a |
| HTTPRoute `backend-b-route`    | backend-b      | Matches `X-Version: v2`, forwards to backend-b |
| Pod `api`                      | backend-a      | go-httpbin backend                             |
| Pod `api`                      | backend-b      | go-httpbin backend                             |
| Pod `netshoot-client`          | client         | In-cluster debug client                        |

## Verification

What `verify.sh` checks:

1. All pods and the Gateway reach ready/accepted state.
2. Both HTTPRoutes are accepted by the Gateway.
3. Listener `http` reports 2 attached routes.
4. `X-Version: v1` routes to `backend-a` (response contains `X-Routed-To` and `backend-a`).
5. `X-Version: v2` routes to `backend-b` (response contains `X-Routed-To` and `backend-b`).
6. A request without the `X-Version` header returns HTTP 404 (no matching route).

## Run

```sh
mise run //scenarios/01-simple/http-header-match:start
```
