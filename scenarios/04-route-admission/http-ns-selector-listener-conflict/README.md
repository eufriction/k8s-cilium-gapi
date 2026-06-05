# HTTPRoute namespace selector listener conflict

This scenario proves that `allowedRoutes.namespaces.from: Selector` is enforced
for each listener, not only during gateway-level route admission.

It is a regression test for listener-level selector leaks.

## Topology

- Gateway: `gateway-system/selector-listener-conflict-gateway`
- Listener `http-selected`
  - port `80`
  - hostname `selected.example.test`
  - accepts namespaces with `expose=true`
- Listener `http-unselected`
  - port `80`
  - hostname `unselected.example.test`
  - accepts namespaces where the `expose` label does not exist
- HTTPRoute: `backend-a/selector-conflict-route`
  - parentRef targets the Gateway without `sectionName`
  - hostnames include both listener hostnames
  - backend namespace `backend-a` has `expose=true`

Because `backend-a` has `expose=true`, the route may attach to
`http-selected`. It must not attach to `http-unselected`.

## What this catches

Gateway-level filtering can keep the route because it is allowed by
`http-selected`. Model ingestion still has to evaluate namespace selectors for
the specific listener being rendered. If ingestion treats selector-based
listeners as allow-all, the route can also be rendered for `http-unselected` and
`unselected.example.test` will incorrectly route to the backend.

## Expected behavior

- `selected.example.test` returns backend traffic.
- `unselected.example.test` returns `404`.
- Gateway listener status reports:
  - `http-selected` attachedRoutes = `1`
  - `http-unselected` attachedRoutes = `0`

## Run

```sh
mise run //scenarios/04-route-admission/http-ns-selector-listener-conflict:start
```

Clean up after verification:

```sh
mise run //scenarios/04-route-admission/http-ns-selector-listener-conflict:start --delete
```
