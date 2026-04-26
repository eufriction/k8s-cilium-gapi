# HTTP Header-Based Routing

This scenario tests header-based matching in HTTPRoute rules. Two routes
on the same hostname route traffic to different backends based on the
`X-Version` request header.

## What it proves

1. Cilium correctly evaluates `matches[].headers` in HTTPRoute rules.
2. `X-Version: v1` is routed to `backend-a`.
3. `X-Version: v2` is routed to `backend-b`.
4. Requests without a matching header return 404 (no route match).
5. `RequestHeaderModifier` filter correctly injects `X-Routed-To` header.

## Run

```sh
mise run //scenarios/01-simple/http-header-match:start
```

With cleanup:

```sh
mise run //scenarios/01-simple/http-header-match:start -- --delete
```

## Resources

| Kind      | Name                   | Namespace      |
| --------- | ---------------------- | -------------- |
| Gateway   | `header-match-gateway` | gateway-system |
| HTTPRoute | `backend-a-route`      | backend-a      |
| HTTPRoute | `backend-b-route`      | backend-b      |
| Pod       | `api`                  | backend-a      |
| Pod       | `api`                  | backend-b      |
| Pod       | `netshoot-client`      | client         |
