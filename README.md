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
mise run //scenarios/01-simple/http:start   # deploy + verify scenario 01
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
mise run //scenarios/01-simple/http:start              # deploy + verify
mise run //scenarios/01-simple/http-grpc-split-port:start  # deploy + verify
```

Each `start` task runs `kubectl apply -k .`, then `verify`. Pass `--delete` to clean up after verification:

```sh
mise run //scenarios/01-simple/http:start --delete   # deploy + verify + delete
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

`scenarios:run-all` deploys a shared fixture (namespaces + backend pods), runs every scenario in gateway-only mode (only Gateway + Route resources are applied/deleted per scenario), then tears down the fixture. Scenarios known to be broken on the active `CILIUM_VERSION` are skipped before deploying.

To run without the fixture (each scenario deploys its own backends):

```sh
mise run cluster:start
mise run --continue-on-error --jobs 1 '//scenarios/...:start' --delete
mise run cluster:delete
```

`--continue-on-error` ensures all 25 scenarios run even if some fail. `--jobs 1` keeps them sequential so namespaces don't collide. `--delete` cleans up each scenario's resources after verification.

### Version profiles

The default Cilium version and version-conditional flags are set in `mise.toml` `[env]`. To test against a different version, copy a version profile to `mise.local.toml`:

```sh
cp versions/1.19.1.toml mise.local.toml
mise run cluster:restart
mise run --continue-on-error --jobs 1 '//scenarios/...:start' --delete 2>&1 | tee run.log
mise run cluster:delete
rm mise.local.toml
```

Available profiles in `versions/`:

