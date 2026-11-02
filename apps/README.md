# App bases

`apps/` contains reusable, namespace-agnostic app bases.

## Bases

| Directory                | Image                                   | Purpose                                                                                                                                                                                                                                                                                                   |
| ------------------------ | --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `backend-grpc/`          | `backend-grpc` (locally built)          | gRPC test server implementing `grpc.testing.TestService`. Source in `image/`, proto fixtures in `proto/`.                                                                                                                                                                                                 |
| `backend-http/`          | `mccutchen/go-httpbin`                  | HTTP echo server (go-httpbin). Returns request headers, method, etc.                                                                                                                                                                                                                                      |
| `backend-mtls/`          | `envoyproxy/envoy`                      | Envoy proxy configured for mutual TLS. Requires a `Secret` with `tls.crt`, `tls.key`, and `ca.crt`. The pod volume uses `secretName: replace-me`—scenario overlays **must** patch this to the real cert-manager Secret name. Listens on port `9443` and returns a static `200 "backend-mtls\n"` response. |
| `coraza-waf-extproc/`    | `coraza-waf-extproc` (locally built)    | Coraza WAF Envoy external processor. Blocks requests that trip an OWASP-style rule and tags the rest with `x-waf-result`.                                                                                                                                                                                 |
| `external-authz/`        | `external-authz` (locally built)        | HTTP and gRPC Envoy ext_authz test service for Gateway API `ExternalAuth` scenarios.                                                                                                                                                                                                                      |
| `netshoot-client/`       | `nicolaka/netshoot`                     | Disposable client pod (`sleep infinity`) with curl, dig, nmap, and other network debugging tools pre-installed.                                                                                                                                                                                           |
| `route-mutator-extproc/` | `route-mutator-extproc` (locally built) | Envoy external processor that rewrites `:path` and sets `clear_route_cache`. Used to probe whether an ext_proc filter can move a request onto a different route.                                                                                                                                          |

## Rules

- One app base per directory.
- No `Namespace` resources in `apps/`.
- No Gateway API resources in `apps/`.
- No hardcoded `metadata.namespace` in app manifests.
- Number files in dependency order starting at `10`, incrementing by `10`. The suffix describes the resource type (for example `10-configmap.yaml`, `20-pod.yaml`, `30-service.yaml`).
- `kustomization.yaml` in every app base.

## Conventions

- Use `Pod` for disposable demo clients or very small single-instance workloads.
- Use `Deployment` when rollout behavior, restart semantics, or scaling are part of what you want to test.
- Keep each app base small enough that a scenario overlay only needs to set namespace and occasional tiny patches.
- If the repo owns the workload implementation, keep its container source in `image/` and any checked-in client fixtures in `proto/` under the same app directory.
- When the app needs TLS material, use a `Secret` volume with a placeholder `secretName` so scenario overlays can patch it per-namespace.
