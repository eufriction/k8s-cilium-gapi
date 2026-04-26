# Two TLS passthrough listeners (split port)

Baseline: two TLS passthrough listeners on different ports, each with a distinct hostname. Independent mTLS CA chains per backend; the gateway does not terminate TLS.

| Listener | Port  | Hostname              | Protocol        |
| -------- | ----- | --------------------- | --------------- |
| `mtls-a` | 9443  | `mtls-a.example.test` | TLS Passthrough |
| `mtls-b` | 50051 | `mtls-b.example.test` | TLS Passthrough |

Apply:

```sh
mise run //scenarios/01-simple/tls-split-port:start
```

Test from the host (extract certs first):

```sh
kubectl get secret backend-a-mtls-client -n backend-a -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/a-client.crt
kubectl get secret backend-a-mtls-client -n backend-a -o jsonpath='{.data.tls\.key}' | base64 -d > /tmp/a-client.key
kubectl get secret backend-a-mtls-server -n backend-a -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/a-ca.crt
curl --resolve "mtls-a.example.test:9443:127.0.0.1" \
  --cacert /tmp/a-ca.crt --cert /tmp/a-client.crt --key /tmp/a-client.key \
  https://mtls-a.example.test:9443/
```
