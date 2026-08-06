# `http-ext-auth-missing-backend` - ExternalAuth fails closed when its backend is missing

This scenario verifies that Gateway API `ExternalAuth` fails closed when its
configured HTTP ext_authz Service does not exist. The cross-namespace
`ReferenceGrant` deliberately permits the exact Service name, isolating the
missing-backend behavior from reference-permission validation.

## Resources

| Resource                                                        | Namespace      | Purpose                                    |
| --------------------------------------------------------------- | -------------- | ------------------------------------------ |
| Gateway `ext-auth-missing-backend-gateway`                      | gateway-system | HTTP listener on port 80                   |
| HTTPRoute `ext-auth-missing-backend-route`                      | backend-a      | Routes traffic through HTTP ExternalAuth   |
| ReferenceGrant `allow-backend-a-httproute-to-missing-ext-authz` | auth           | Permits the missing auth Service reference |
| Service `external-authz-missing`                                | auth           | Intentionally absent ext_authz backend     |
| Pod `api`                                                       | backend-a      | go-httpbin backend                         |

## Verification

What `verify.sh` checks:

1. The backend pod is Ready.
2. The configured ext_authz Service is absent.
3. Gateway is Accepted.
4. HTTPRoute is Accepted and attached to the Gateway.
5. The data plane fails closed with HTTP 500 instead of forwarding to the
   backend.

## Prerequisites

This scenario requires Cilium and Gateway API CRDs with experimental
`HTTPRoute` `ExternalAuth` support. Released profiles that do not include this
support are skipped via `SCENARIO_SKIP_VERSIONS`.

## Run

```sh
mise run //scenarios/06-extensions/http-ext-auth-missing-backend:start
```
