# http — Multi-namespace HTTPRoutes

Two HTTPRoute resources in separate namespaces attach to a single HTTP Gateway,
routing traffic by hostname. `backend-a.example.test` reaches `backend-a` and
`backend-b.example.test` reaches `backend-b`. This is the simplest possible
multi-namespace HTTPRoute topology.

## Resources

| Resource                          | Namespace      | Purpose                                     |
| --------------------------------- | -------------- | ------------------------------------------- |
| Gateway `multi-namespace-gateway` | gateway-system | HTTP listener on port 80                    |
| HTTPRoute `backend-a-route`       | backend-a      | Routes `backend-a.example.test` → backend-a |
| HTTPRoute `backend-b-route`       | backend-b      | Routes `backend-b.example.test` → backend-b |
| Pod `api`                         | backend-a      | go-httpbin backend                          |
| Pod `api`                         | backend-b      | go-httpbin backend                          |
| Pod `netshoot-client`             | client         | In-cluster debugging client                 |

## Verification

What `verify.sh` checks:

1. Both backend pods are Ready.
2. Gateway is Accepted.
3. Both HTTPRoutes are Accepted.
4. Listener `http` reports 2 attached routes.
5. `curl -H 'Host: backend-a.example.test' http://localhost/headers` returns 200.
6. `curl -H 'Host: backend-b.example.test' http://localhost/headers` returns 200.
7. Both routes report Accepted message `"Accepted HTTPRoute"`.

## Run

```sh
mise run //scenarios/01-simple/http:start
```
