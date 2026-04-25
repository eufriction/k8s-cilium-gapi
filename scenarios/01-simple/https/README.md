# HTTPS Termination Baseline

This scenario is the HTTPS counterpart to `http`. One Gateway terminates TLS on port `443` via a self-signed cert-manager certificate, with two HTTPRoute backends in separate namespaces (`https-a.example.test`, `https-b.example.test`).

It deploys:

- `backend-http` into `backend-a` and `backend-b`
- one `netshoot-client` pod in `client`
- one TLS-terminating Gateway in `gateway-system`
- a self-signed cert-manager Issuer and wildcard Certificate

## Purpose

This fills the gap between plaintext HTTP (`http`) and the gRPC/mTLS scenarios by establishing the simplest possible TLS-termination pattern. The Gateway terminates TLS on port `443`, which is exposed on your machine as `localhost:443` through kind `extraPortMappings`.

## Apply

```sh
mise run scenario:03:start
mise run scenario:03:verify
```

`scenario:03:start` installs `cert-manager` first if it is not already present, then issues a self-signed certificate in `gateway-system`.

## Manual Check

```sh
curl -k --resolve "https-a.example.test:443:127.0.0.1" https://https-a.example.test/headers
curl -k --resolve "https-b.example.test:443:127.0.0.1" https://https-b.example.test/headers
```

The hostname determines which namespace-local backend receives the request.

For the plaintext HTTP variant, see [`scenarios/01-simple/http`](../http/README.md).
