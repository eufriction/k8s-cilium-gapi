# Multi-namespace HTTPRoutes

This scenario deploys the shared `backend-http` app base twice, once in `backend-a` and once in `backend-b`, and attaches both backends to a single Gateway in `gateway-system`. It also deploys a `netshoot-client` pod in `client` for in-cluster inspection and debugging.

Apply the scenario:

```sh
mise run scenario:01:start
mise run scenario:01:verify
```

Test the two routes from your machine:

```sh
curl -i -H 'Host: backend-a.example.test' http://localhost/headers
curl -i -H 'Host: backend-b.example.test' http://localhost/headers
```

The hostname determines which namespace-local backend receives the request.
