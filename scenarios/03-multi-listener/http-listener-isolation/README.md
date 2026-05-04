# Scenario: HTTP Listener Isolation

## Overview

Tests that when multiple HTTP listeners share the same port (80) with different
hostname specificity levels, each listener **isolates** traffic correctly — a
more-specific listener "claims" hostnames and prevents less-specific listeners
from serving them.

## Gateway Configuration

| Listener           | Hostname               | Specificity                              |
| ------------------ | ---------------------- | ---------------------------------------- |
| `catch-all`        | _(none)_               | Least — matches anything not claimed     |
| `wildcard-example` | `*.example.test`       | Wildcard — any subdomain of example.test |
| `wildcard-foo`     | `*.foo.example.test`   | More specific wildcard                   |
| `exact-abc-foo`    | `abc.foo.example.test` | Most specific — exact match              |

## Routes

Each listener has exactly one HTTPRoute attached via `sectionName`, each serving
a unique path prefix (`/catch-all`, `/wildcard-example`, `/wildcard-foo`,
`/exact-abc-foo`).

## Verification

The verify script confirms **both positive and negative** routing:

1. **Positive:** Each hostname reaches the correct listener's route
2. **Negative (isolation):** Each hostname does NOT reach routes on less-specific listeners

For example, `abc.foo.example.test` must only be served by the `exact-abc-foo`
listener and must NOT hit the `wildcard-foo` or `wildcard-example` listeners.

## Run

```sh
mise run //scenarios/03-multi-listener/http-listener-isolation:start
```

## Related

- Golden test: `gateway-http-listener-isolation` in Cilium operator
- Gateway API spec: [Listener Isolation](https://gateway-api.sigs.k8s.io/reference/spec/#gateway.networking.k8s.io/v1.Listener)