| File                          | Cilium       | Gateway API | Notes                                     |
| ----------------------------- | ------------ | ----------- | ----------------------------------------- |
| `1.19.1.toml`                 | 1.19.1       | 1.4.1       | Oldest patch, regression baseline         |
| `1.19.3.toml`                 | 1.19.3       | 1.4.1       | Matches `mise.toml` defaults              |
| `1.20.0-pre.1.toml`           | 1.20.0-pre.1 | 1.5.1       | Pre-release                               |
| `branch.toml`                 | local build  | 1.5.1       | Set `CILIUM_CHART_DIR` and image vars     |
| `fix-server-names-dedup.toml` | local build  | 1.5.1       | fix/server-names-dedup branch (PR #45624) |

Each profile sets `CILIUM_VERSION`, `GATEWAY_API_VERSION`, and `X_*` env vars that control version-conditional verify behavior (expected status messages, TLSRoute API version).

#### Skip logic

Scenarios that are known to be broken on specific Cilium releases declare a `SCENARIO_SKIP_VERSIONS` env var in their `mise.toml`:

```toml
[env]
SCENARIO_SKIP_VERSIONS = "1.19.1 1.19.3 1.20.0-pre.1"
```

Before deploying, the `scenario:start` template compares `CILIUM_VERSION` against this space-separated list. If it matches, the scenario is skipped with exit 0. The same check runs inside `verify.sh` via `skip_on_versions` as a safety net for standalone invocation.

Branch builds set `CILIUM_VERSION = "branch"`, which never matches a release version — so branch builds run every scenario and report real pass/fail results.

### Branch builds

To test a locally-built Cilium branch, copy `branch.toml` and fill in the three path/image vars:

```sh
cp versions/branch.toml mise.local.toml
```

Edit `mise.local.toml` and set:

| Variable                | Description                                 | Example                                      |
| ----------------------- | ------------------------------------------- | -------------------------------------------- |
| `CILIUM_CHART_DIR`      | Path to the local Helm chart directory      | `/home/you/cilium/install/kubernetes/cilium` |
| `CILIUM_AGENT_IMAGE`    | Locally-built agent image ref (optional)    | `quay.io/cilium/cilium-dev:local`            |
| `CILIUM_OPERATOR_IMAGE` | Locally-built operator image ref (optional) | `quay.io/cilium/operator-generic:local`      |

Then run the standard workflow — `cluster:start` handles image loading and Helm install automatically:

```sh
mise run cluster:restart
mise run --continue-on-error --jobs 1 '//scenarios/...:start' --delete 2>&1 | tee run-branch.log
mise run cluster:delete
rm mise.local.toml
```

When `CILIUM_CHART_DIR` is set, the install tasks use the local chart path instead of `cilium/cilium --version`. When the image vars are set, they are passed as `--set image.override=…` / `--set operator.image.override=…` to Helm and pre-loaded into kind.

---

## Scenarios

Read each scenario README for the scenario-specific test flow.

### Directory structure

| Group directory       | Category              | Contents                                                        |
| --------------------- | --------------------- | --------------------------------------------------------------- |
| `01-simple/`          | Simple gateway setups | Single or dual protocol, one gateway — the happy-path scenarios |
| `02-listener-policy/` | Listener policy       | `allowedRoutes.kinds`, `allowedRoutes.namespaces`, sectionName  |
| `03-multi-port/`      | Multi-port / topology | Same hostname on split ports, per-port Envoy listeners          |

### Scenario table

| Group                | Scenario                                                                                                                           | Scope                                                                                                       | Status                                                  |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `01-simple`          | [`grpc`](scenarios/01-simple/grpc/README.md)                                                                                       | GRPCRoute, TLS termination at gateway, two backend namespaces                                               | ✅ Pass (#43881 cosmetic on ≤1.19.x)                    |
| `01-simple`          | [`http`](scenarios/01-simple/http/README.md)                                                                                       | HTTPRoute, plaintext, one gateway, two backend namespaces                                                   | ✅ Pass                                                 |
| `01-simple`          | `http-canary`                                                                                                                      | HTTPRoute with weighted backendRefs for traffic splitting                                                   | Planned                                                 |
| `01-simple`          | [`http-grpc-shared-port`](scenarios/01-simple/http-grpc-shared-port/README.md)                                                     | HTTPRoute + GRPCRoute on one HTTPS listener (same port, different hostnames)                                | ✅ Pass                                                 |
| `01-simple`          | [`http-grpc-split-port`](scenarios/01-simple/http-grpc-split-port/README.md)                                                       | HTTPS + gRPC on one gateway, separate ports, two namespaces                                                 | ⚠️ #45623 on ≥1.19.2 (pass on 1.19.1, fix/server-names) |
| `01-simple`          | [`http-header-match`](scenarios/01-simple/http-header-match/README.md)                                                             | HTTPRoute with header-based match rules, `RequestHeaderModifier`                                            | ✅ Pass                                                 |
| `01-simple`          | [`http-path-match`](scenarios/01-simple/http-path-match/README.md)                                                                 | HTTPRoute with path prefix routing, `URLRewrite` to strip prefix                                            | ✅ Pass                                                 |
| `01-simple`          | [`http-redirect`](scenarios/01-simple/http-redirect/README.md)                                                                     | HTTP→HTTPS redirect with `RequestRedirect` filter, dual listener                                            | ✅ Pass                                                 |
| `01-simple`          | [`http-shared-port`](scenarios/01-simple/http-shared-port/README.md)                                                               | Two HTTP/80 listeners, hostname-based routing via `sectionName`                                             | ✅ Pass                                                 |
| `01-simple`          | [`https`](scenarios/01-simple/https/README.md)                                                                                     | HTTPRoute over HTTPS, TLS termination at gateway, two backend namespaces                                    | ✅ Pass                                                 |
| `01-simple`          | [`https-tls-shared-port`](scenarios/01-simple/https-tls-shared-port/README.md)                                                     | HTTPS termination + TLS passthrough on same port 443, disjoint hostnames                                    | ✅ Pass                                                 |
| `01-simple`          | [`tls-passthrough`](scenarios/01-simple/tls-passthrough/README.md)                                                                 | TLSRoute passthrough, mTLS at backend, per-namespace PKI                                                    | ✅ Pass (#43881 cosmetic on ≤1.19.x)                    |
| `01-simple`          | [`tls-split-port`](scenarios/01-simple/tls-split-port/README.md)                                                                   | Two TLS passthrough listeners on split ports (9443 / 50051), per-namespace mTLS                             | ✅ Pass                                                 |
| `02-listener-policy` | [`kind-restricted-https-tls-shared-port`](scenarios/02-listener-policy/kind-restricted-https-tls-shared-port/README.md)            | HTTPS + TLS passthrough on port 443 with per-listener `allowedRoutes.kinds`                                 | ⚠️ #45559                                               |
| `02-listener-policy` | [`kinds-multi-listener`](scenarios/02-listener-policy/kinds-multi-listener/README.md)                                              | 4 listeners (HTTP/HTTPS/gRPC/TLS), per-listener `allowedRoutes.kinds`, HTTP→HTTPS redirect, TLS passthrough | ⚠️ #45559                                               |
| `02-listener-policy` | [`kinds-shared-port`](scenarios/02-listener-policy/kinds-shared-port/README.md)                                                    | HTTPRoute + GRPCRoute on one HTTPS listener with `allowedRoutes.kinds`                                      | ✅ Pass on ≥1.19.3 (#44824 on ≤1.19.1)                  |
| `02-listener-policy` | [`kinds-split-port`](scenarios/02-listener-policy/kinds-split-port/README.md)                                                      | HTTPS + gRPC on separate ports with per-listener `allowedRoutes.kinds`                                      | ⚠️ #45559, #45623                                       |
| `02-listener-policy` | [`namespace-restricted-shared-port`](scenarios/02-listener-policy/namespace-restricted-shared-port/README.md)                      | Namespace-scoped `allowedRoutes` on shared HTTPS port 443                                                   | ✅ Pass                                                 |
| `02-listener-policy` | [`namespace-restricted-split-port`](scenarios/02-listener-policy/namespace-restricted-split-port/README.md)                        | Namespace-scoped `allowedRoutes` on split HTTP ports with hostnames                                         | ✅ Pass                                                 |
| `02-listener-policy` | [`namespaces`](scenarios/02-listener-policy/namespaces/README.md)                                                                  | `allowedRoutes.namespaces` per-listener enforcement, cross-namespace HTTPRoute                              | ✅ Pass                                                 |
| `02-listener-policy` | [`no-sectionname`](scenarios/02-listener-policy/no-sectionname/README.md)                                                          | TLSRoute without sectionName on mixed-listener Gateway (HTTP/HTTPS/TLS)                                     | ⚠️ #45050                                               |
| `03-multi-port`      | [`http-grpc-same-hostname`](scenarios/03-multi-port/http-grpc-same-hostname/README.md)                                             | HTTPRoute + GRPCRoute on same hostname, different ports (443 / 50051)                                       | ⚠️ #44877, #45623                                       |
| `03-multi-port`      | [`https-tls-same-hostname-split-port`](scenarios/03-multi-port/https-tls-same-hostname-split-port/README.md)                       | HTTPS termination + TLS passthrough, same hostname, different ports                                         | ⚠️ #45623, #45050                                       |
| `03-multi-port`      | [`kind-restricted-https-tls-split-port`](scenarios/03-multi-port/kind-restricted-https-tls-split-port/README.md)                   | Kind-restricted HTTPS + TLS passthrough on split ports with `allowedRoutes.kinds`                           | ⚠️ #45559, #45623, #45050                               |
| `03-multi-port`      | [`namespace-restricted-same-hostname-split-port`](scenarios/03-multi-port/namespace-restricted-same-hostname-split-port/README.md) | Namespace-restricted same-hostname split-port with `allowedRoutes.namespaces`                               | ⚠️ #42159, #44877                                       |
| `03-multi-port`      | [`tls-passthrough-same-hostname`](scenarios/03-multi-port/tls-passthrough-same-hostname/README.md)                                 | TLS passthrough same hostname on different ports                                                            | ⚠️ #42898                                               |
| —                    | `30-multi-gateway-grpc`                                                                                                            | Two gateways, each serving gRPC                                                                             | Planned                                                 |
| —                    | `31-multi-gateway-multi-protocol`                                                                                                  | Two gateways, mixed protocols                                                                               | Planned                                                 |
| —                    | `40-kyverno-route-governance`                                                                                                      | Mutating + validating policies for Gateway API route hygiene                                                | Planned                                                 |
| —                    | `41-http-rate-limit`                                                                                                               | HTTPRoute with Envoy rate-limit filter                                                                      | Planned                                                 |
| —                    | `42-http-ext-auth`                                                                                                                 | HTTPRoute with OIDC / external authorization                                                                | Planned                                                 |
| —                    | `50-clustermesh-grpc`                                                                                                              | Cross-cluster gRPC with Cilium ClusterMesh                                                                  | Planned                                                 |

> **Note:** Issue IDs are suspected causes based on observed symptoms — root cause is not confirmed for every scenario. Where multiple issues are listed, the bugs may be related or compound; fixing one may resolve others. See the [Known Cilium bugs](#known-cilium-bugs) table below for details.

### Known Cilium bugs

Scenarios affected by known bugs declare `SCENARIO_SKIP_VERSIONS` in their `mise.toml` to skip broken Cilium releases automatically. The verify scripts also call `skip_on_versions` as a safety net. See [Skip logic](#skip-logic) above.

#### Open bugs

| Bug                                                                                   | Scenarios                                                                     | Cilium issue                                            | Fix                                                                                      | Status                                                                                                                                                                                                                                                |
| ------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CheckGatewayAllowedForNamespace` doesn't enforce per-listener namespace restrictions | namespace-restricted-same-hostname-split-port                                 | [#42159](https://github.com/cilium/cilium/issues/42159) | [fix/allowed-routes-main](https://github.com/cilium/cilium/tree/fix/allowed-routes-main) | Broken on all tested releases; route-attachment checks verified fixed on allowed-routes branch (data plane still needs #44889 for split-port scenarios)                                                                                               |
| `CheckGatewayRouteKindAllowed` overwrites Accepted condition across listeners         | kinds-split-port, kinds-multi-listener, kind-restricted-https-tls-shared-port | [#45559](https://github.com/cilium/cilium/issues/45559) | [fix/allowed-routes-main](https://github.com/cilium/cilium/tree/fix/allowed-routes-main) | Broken on all tested releases; verified fixed on allowed-routes branch (kinds-multi-listener ✅, kind-restricted-https-tls-shared-port ✅; kinds-split-port still ❌ due to #45623)                                                                   |
| TLS passthrough split-port same-hostname Envoy wiring failure                         | tls-passthrough-same-hostname                                                 | [#42898](https://github.com/cilium/cilium/issues/42898) | —                                                                                        | Broken on all tested versions (`SSL_ERROR_SYSCALL`)                                                                                                                                                                                                   |
| TLSRoute without sectionName creates duplicate FilterChains on mixed-listener Gateway | no-sectionname                                                                | [#45050](https://github.com/cilium/cilium/issues/45050) | [#45371](https://github.com/cilium/cilium/pull/45371)                                    | Broken on ≤1.19.3 and #44889 branch build (#45371 not merged)                                                                                                                                                                                         |
| `toFilterChainMatch` duplicate `serverNames` after `SortedUnique` removal             | http-grpc-split-port, kinds-split-port, http-grpc-same-hostname               | [#45623](https://github.com/cilium/cilium/issues/45623) | [fix/server-names-dedup](https://github.com/cilium/cilium/tree/fix/server-names-dedup)   | Broken on ≥1.19.2 (regression in `9ee2db2b32`); works on 1.19.1; http-grpc-split-port now passes on #44889 branch (per-port listeners avoid the conflict); verified fixed on fix/server-names-dedup (restores `SortedUnique` in `toFilterChainMatch`) |
| Same-hostname GRPCRoutes on split ports return 404                                    | http-grpc-same-hostname                                                       | [#44877](https://github.com/cilium/cilium/issues/44877) | [#44889](https://github.com/cilium/cilium/pull/44889)                                    | Broken on ≤1.20.0-pre.1; verified fixed on #44889 branch build (not yet in a release)                                                                                                                                                                 |

#### Fixed bugs

| Bug                                                                 | Scenarios                           | Cilium issue                                            | Fix                                                   | Available since                                           |
| ------------------------------------------------------------------- | ----------------------------------- | ------------------------------------------------------- | ----------------------------------------------------- | --------------------------------------------------------- |
| `allowedRoutes.kinds` silently excludes GRPCRoute from Envoy config | kinds-split-port, kinds-shared-port | [#44824](https://github.com/cilium/cilium/issues/44824) | [#44826](https://github.com/cilium/cilium/pull/44826) | ≥1.19.3, ≥1.20.0                                          |
| GRPCRoute/TLSRoute status reports "Accepted HTTPRoute"              | grpc, tls-passthrough               | [#43881](https://github.com/cilium/cilium/issues/43881) | [#44962](https://github.com/cilium/cilium/pull/44962) | ≥1.20.0 (not backported to 1.19.x; data plane unaffected) |

### Test results by version

| Group                | Scenario                                      | 1.19.1 | 1.19.3 | 1.20.0-pre.1 | #45624 | #44889 | allowed-routes | combined |
| -------------------- | --------------------------------------------- | :----: | :----: | :----------: | :----: | :----: | :------------: | :------: |
| `01-simple`          | grpc                                          |   ✅   |   ✅   |      ✅      |   ✅   |   ✅   |       ✅       |    ✅    |
| `01-simple`          | http                                          |   ✅   |   ✅   |      ✅      |   ✅   |   ✅   |       ✅       |    ✅    |
| `01-simple`          | http-grpc-shared-port                         |   ✅   |   ✅   |      ✅      |   ✅   |   ✅   |       ✅       |    ✅    |
| `01-simple`          | http-grpc-split-port                          |   ✅   |   ❌   |      ❌      |   ✅   |   ✅   |       ❌       |    ✅    |
| `01-simple`          | http-header-match                             |   ✅   |   ✅   |      ✅      |   ✅   |   ✅   |       ✅       |    ✅    |
| `01-simple`          | http-path-match                               |   ✅   |   ✅   |      ✅      |   ✅   |   ✅   |       ✅       |    ✅    |
| `01-simple`          | http-redirect                                 |   ✅   |   ✅   |      ✅      |   ✅   |   ✅   |       ✅       |    ✅    |
| `01-simple`          | http-shared-port                              |   ✅   |   ✅   |      ✅      |   ✅   |   ✅   |       ✅       |    ✅    |
| `01-simple`          | https                                         |   ✅   |   ✅   |      ✅      |   ✅   |   ✅   |       ✅       |    ✅    |
| `01-simple`          | https-tls-shared-port                         |   ✅   |   ✅   |      ✅      |   ✅   |   ✅   |       ✅       |    ✅    |
| `01-simple`          | tls-passthrough                               |   ✅   |   ✅   |      ✅      |   ✅   |   ✅   |       ✅       |    ✅    |
| `01-simple`          | tls-split-port                                |   ✅   |   ✅   |      ✅      |   ✅   |   ✅   |       ✅       |    ✅    |
| `02-listener-policy` | kind-restricted-https-tls-shared-port         |   ⏭️   |   ⏭️   |      ⏭️      |   ❌   |   ❌   |       ✅       |    ✅    |
| `02-listener-policy` | kinds-multi-listener                          |   ❌   |   ❌   |      ❌      |   ❌   |   ❌   |       ✅       |    ✅    |
| `02-listener-policy` | kinds-shared-port                             |   ⏭️   |   ✅   |      ✅      |   ✅   |   ✅   |       ✅       |    ✅    |
| `02-listener-policy` | kinds-split-port                              |   ⏭️   |   ⏭️   |      ⏭️      |   ❌   |   ❌   |       ❌       |    ✅    |
| `02-listener-policy` | namespace-restricted-shared-port              |   ✅   |   ✅   |      ✅      |   ✅   |   ✅   |       ✅       |    ✅    |
| `02-listener-policy` | namespace-restricted-split-port               |   ✅   |   ✅   |      ✅      |   ✅   |   ✅   |       ✅       |    ✅    |
| `02-listener-policy` | namespaces                                    |   ✅   |   ✅   |      ✅      |   ✅   |   ✅   |       ✅       |    ✅    |
| `02-listener-policy` | no-sectionname                                |   ⏭️   |   ⏭️   |      ❌      |   ❌   |   ❌   |       ❌       |    ❌    |
| `03-multi-port`      | http-grpc-same-hostname                       |   ⏭️   |   ⏭️   |      ⏭️      |   ❌   |   ✅   |       ❌       |    ✅    |
| `03-multi-port`      | https-tls-same-hostname-split-port            |   ⏭️   |   ⏭️   |      ⏭️      |   ❌   |   ❌   |       ❌       |    ❌    |
| `03-multi-port`      | kind-restricted-https-tls-split-port          |   ⏭️   |   ⏭️   |      ⏭️      |   ❌   |   ❌   |       ❌       |    ❌    |
| `03-multi-port`      | namespace-restricted-same-hostname-split-port |   ⏭️   |   ⏭️   |      ⏭️      |   ✅   |   ✅   |       ❌       |    ✅    |
| `03-multi-port`      | tls-passthrough-same-hostname                 |   ⏭️   |   ⏭️   |      ⏭️      |   ❌   |   ❌   |       ❌       |    ❌    |

✅ = pass ❌ = fail ⏭️ = skipped (known bug) — = not yet tested.
Cross-reference scenario names with the [Known Cilium bugs](#known-cilium-bugs) table for failure and skip details.

---

## Repo model

- `apps/` — reusable, namespace-agnostic app bases ([`apps/README.md`](apps/README.md))
- `scenarios/` — each scenario is a [mise monorepo config root](https://mise.jdx.dev/tasks/monorepo.html) with its own `mise.toml` + `verify.sh`
- `versions/` — version profiles for multi-version testing (copy to `mise.local.toml`)
- `lib/` — shared bash helpers sourced by verify scripts

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
mise run //scenarios/01-simple/http:start --delete   # deploy + verify + delete in one step
mise run //scenarios/01-simple/http:delete --delete   # delete a previously-deployed scenario
mise run cluster:delete                               # delete the cluster (removes everything)
```
