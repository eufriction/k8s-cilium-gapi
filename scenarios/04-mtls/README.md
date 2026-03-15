# Multi-Namespace mTLS

This scenario adds a focused mTLS test path using one passthrough Gateway listener and two `backend-mtls` instances in separate namespaces.

It deploys:

- one `backend-mtls` instance in `backend-a`
- one `backend-mtls` instance in `backend-b`
- one `netshoot-client` pod in `client`
- one shared Gateway in `gateway-system`

The Gateway exposes:

- `TLS` passthrough on `9443` for two `TLSRoute`s

Each backend uses its own CA, server certificate, and client certificate. That keeps the verification strong:

- `backend-a` only trusts the `backend-a` client certificate
- `backend-b` only trusts the `backend-b` client certificate

## Purpose

This is a focused `TLSRoute` scenario in the `01–09` series. It demonstrates end-to-end mutual TLS with per-namespace PKI isolation:

- The Gateway performs **TLS passthrough** — it routes by SNI hostname but does **not** terminate TLS.
- Each backend's Envoy sidecar terminates TLS and enforces client certificate verification against its own CA.
- Cross-namespace client certificates are rejected because each namespace has an independent CA.

## Apply

```sh
mise run scenario:04:start
mise run scenario:04:verify
```

`scenario:04:start` installs `cert-manager` first if it is not already present, then issues per-namespace CA hierarchies in `backend-a` and `backend-b`.

## Manual Check

The verify task extracts the right certs from the cluster and checks both success and failure cases automatically. For manual testing you can replicate the same steps.

### Extract certificates from the cluster

```sh
TMPDIR=$(mktemp -d)

# backend-a certs
kubectl get secret backend-a-mtls-server -n backend-a -o jsonpath='{.data.ca\.crt}' | base64 -d > "$TMPDIR/a-ca.crt"
kubectl get secret backend-a-mtls-client -n backend-a -o jsonpath='{.data.tls\.crt}' | base64 -d > "$TMPDIR/a-client.crt"
kubectl get secret backend-a-mtls-client -n backend-a -o jsonpath='{.data.tls\.key}' | base64 -d > "$TMPDIR/a-client.key"

# backend-b certs
kubectl get secret backend-b-mtls-server -n backend-b -o jsonpath='{.data.ca\.crt}' | base64 -d > "$TMPDIR/b-ca.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.crt}' | base64 -d > "$TMPDIR/b-client.crt"
kubectl get secret backend-b-mtls-client -n backend-b -o jsonpath='{.data.tls\.key}' | base64 -d > "$TMPDIR/b-client.key"
```

### Positive tests — correct client cert

```sh
# backend-a with backend-a's client cert (should succeed)
curl --resolve "mtls-a.example.test:9443:127.0.0.1" \
  --cacert "$TMPDIR/a-ca.crt" \
  --cert "$TMPDIR/a-client.crt" \
  --key "$TMPDIR/a-client.key" \
  https://mtls-a.example.test:9443/

# backend-b with backend-b's client cert (should succeed)
curl --resolve "mtls-b.example.test:9443:127.0.0.1" \
  --cacert "$TMPDIR/b-ca.crt" \
  --cert "$TMPDIR/b-client.crt" \
  --key "$TMPDIR/b-client.key" \
  https://mtls-b.example.test:9443/
```

### Negative test — no client cert

```sh
# backend-a without any client cert (should fail — proves mTLS enforcement)
curl --resolve "mtls-a.example.test:9443:127.0.0.1" \
  --cacert "$TMPDIR/a-ca.crt" \
  https://mtls-a.example.test:9443/
```

### Negative test — wrong client cert (cross-namespace)

```sh
# backend-b with backend-a's client cert (should fail — proves CA isolation)
curl --resolve "mtls-b.example.test:9443:127.0.0.1" \
  --cacert "$TMPDIR/b-ca.crt" \
  --cert "$TMPDIR/a-client.crt" \
  --key "$TMPDIR/a-client.key" \
  https://mtls-b.example.test:9443/
```

### Clean up temp files

```sh
rm -rf "$TMPDIR"
```
