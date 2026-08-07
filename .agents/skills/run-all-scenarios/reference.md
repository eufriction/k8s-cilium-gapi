# Run-all reference

## Timeout guidance

Use `timeout_ms >= 1800000` for full-suite runs.

## Useful environment variables

These values come from `mise.toml` and affect scenario verification timing:

| Variable                    | Default | Purpose                                                              |
| --------------------------- | ------- | -------------------------------------------------------------------- |
| `POD_READY_TIMEOUT`         | `10`    | Seconds to wait for pod readiness                                    |
| `MTLS_POD_READY_TIMEOUT`    | `60`    | Seconds to wait for mTLS pods with init containers                   |
| `GW_READY_TIMEOUT`          | `5`     | Seconds to wait for `Programmed=True`                                |
| `ROUTE_READY_TIMEOUT`       | `5`     | Seconds to wait for `Accepted=True`                                  |
| `LISTENER_READY_TIMEOUT`    | `5`     | Floor for listener readiness retries                                 |
| `ENVOY_READY_TIMEOUT`       | `30`    | Seconds to wait for LB Envoy listener, route, and policy convergence |
| `ENVOY_TEARDOWN_TIMEOUT`    | `30`    | Seconds to wait for LB resources and Envoy state to disappear        |
| `AUTO_RECOVER_CILIUM_ENVOY` | unset   | Optional one-shot local Envoy recovery; leave unset in CI            |
| `PRE_DELETE_SLEEP`          | `5`     | Sleep before deleting resources                                      |
| `POST_DELETE_SLEEP`         | `0`     | Optional bounded fallback sleep after deletion gates                 |

## Version profile example

To test a specific release profile before starting the cluster:

```sh
cp versions/1.19.4.toml mise.local.toml
```

For local Cilium branch builds, use `versions/branch.toml`. It sets `CILIUM_VERSION=branch`, so branch runs do not match release-only skip lists.
