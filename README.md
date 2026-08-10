# Introduction

This repository demonstrates how **Cilium Service Mesh** implements the **Gateway API** in a **kind** cluster. It provides a set of scenarios that exercise different configuration models so you can compare their behavior directly.

---

## Prerequisites

- [mise](https://mise.jdx.dev/installing-mise.html)
- [Docker](https://docs.docker.com/get-docker/) (running locally)

`mise` manages all other required tools (`kind`, `helm`, `cilium-cli`, `hubble`, `kyverno`) automatically.

---

## Quick start

### Preparation (one-time)

#### Activate mise in your shell

Follow the official [mise activate documentation](https://mise.jdx.dev/cli/activate.html) for your shell. Restart your shell after adding the activation line.

#### Set a GitHub token to avoid rate limits (recommended)

```sh
mise set --prompt GITHUB_TOKEN
```

Create a [personal access token](https://github.com/settings/tokens/new) (no scopes needed for public tools). Using `--prompt` keeps the token out of your shell history.

### Run the demo

```sh
mise run cluster:start                      # create kind cluster + install Cilium
mise run //scenarios/01-basic/http:start    # deploy + verify scenario 01
```

Test the two HTTPRoutes from your machine:

```sh
curl -i -H 'Host: backend-a.example.test' http://localhost/headers
curl -i -H 'Host: backend-b.example.test' http://localhost/headers
```

---

## Running scenarios

### Task naming

This repo uses mise [monorepo mode](https://mise.jdx.dev/tasks/monorepo.html). Each scenario has its own `mise.toml` + `verify.sh` and is addressed with the `//scenarios/<name>:<action>` path syntax:

```sh
mise run //scenarios/01-basic/http:start                       # deploy + verify
mise run //scenarios/03-multi-listener/http-grpc-split-port:start  # deploy + verify
```

Each `start` task renders the scenario with `kubectl kustomize . --load-restrictor=LoadRestrictionsNone` and applies it, then runs `verify`. Pass `--delete` to clean up after verification:

```sh
mise run //scenarios/01-basic/http:start --delete    # deploy + verify + delete
```

The `--delete` flag is backed by the `DELETE` env var, so `DELETE=1 mise run …` also works (useful for shell aliases and the glob-based run-all command below).

List all available tasks:

```sh
mise tasks --all | grep scenarios
```

### Run all scenarios

The fastest way to run all scenarios uses a shared fixture that pre-deploys backend pods once:

```sh
mise run cluster:start
mise run scenarios:run-all
mise run cluster:delete
```

`scenarios:run-all` deploys a shared fixture (namespaces + backend pods), runs every scenario in gateway-only mode (only Gateway + Route resources are applied/deleted per scenario), then writes `run-all.log` and the machine-readable `run-all-results.tsv` before tearing down the fixture. Scenarios known to be broken on the active `CILIUM_VERSION` are skipped before deploying.

The results file records the Cilium version, overall status, PASS/FAIL/SKIP counts, each scenario status, failure details, and a copy-pasteable rerun command for failed scenarios. Set `RUN_LOG` or `RUN_RESULTS` to choose different output paths.

To run without the fixture (each scenario deploys its own backends):

```sh
mise run cluster:start
mise run --continue-on-error --jobs 1 '//scenarios/...:start' --delete
mise run cluster:delete
```

`--continue-on-error` ensures all scenarios run even if some fail. `--jobs 1` keeps them sequential so namespaces don't collide. `--delete` cleans up each scenario's resources after verification.

#### Cluster modes

Two cluster modes are available:

| Mode         | Task                 | Gateway access            | Notes                                                                        |
| ------------ | -------------------- | ------------------------- | ---------------------------------------------------------------------------- |
| hostNetwork  | `cluster:start`      | `localhost:<portMapping>` | Fastest. Kind `extraPortMappings` expose Gateway ports directly.             |
| LoadBalancer | `cluster:start --lb` | `<LB IP>:<service port>`  | Production-realistic. Requires `cloud-provider-kind` in a separate terminal. |

LB mode exercises the full `type: LoadBalancer` path that production clusters use. It validates that Gateways receive external IPs and that port-mapping through the kind Docker network works correctly. The redirect scenario in particular needs LB mode to verify HTTP-to-HTTPS redirect following through real service ports.

To run in LB mode:

```sh
mise run cluster:start --lb
# In a separate terminal:
mise run cloud-provider-kind:start
# Back in the main terminal:
mise run --continue-on-error --jobs 1 '//scenarios/...:start' --delete
mise run cluster:delete
```

The [test results table](#test-results-by-version) uses LB mode for all released versions.

### Version profiles

The default Cilium version and version-conditional flags are set in `mise.toml` `[env]`. To test against a different version, copy a version profile to `mise.local.toml`:

```sh
cp versions/1.19.6.toml mise.local.toml
mise run cluster:restart
mise run --continue-on-error --jobs 1 '//scenarios/...:start' --delete 2>&1 | tee run.log
mise run cluster:delete
rm mise.local.toml
```

Available profiles in `versions/`:

| File          | Cilium      | Gateway API | Notes                           |
| ------------- | ----------- | ----------- | ------------------------------- |
| `1.19.6.toml` | 1.19.6      | 1.4.1       | Latest 1.19.x patch             |
| `1.20.0.toml` | 1.20.0      | 1.6.1       | Latest stable release           |
| `branch.toml` | local build | 1.6.1       | Uses `make dev-docker-*` output |

Each profile sets `CILIUM_VERSION`, `GATEWAY_API_VERSION`, and `X_*` env vars that control version-conditional verify behavior (expected status messages, TLSRoute API version).

#### Skip logic

Scenarios that are known to be broken on specific Cilium releases declare a `SCENARIO_SKIP_VERSIONS` env var in their `mise.toml`:

```toml
[env]
SCENARIO_SKIP_VERSIONS = "1.19.1 1.19.3 1.20.0-pre.1"
```

Before deploying, the `scenario:start` template compares `CILIUM_VERSION` against this space-separated list. If it matches, the scenario is skipped with exit 0. The same validation runs inside `verify.sh` via `skip_on_versions` as a safety net for standalone invocation.

Branch builds set `CILIUM_VERSION = "branch"`, which never matches a release version, so branch builds run every scenario and report real pass/fail results.

### Branch builds

To test a locally-built Cilium branch, first build the images in the Cilium repo with the running kind cluster:

```sh
cd ../cilium
make kind-image-agent
make kind-image-operator
```

Then copy `branch.toml` and adjust `CILIUM_CHART_DIR` if needed:

```sh
cp versions/branch.toml mise.local.toml
```

The defaults in `branch.toml` match the standard `make` output:

| Variable                | Description                                                  | Default                                        |
| ----------------------- | ------------------------------------------------------------ | ---------------------------------------------- |
| `CILIUM_CHART_DIR`      | Path to the local Helm chart directory                       | `../cilium/install/kubernetes/cilium`          |
| `CILIUM_AGENT_IMAGE`    | Agent image from `make dev-docker-image`                     | `localhost:5000/cilium/cilium-dev:local`       |
| `CILIUM_OPERATOR_IMAGE` | Operator image from `make dev-docker-operator-generic-image` | `localhost:5000/cilium/operator-generic:local` |

Then run the standard workflow - `cluster:start` handles image loading and Helm install automatically:

```sh
mise run cluster:restart
mise run --continue-on-error --jobs 1 '//scenarios/...:start' --delete 2>&1 | tee run-branch.log
mise run cluster:delete
rm mise.local.toml
```

To reload after rebuilding images without recreating the cluster:

```sh
mise run cilium:reload
```

When `CILIUM_CHART_DIR` is set, the install tasks use the local chart path instead of `cilium/cilium --version`. The image vars are passed as `--set image.override=…` / `--set operator.image.override=…` to Helm and pre-loaded into kind.

---

## Scenarios

Read each scenario README for the scenario-specific test flow.

### Directory structure

| Group directory       | Category              | Contents                                                                |
| --------------------- | --------------------- | ----------------------------------------------------------------------- |
| `01-basic/`           | Basic connectivity    | Single protocol, single listener. The happy-path scenarios              |
| `02-http-routing/`    | HTTP routing features | Header match, path match, redirect, canary                              |
| `03-multi-listener/`  | Multi-listener        | Multiple listeners / route types on one gateway, shared, or split ports |
| `04-route-admission/` | Route admission       | `allowedRoutes.kinds`, `allowedRoutes.namespaces`, sectionName          |
| `06-extensions/`      | Extensions            | External processing, ExternalAuth, and other implementation extensions  |

### Scenario table

| Group                | Scenario                                                                                                            | Scope                                                                                                                | Status                     |
| -------------------- | ------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | -------------------------- |
| `01-basic`           | [`grpc`](scenarios/01-basic/grpc/README.md)                                                                         | GRPCRoute, TLS termination at gateway, two backend namespaces                                                        | ✅ Pass                    |
| `01-basic`           | [`http`](scenarios/01-basic/http/README.md)                                                                         | HTTPRoute, plaintext, one gateway, two backend namespaces                                                            | ✅ Pass                    |
| `01-basic`           | [`https`](scenarios/01-basic/https/README.md)                                                                       | HTTPRoute over HTTPS, TLS termination at gateway, two backend namespaces                                             | ✅ Pass                    |
| `01-basic`           | [`tls-passthrough`](scenarios/01-basic/tls-passthrough/README.md)                                                   | TLSRoute passthrough, mTLS at backend, per-namespace PKI                                                             | ✅ Pass                    |
| `02-http-routing`    | `canary`                                                                                                            | HTTPRoute with weighted backendRefs for traffic splitting                                                            | Planned                    |
| `02-http-routing`    | [`header-match`](scenarios/02-http-routing/header-match/README.md)                                                  | HTTPRoute with header-based match rules, `RequestHeaderModifier`                                                     | ✅ Pass                    |
| `02-http-routing`    | [`path-match`](scenarios/02-http-routing/path-match/README.md)                                                      | HTTPRoute with path prefix routing, `URLRewrite` to strip prefix                                                     | ✅ Pass                    |
| `02-http-routing`    | [`redirect`](scenarios/02-http-routing/redirect/README.md)                                                          | HTTP→HTTPS redirect with `RequestRedirect` filter, dual listener                                                     | ✅ Pass                    |
| `03-multi-listener`  | [`http-grpc-same-hostname`](scenarios/03-multi-listener/http-grpc-same-hostname/README.md)                          | HTTPRoute + GRPCRoute on same hostname, different ports (443 / 50051)                                                | ⚠️ Broken on some versions |
| `03-multi-listener`  | [`http-grpc-shared-port`](scenarios/03-multi-listener/http-grpc-shared-port/README.md)                              | HTTPRoute + GRPCRoute on one HTTPS listener (same port, different hostnames)                                         | ✅ Pass                    |
| `03-multi-listener`  | [`http-grpc-split-port`](scenarios/03-multi-listener/http-grpc-split-port/README.md)                                | HTTPS + gRPC on one gateway, separate ports, two namespaces                                                          | ⚠️ Broken on some versions |
| `03-multi-listener`  | [`http-listener-isolation`](scenarios/03-multi-listener/http-listener-isolation/README.md)                          | Four HTTP listeners on one gateway, exact, and wildcard hostname precedence, listener isolation across host patterns | ✅ Pass                    |
| `03-multi-listener`  | [`http-shared-port`](scenarios/03-multi-listener/http-shared-port/README.md)                                        | Two HTTP/80 listeners, hostname-based routing via `sectionName`                                                      | ✅ Pass                    |
| `03-multi-listener`  | [`https-tls-same-hostname`](scenarios/03-multi-listener/https-tls-same-hostname/README.md)                          | HTTPS termination + TLS passthrough, same hostname, different ports                                                  | ⚠️ Broken on some versions |
| `03-multi-listener`  | [`https-tls-catch-all`](scenarios/03-multi-listener/https-tls-catch-all/README.md)                                  | Catch-all HTTPS termination + TLS passthrough, different ports                                                       | ⚠️ Broken on some versions |
| `03-multi-listener`  | [`https-tls-catch-all-multi-tls-ports`](scenarios/03-multi-listener/https-tls-catch-all-multi-tls-ports/README.md)  | Catch-all HTTPS termination + multi-port TLS passthrough                                                             | ⚠️ Broken on some versions |
| `03-multi-listener`  | [`https-tls-shared-port`](scenarios/03-multi-listener/https-tls-shared-port/README.md)                              | HTTPS termination + TLS passthrough on same port 443, disjoint hostnames                                             | ✅ Pass                    |
| `03-multi-listener`  | [`https-tls-same-port-same-hostname`](scenarios/03-multi-listener/https-tls-same-port-same-hostname/README.md)      | Invalid HTTPS termination + TLS passthrough on same port and hostname should be rejected                             | ⚠️ Broken on some versions |
| `03-multi-listener`  | [`tls-passthrough-same-hostname`](scenarios/03-multi-listener/tls-passthrough-same-hostname/README.md)              | TLS passthrough same hostname on different ports                                                                     | ⚠️ Broken on some versions |
| `03-multi-listener`  | [`tls-split-port`](scenarios/03-multi-listener/tls-split-port/README.md)                                            | Two TLS passthrough listeners on split ports (9443 / 50051), per-namespace mTLS                                      | ✅ Pass                    |
| `04-route-admission` | [`http-https-tls-implicit-kinds`](scenarios/04-route-admission/http-https-tls-implicit-kinds/README.md)             | HTTP/HTTPS/TLS-passthrough on 3 listeners, implicit `allowedRoutes.kinds`                                            | ⚠️ Broken on some versions |
| `04-route-admission` | [`http-ns-allowed`](scenarios/04-route-admission/http-ns-allowed/README.md)                                         | `allowedRoutes.namespaces` per-listener enforcement, cross-namespace HTTPRoute                                       | ✅ Pass                    |
| `04-route-admission` | [`http-ns-selector`](scenarios/04-route-admission/http-ns-selector/README.md)                                       | `allowedRoutes.namespaces.from: Selector` filters HTTPRoutes by namespace labels                                     | ✅ Pass                    |
| `04-route-admission` | [`http-ns-selector-listener-conflict`](scenarios/04-route-admission/http-ns-selector-listener-conflict/README.md)   | Selector-based namespace checks must be enforced independently per listener                                          | ⚠️ Broken on some versions |
| `04-route-admission` | [`http-ns-restricted-split-port`](scenarios/04-route-admission/http-ns-restricted-split-port/README.md)             | Namespace-scoped `allowedRoutes` on split HTTP ports with hostnames                                                  | ✅ Pass                    |
| `04-route-admission` | [`https-grpc-kinds-shared-port`](scenarios/04-route-admission/https-grpc-kinds-shared-port/README.md)               | HTTPRoute + GRPCRoute on one HTTPS listener with `allowedRoutes.kinds`                                               | ⚠️ Broken on some versions |
| `04-route-admission` | [`https-grpc-kinds-split-port`](scenarios/04-route-admission/https-grpc-kinds-split-port/README.md)                 | HTTPS + gRPC on separate ports with per-listener `allowedRoutes.kinds`                                               | ⚠️ Broken on some versions |
| `04-route-admission` | [`https-ns-restricted-same-hostname`](scenarios/04-route-admission/https-ns-restricted-same-hostname/README.md)     | Namespace-restricted same-hostname split-port with `allowedRoutes.namespaces`                                        | ⚠️ Broken on some versions |
| `04-route-admission` | [`https-ns-restricted-shared-port`](scenarios/04-route-admission/https-ns-restricted-shared-port/README.md)         | Namespace-scoped `allowedRoutes` on shared HTTPS port 443                                                            | ✅ Pass                    |
| `04-route-admission` | [`https-tls-kinds-same-hostname`](scenarios/04-route-admission/https-tls-kinds-same-hostname/README.md)             | Kind-restricted HTTPS + TLS passthrough on split ports with `allowedRoutes.kinds`                                    | ⚠️ Broken on some versions |
| `04-route-admission` | [`https-tls-kinds-shared-port`](scenarios/04-route-admission/https-tls-kinds-shared-port/README.md)                 | HTTPS + TLS passthrough on port 443 with per-listener `allowedRoutes.kinds`                                          | ⚠️ Broken on some versions |
| `04-route-admission` | [`multi-protocol-kinds-multi-listener`](scenarios/04-route-admission/multi-protocol-kinds-multi-listener/README.md) | 4 listeners (HTTP/HTTPS/gRPC/TLS), per-listener `allowedRoutes.kinds`, HTTP→HTTPS redirect, TLS passthrough          | ⚠️ Broken on some versions |
| `04-route-admission` | [`tls-no-sectionname-multi-listener`](scenarios/04-route-admission/tls-no-sectionname-multi-listener/README.md)     | TLSRoute without sectionName on mixed-listener Gateway (HTTP/HTTPS/TLS)                                              | ✅ Pass                    |
| `05-multi-gateway`   | `grpc`                                                                                                              | Two gateways, each serving gRPC                                                                                      | Planned                    |
| `05-multi-gateway`   | `multi-protocol`                                                                                                    | Two gateways, mixed protocols                                                                                        | Planned                    |
| `06-extensions`      | [`grpc-ext-proc`](scenarios/06-extensions/grpc-ext-proc/README.md)                                                  | GRPCRoute with Coraza WAF `ext_proc` via `CiliumEnvoyExtProcFilter` and Envoy metric verification                    | ⚠️ Broken on some versions |
| `06-extensions`      | [`http-ext-proc-waf`](scenarios/06-extensions/http-ext-proc-waf/README.md)                                          | Coraza WAF `ext_proc` with cross-namespace `CiliumEnvoyExtProcFilter` Service reference allowed by `ReferenceGrant`  | ⚠️ Broken on some versions |
| `06-extensions`      | [`https-ext-proc-waf`](scenarios/06-extensions/https-ext-proc-waf/README.md)                                        | HTTPS HTTPRoute with TLS termination and Coraza WAF `ext_proc` via `CiliumEnvoyExtProcFilter`                        | ⚠️ Broken on some versions |
| `06-extensions`      | [`https-ext-auth-http`](scenarios/06-extensions/https-ext-auth-http/README.md)                                      | HTTPS HTTPRoute with Gateway API `ExternalAuth` using an HTTP ext_authz backend                                      | ✅ Pass                    |
| `06-extensions`      | [`https-ext-auth-grpc`](scenarios/06-extensions/https-ext-auth-grpc/README.md)                                      | HTTPS HTTPRoute with Gateway API `ExternalAuth` using a gRPC ext_authz backend                                       | ✅ Pass                    |
| `06-extensions`      | [`http-ext-auth-missing-backend`](scenarios/06-extensions/http-ext-auth-missing-backend/README.md)                  | HTTPRoute ExternalAuth fails closed when the configured ext_authz backend Service is missing                         | ✅ Pass                    |
| `06-extensions`      | [`http-ext-proc-referencegrant`](scenarios/06-extensions/http-ext-proc-referencegrant/README.md)                    | `CiliumEnvoyExtProcFilter` cross-namespace backendRef blocked when `ReferenceGrant` does not cover the ref           | ⚠️ Broken on some versions |
| `06-extensions`      | [`http-ext-proc-ext-auth`](scenarios/06-extensions/http-ext-proc-ext-auth/README.md)                                | `CiliumEnvoyExtProcFilter` WAF and `ExternalAuth` coexisting on the same HTTPRoute rule                              | ⚠️ Broken on some versions |
| `06-extensions`      | [`http-ext-proc-conflict-resolution`](scenarios/06-extensions/http-ext-proc-conflict-resolution/README.md)          | Gateway API precedence for ext_proc order, auth placement, and invalid-reference fail-closed behavior                | ⚠️ Broken on some versions |
| `06-extensions`      | `kyverno-route-governance`                                                                                          | Mutating + validating policies for Gateway API route hygiene                                                         | Planned                    |
| `06-extensions`      | `http-rate-limit`                                                                                                   | HTTPRoute with Envoy rate-limit filter                                                                               | Planned                    |
| `07-clustermesh`     | `grpc`                                                                                                              | Cross-cluster gRPC with Cilium ClusterMesh                                                                           | Planned                    |

See the [Known Cilium bugs](#known-cilium-bugs) table for failure details, and [Test results by version](#test-results-by-version) for the full pass/fail/skip grid.

### Known Cilium bugs

Scenarios affected by known bugs declare `SCENARIO_SKIP_VERSIONS` in their `mise.toml` to skip broken Cilium releases automatically. The verify scripts also call `skip_on_versions` as a safety net. See the preceding [Skip logic](#skip-logic) section.

#### Open bugs

Not tracking any current bugs.

#### Fixed (released)

| Bug                                                                                                             | Scenarios                                                                                                                                              | Cilium issue                                                                                                                                                              | Fix                                                   | Available since                                           |
| --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- | --------------------------------------------------------- |
| Statedb panic: "delete did not find old object" on CEC deletion with multi-listener Gateways                    | All multi-listener scenarios (create/delete cycles)                                                                                                    | [#45758](https://github.com/cilium/cilium/issues/45758)                                                                                                                   | [#45949](https://github.com/cilium/cilium/pull/45949) | ≥1.19.6, ≥1.20.0                                          |
| TLSRoute without sectionName creates duplicate FilterChains on mixed-listener Gateway                           | `tls-no-sectionname-multi-listener`                                                                                                                    | [#45050](https://github.com/cilium/cilium/issues/45050)                                                                                                                   | [#45371](https://github.com/cilium/cilium/pull/45371) | ≥1.19.5, ≥1.20.0                                          |
| `isKindAllowed` cross-counts TLSRoutes on HTTP/HTTPS listeners                                                  | `http-https-tls-implicit-kinds`                                                                                                                        | [#45050](https://github.com/cilium/cilium/issues/45050)                                                                                                                   | [#45371](https://github.com/cilium/cilium/pull/45371) | ≥1.19.5, ≥1.20.0                                          |
| `allowedRoutes.kinds` silently excludes GRPCRoute from Envoy config                                             | `https-grpc-kinds-split-port`, `https-grpc-kinds-shared-port`                                                                                          | [#44824](https://github.com/cilium/cilium/issues/44824)                                                                                                                   | [#44826](https://github.com/cilium/cilium/pull/44826) | ≥1.19.3, ≥1.20.0                                          |
| GRPCRoute/TLSRoute status reports "Accepted HTTPRoute"                                                          | `grpc`, `tls-passthrough`                                                                                                                              | [#43881](https://github.com/cilium/cilium/issues/43881)                                                                                                                   | [#44962](https://github.com/cilium/cilium/pull/44962) | ≥1.20.0 (not backported to 1.19.x; data plane unaffected) |
| Multi-port HTTPS listener collapse: single Envoy listener for multiple HTTPS ports causes NACK or route leakage | `http-grpc-split-port`, `http-grpc-same-hostname`, `https-grpc-kinds-split-port`, `https-ns-restricted-same-hostname`, `https-tls-kinds-same-hostname` | [#42898](https://github.com/cilium/cilium/issues/42898), [#44877](https://github.com/cilium/cilium/issues/44877), [#42159](https://github.com/cilium/cilium/issues/42159) | [#44889](https://github.com/cilium/cilium/pull/44889) | ≥1.20.0 (not backported to 1.19.x)                        |
| TLS passthrough split-port same-hostname Envoy wiring failure                                                   | `tls-passthrough-same-hostname`, `https-tls-same-hostname`                                                                                             | [#42898](https://github.com/cilium/cilium/issues/42898)                                                                                                                   | [#44889](https://github.com/cilium/cilium/pull/44889) | ≥1.20.0 (not backported to 1.19.x)                        |
| `CheckGatewayRouteKindAllowed` overwrites Accepted condition across listeners                                   | `https-grpc-kinds-split-port`, `multi-protocol-kinds-multi-listener`, `https-tls-kinds-shared-port`                                                    | [#45559](https://github.com/cilium/cilium/issues/45559)                                                                                                                   | [#45693](https://github.com/cilium/cilium/pull/45693) | ≥1.19.6, ≥1.20.0                                          |
| `CheckGatewayAllowedForNamespace` doesn't enforce per-listener namespace restrictions                           | `https-ns-restricted-same-hostname`                                                                                                                    | [#42159](https://github.com/cilium/cilium/issues/42159)                                                                                                                   | [#45693](https://github.com/cilium/cilium/pull/45693) | ≥1.19.6, ≥1.20.0                                          |

The preceding release thresholds are based on the [Cilium v1.19.5](https://github.com/cilium/cilium/releases/tag/v1.19.5), [v1.19.6](https://github.com/cilium/cilium/releases/tag/v1.19.6), and [v1.20.0](https://github.com/cilium/cilium/releases/tag/v1.20.0) release notes. The v1.19.5 notes include #45371; v1.19.6 includes #45693 and #45949; and v1.20.0 includes all three fixes.

### Test results by version

| Group                | Scenario                              | 1.19.6 | 1.20.0 | main (2b56ecd80b6) | [PR #46479](https://github.com/cilium/cilium/pull/46479) |
| -------------------- | ------------------------------------- | :----: | :----: | :----------------: | :------------------------------------------------------: |
| `01-basic`           | `grpc`                                |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `01-basic`           | `http`                                |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `01-basic`           | `https`                               |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `01-basic`           | `tls-passthrough`                     |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `02-http-routing`    | `header-match`                        |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `02-http-routing`    | `path-match`                          |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `02-http-routing`    | `redirect`                            |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `03-multi-listener`  | `http-grpc-same-hostname`             |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `03-multi-listener`  | `http-grpc-shared-port`               |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `03-multi-listener`  | `http-grpc-split-port`                |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `03-multi-listener`  | `http-listener-isolation`             |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `03-multi-listener`  | `http-shared-port`                    |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `03-multi-listener`  | `https-tls-same-hostname`             |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `03-multi-listener`  | `https-tls-catch-all`                 |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `03-multi-listener`  | `https-tls-catch-all-multi-tls-ports` |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `03-multi-listener`  | `https-tls-shared-port`               |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `03-multi-listener`  | `https-tls-same-port-same-hostname`   |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `03-multi-listener`  | `tls-passthrough-same-hostname`       |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `03-multi-listener`  | `tls-split-port`                      |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `04-route-admission` | `http-https-tls-implicit-kinds`       |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `04-route-admission` | `http-ns-allowed`                     |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `04-route-admission` | `http-ns-selector`                    |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `04-route-admission` | `http-ns-selector-listener-conflict`  |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `04-route-admission` | `http-ns-restricted-split-port`       |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `04-route-admission` | `https-grpc-kinds-shared-port`        |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `04-route-admission` | `https-grpc-kinds-split-port`         |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `04-route-admission` | `https-ns-restricted-same-hostname`   |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `04-route-admission` | `https-ns-restricted-shared-port`     |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `04-route-admission` | `https-tls-kinds-same-hostname`       |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `04-route-admission` | `https-tls-kinds-shared-port`         |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `04-route-admission` | `multi-protocol-kinds-multi-listener` |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `04-route-admission` | `tls-no-sectionname-multi-listener`   |   ✅   |   ✅   |         ✅         |                            ✅                            |
| `06-extensions`      | `grpc-ext-proc`                       |   ❌   |   ❌   |         ❌         |                            ✅                            |
| `06-extensions`      | `http-ext-proc-waf`                   |   ❌   |   ❌   |         ❌         |                            ✅                            |
| `06-extensions`      | `https-ext-proc-waf`                  |   ❌   |   ❌   |         ❌         |                            ✅                            |
| `06-extensions`      | `https-ext-auth-http`                 |   ❌   |   ✅   |         ✅         |                            ✅                            |
| `06-extensions`      | `https-ext-auth-grpc`                 |   ❌   |   ✅   |         ·          |                            ✅                            |
| `06-extensions`      | `http-ext-auth-missing-backend`       |   ⏭️   |   ·    |         ·          |                            ·                             |
| `06-extensions`      | `http-ext-proc-referencegrant`        |   ❌   |   ❌   |         ·          |                            ✅                            |
| `06-extensions`      | `http-ext-proc-ext-auth`              |   ❌   |   ❌   |         ·          |                            ✅                            |
| `06-extensions`      | `http-ext-proc-conflict-resolution`   |   ⏭️   |   ·    |         ·          |                            ·                             |

**Legend:** ✅ = scenario passed, ❌ = scenario failed, ⏭️ = intentionally skipped by version guard (known bug or unsupported feature), · = no result recorded.

**Notes:** Results for released versions use LB mode (`cluster:start --lb` + `cloud-provider-kind`). Column titles identify the Cilium build tested such as released version, branch SHA, or pull request. Cross-reference scenario names with the [Known Cilium bugs](#known-cilium-bugs) table for failure and skip details. PR #46479 ext_proc results were rechecked in fixture/gateway-only mode with `FIXTURE_DEPLOYED=true` after updating each scenario's `gateway/` kustomization.

---

## Repo model

- `apps/`: reusable, namespace-agnostic app bases [`apps/README.md`](apps/README.md)
- `scenarios/`: each scenario is a [mise monorepo config root](https://mise.jdx.dev/tasks/monorepo.html) with its own `mise.toml` + `verify.sh`
- `versions/`: version profiles for multi-version testing (copy to `mise.local.toml`)
- `lib/`: shared bash helpers sourced by verify scripts

## TLS foundation

TLS scenarios use `cert-manager`. It is installed automatically by scenarios that depend on it (via `depends = ["//:cert-manager:install"]`).

The self-signed certificate pattern for this repo lives in [`docs/tls-selfsigned.md`](docs/tls-selfsigned.md). For local checks, use insecure client flags:

```sh
curl -k https://...
grpcurl -insecure ...
```

## Policy foundation

Kyverno is optional and not part of `cluster:start`. Install when needed:

```sh
mise run kyverno:install
mise run kyverno:verify
mise run kyverno:delete
```

---

## Observing with Hubble

```sh
cilium hubble ui                              # web UI
```

Or from the command line:

```sh
cilium hubble port-forward &
hubble observe --namespace backend-a --follow
```

---

## Clean up

```sh
mise run //scenarios/01-basic/http:start --delete    # deploy + verify + delete in one step
mise run //scenarios/01-basic/http:delete --delete    # delete a previously-deployed scenario
mise run cluster:delete                               # delete the cluster (removes everything)
```
