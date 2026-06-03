# Namespace selector: `allowedRoutes.namespaces` enforcement

Tests that `allowedRoutes.namespaces.from: Selector` only attaches routes from
namespaces matching the listener's namespace selector.

The Gateway has one HTTP listener on port 80:

```yaml
allowedRoutes:
  namespaces:
    from: Selector
    selector:
      matchLabels:
        expose: "true"
```

| Namespace   | Label           | Route hostname                  | Expected            |
| ----------- | --------------- | ------------------------------- | ------------------- |
| `backend-a` | `expose: true`  | `selector-allowed.example.test` | Attached and served |
| `backend-b` | no `expose` key | `selector-denied.example.test`  | Not attached; 404   |

## Resources

| Resource                           | Namespace      | Purpose                                |
| ---------------------------------- | -------------- | -------------------------------------- |
| Gateway `selector-ns-gateway`      | gateway-system | HTTP listener with namespace selector  |
| HTTPRoute `selector-allowed-route` | backend-a      | Route from selector-matching namespace |
| HTTPRoute `selector-denied-route`  | backend-b      | Route from non-matching namespace      |
| Pod `api`                          | backend-a/b    | go-httpbin HTTP backend                |

## Verification

What `verify.sh` checks:

1. Listener status: `http-selector` has exactly 1 attached route
2. HTTP traffic to `selector-allowed.example.test` succeeds
3. HTTP traffic to `selector-denied.example.test` returns 404

This scenario should fail on implementations that treat `from: Selector` as
`from: All` during model ingestion.

## Run

```sh
mise run //scenarios/04-route-admission/http-ns-selector:start
```
