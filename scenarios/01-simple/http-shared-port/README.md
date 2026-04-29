# http-shared-port — Two HTTP listeners on a shared port with distinct hostnames

Two HTTP listeners on port 80, each scoped to a different hostname, with one
HTTPRoute attached to each via `sectionName`. This validates that Cilium
correctly merges multiple HTTP listeners sharing a port and routes by hostname.

## Resources

| Resource                           | Namespace      | Purpose                                            |
| ---------------------------------- | -------------- | -------------------------------------------------- |
| Gateway `http-shared-port-gateway` | gateway-system | Two HTTP listeners (`http-a`, `http-b`) on port 80 |
| HTTPRoute `backend-a-route`        | backend-a      | Routes `api-a.example.test` → backend-a            |
| HTTPRoute `backend-b-route`        | backend-b      | Routes `api-b.example.test` → backend-b            |
| Pod `api`                          | backend-a      | go-httpbin backend                                 |
| Pod `api`                          | backend-b      | go-httpbin backend                                 |

## Verification

What `verify.sh` checks:

1. All pods are ready
2. Gateway is accepted
3. Both HTTPRoutes are accepted
4. Listener `http-a` reports 1 attached route; listener `http-b` reports 1 attached route
5. `curl -H 'Host: api-a.example.test'` returns a successful HTTP response
6. `curl -H 'Host: api-b.example.test'` returns a successful HTTP response
7. Both routes report Accepted message = `"Accepted HTTPRoute"`

## Run

```sh
mise run //scenarios/01-simple/http-shared-port:start
```
