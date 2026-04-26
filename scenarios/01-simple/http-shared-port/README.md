# Two HTTP/80 listeners (shared port, different hostnames)

Baseline: two HTTP listeners on port 80, each with a distinct hostname, two HTTPRoutes attached via `sectionName`. No `allowedRoutes` restrictions.

| Listener | Port | Hostname             | Protocol |
| -------- | ---- | -------------------- | -------- |
| `http-a` | 80   | `api-a.example.test` | HTTP     |
| `http-b` | 80   | `api-b.example.test` | HTTP     |

Apply:

```sh
mise run //scenarios/01-simple/http-shared-port:start
```

Test from the host:

```sh
curl -H 'Host: api-a.example.test' http://localhost/headers
curl -H 'Host: api-b.example.test' http://localhost/headers
```
