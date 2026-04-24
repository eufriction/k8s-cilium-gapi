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
mise run //scenarios/01-http:start          # deploy + verify scenario 01
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
mise run //scenarios/01-http:start       # deploy + verify
mise run //scenarios/20-http-grpc:start  # deploy + verify
```

Each `start` task runs `kubectl apply -k .`, then `verify`. Set `DELETE=1` to clean up after verification:

```sh
DELETE=1 mise run //scenarios/01-http:start   # deploy + verify + delete
```

List all available tasks:

```sh
mise tasks --all | grep scenarios
```

### Run all scenarios

```sh
mise run cluster:start
DELETE=1 mise run --continue-on-error --jobs 1 '//scenarios/...:start'
mise run cluster:delete
```

`--continue-on-error` ensures all 11 scenarios run even if some fail. `--jobs 1` keeps them sequential so namespaces don't collide.

### Version profiles

The default Cilium version and version-conditional flags are set in `mise.toml` `[env]`. To test against a different version, copy a version profile to `mise.local.toml`:

```sh
cp versions/1.19.1.toml mise.local.toml
mise run cluster:restart
DELETE=1 mise run --continue-on-error --jobs 1 '//scenarios/...:start' 2>&1 | tee run.log
mise run cluster:delete
rm mise.local.toml
```

Available profiles in `versions/`:

| File                | Cilium       | Gateway API | Notes                                 |
| ------------------- | ------------ | ----------- | ------------------------------------- |
| `1.19.1.toml`       | 1.19.1       | 1.4.1       | Oldest patch, regression baseline     |
| `1.19.3.toml`       | 1.19.3       | 1.4.1       | Matches `mise.toml` defaults          |
| `1.20.0-pre.1.toml` | 1.20.0-pre.1 | 1.5.1       | Pre-release                           |
| `branch.toml`       | local build  | 1.5.1       | Set `CILIUM_CHART_DIR` and image vars |

Each profile sets `CILIUM_VERSION`, `GATEWAY_API_VERSION`, and `X_*` env vars that control version-conditional verify behavior (expected status messages, known-bug skips).

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
DELETE=1 mise run --continue-on-error --jobs 1 '//scenarios/...:start' 2>&1 | tee run-branch.log
mise run cluster:delete
rm mise.local.toml
```

When `CILIUM_CHART_DIR` is set, the install tasks use the local chart path instead of `cilium/cilium --version`. When the image vars are set, they are passed as `--set image.override=…` / `--set operator.image.override=…` to Helm and pre-loaded into kind.

---

## Scenarios

Read each scenario README for the scenario-specific test flow.

### Numbering convention

| Range   | Category                        | Rule                                                               |
| ------- | ------------------------------- | ------------------------------------------------------------------ |
| `01–09` | Single protocol, single gateway | One route type, one gateway — vary the protocol or routing feature |
| `20–29` | Multi-protocol, single gateway  | Multiple route types on one gateway                                |
| `30–39` | Multi-gateway                   | Topology is the variable — multiple gateways                       |
| `40–49` | Policy & filters                | Kyverno, rate limiting, auth — the protocol is incidental          |
| `50+`   | Advanced topology               | ClusterMesh, federation, cross-cluster                             |

### Scenario table

| Scenario                                                                                                 | Scope                                                                                                       | Status                                                        |
| -------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| [`01-http`](scenarios/01-http/README.md)                                                                 | HTTPRoute, plaintext, one gateway, two backend namespaces                                                   | ✅ Pass                                                       |
| [`02-grpc`](scenarios/02-grpc/README.md)                                                                 | GRPCRoute, TLS termination at gateway, two backend namespaces                                               | ✅ Pass (status message [bug](#known-cilium-bugs) on ≤1.19.x) |
| [`03-https`](scenarios/03-https/README.md)                                                               | HTTPRoute over HTTPS, TLS termination at gateway, two backend namespaces                                    | ✅ Pass                                                       |
| [`04-mtls`](scenarios/04-mtls/README.md)                                                                 | TLSRoute passthrough, mTLS at backend, per-namespace PKI                                                    | ✅ Pass (status message [bug](#known-cilium-bugs) on ≤1.19.x) |
| `05-tcp`                                                                                                 | TCPRoute, no TLS                                                                                            | Planned                                                       |
| `06-http-header-routing`                                                                                 | HTTPRoute with header-based match rules                                                                     | Planned                                                       |
| `07-http-canary`                                                                                         | HTTPRoute with weighted backendRefs for traffic splitting                                                   | Planned                                                       |
| [`20-http-grpc`](scenarios/20-http-grpc/README.md)                                                       | HTTPS + gRPC on one gateway, separate ports, two namespaces                                                 | ✅ Pass                                                       |
| [`21-http-grpc-shared-port`](scenarios/21-http-grpc-shared-port/README.md)                               | HTTPRoute + GRPCRoute on one HTTPS listener (same port, different hostnames)                                | ✅ Pass                                                       |
| [`22-http-grpc-allowed-routes`](scenarios/22-http-grpc-allowed-routes/README.md)                         | HTTPS + gRPC on separate ports with per-listener `allowedRoutes.kinds`                                      | ⚠️ [Cilium bug](#known-cilium-bugs)                           |
| [`23-http-grpc-shared-port-allowed-routes`](scenarios/23-http-grpc-shared-port-allowed-routes/README.md) | HTTPRoute + GRPCRoute on one HTTPS listener with `allowedRoutes.kinds`                                      | ✅ Pass on ≥1.19.3 — [bug](#known-cilium-bugs) on ≤1.19.1     |
| [`24-http-grpc-same-hostname-split-ports`](scenarios/24-http-grpc-same-hostname-split-ports/README.md)   | HTTPRoute + GRPCRoute on same hostname, different ports (443 / 50051)                                       | ⚠️ [Cilium bug](#known-cilium-bugs)                           |
| [`25-https-tls-passthrough-same-port`](scenarios/25-https-tls-passthrough-same-port/README.md)           | HTTPS termination + TLS passthrough on same port 443, disjoint hostnames                                    | ✅ Pass                                                       |
| [`26-tlsroute-no-sectionname`](scenarios/26-tlsroute-no-sectionname/README.md)                           | TLSRoute without sectionName on mixed-listener Gateway (HTTP/HTTPS/TLS)                                     | ⚠️ [Cilium bug](#known-cilium-bugs)                           |
| [`27-allowed-routes-kinds-same-port`](scenarios/27-allowed-routes-kinds-same-port/README.md)             | 4 listeners (HTTP/HTTPS/gRPC/TLS), per-listener `allowedRoutes.kinds`, HTTP→HTTPS redirect, TLS passthrough | ⚠️ [Cilium bug](#known-cilium-bugs)                           |
| `30-multi-gateway-grpc`                                                                                  | Two gateways, each serving gRPC                                                                             | Planned                                                       |
| `31-multi-gateway-multi-protocol`                                                                        | Two gateways, mixed protocols                                                                               | Planned                                                       |
| `40-kyverno-route-governance`                                                                            | Mutating + validating policies for Gateway API route hygiene                                                | Planned                                                       |
| `41-http-rate-limit`                                                                                     | HTTPRoute with Envoy rate-limit filter                                                                      | Planned                                                       |
| `42-http-ext-auth`                                                                                       | HTTPRoute with OIDC / external authorization                                                                | Planned                                                       |
| `50-clustermesh-grpc`                                                                                    | Cross-cluster gRPC with Cilium ClusterMesh                                                                  | Planned                                                       |

### Known Cilium bugs

The verify scripts use version-conditional `X_*` env vars to skip or adjust assertions for known issues.

| Bug                                                                                   | Scenarios | Cilium issue                                            | Fix                                                   | Availability                                                    |
| ------------------------------------------------------------------------------------- | --------- | ------------------------------------------------------- | ----------------------------------------------------- | --------------------------------------------------------------- |
| `allowedRoutes.kinds` silently excludes GRPCRoute from Envoy config                   | 22, 23    | [#44824](https://github.com/cilium/cilium/issues/44824) | [#44826](https://github.com/cilium/cilium/pull/44826) | ≥1.19.3, ≥1.20.0                                                |
| GRPCRoute/TLSRoute status reports "Accepted HTTPRoute"                                | 02, 04    | [#43881](https://github.com/cilium/cilium/issues/43881) | [#44962](https://github.com/cilium/cilium/pull/44962) | ≥1.20.0 (not backported to 1.19.x)                              |
| `CheckGatewayRouteKindAllowed` overwrites Accepted condition across listeners         | 22, 27    | [#45559](https://github.com/cilium/cilium/issues/45559) | —                                                     | Broken on ≤1.19.3; verified fixed on fix/allowed-routes branch  |
| Same-hostname GRPCRoutes on split ports return 404                                    | 24        | [#44877](https://github.com/cilium/cilium/issues/44877) | [#44889](https://github.com/cilium/cilium/pull/44889) | Broken on ≤1.20.0-pre.1; verified fixed on #44889 branch build  |
| TLSRoute without sectionName creates duplicate FilterChains on mixed-listener Gateway | 26        | [#45050](https://github.com/cilium/cilium/issues/45050) | [#45371](https://github.com/cilium/cilium/pull/45371) | Broken on ≤1.19.3 and #44889 branch build (#45371 not included) |

### Test results by version

| Scenario                                | 1.19.1 | 1.19.3 | 1.20.0-pre.1 | #44889 branch | fix/allowed-routes |
| --------------------------------------- | :----: | :----: | :----------: | :-----------: | :----------------: |
| 01-http                                 |   ✅   |   ✅   |      ✅      |      ✅       |         ✅         |
| 02-grpc                                 |  ✅¹   |  ✅¹   |      ✅      |      ✅       |         ✅         |
| 03-https                                |   ✅   |   ✅   |      ✅      |      ✅       |         ✅         |
| 04-mtls                                 |  ✅¹   |  ✅¹   |      ✅      |      ✅       |         ✅         |
| 20-http-grpc                            |   ✅   |  ✅²   |      ✅      |      ✅       |        ❌²         |
| 21-http-grpc-shared-port                |   ✅   |   ✅   |      ✅      |      ✅       |         ✅         |
| 22-http-grpc-allowed-routes             |  ⏭️³   |  ⏭️³   |     ⏭️³      |      ⏭️³      |        ❌²         |
| 23-http-grpc-shared-port-allowed-routes |  ⏭️³   |   ✅   |      ✅      |      ✅       |         ✅         |
| 24-http-grpc-same-hostname-split-ports  |  ⏭️³   |  ⏭️³   |     ⏭️³      |      ✅⁵      |        ❌²         |
| 25-https-tls-passthrough-same-port      |   —    |   ✅   |      —       |      ✅       |         ✅         |
| 26-tlsroute-no-sectionname              |   —    |  ⏭️⁴   |      —       |      ❌⁶      |        ⏭️⁴         |
| 27-allowed-routes-kinds-same-port       |   —    |  ❌⁷   |      —       |       —       |        ✅⁸         |
| 35-tls-passthrough-same-hostname-split  |   —    |   —    |      —       |       —       |        ⏭️⁹         |
| 36-allowed-routes-namespaces            |   —    |   —    |      —       |       —       |         ✅         |

✅ = pass. ❌ = fail. ⏭️ = skipped by `skip_if`. — = not yet tested.
¹ Data plane passes; status message says "Accepted HTTPRoute" instead of correct route type.
² Transient `SSL_ERROR_SYSCALL` — Envoy listener timing; passes on retry.
³ Skipped; confirmed broken when run without skip — see [Known Cilium bugs](#known-cilium-bugs).
⁴ Skipped; confirmed broken (404 on HTTPS termination when TLSRoute omits sectionName) — see [#45050](https://github.com/cilium/cilium/issues/45050).
⁵ **Fixed by [#44889](https://github.com/cilium/cilium/pull/44889)** — gRPC traffic distributed 9/11 across both backends.
⁶ `SSL_ERROR_SYSCALL` — branch does not include [#45371](https://github.com/cilium/cilium/pull/45371) fix.
⁷ 5/6 routes rejected with `NotAllowedByListeners` — only the TLSRoute (targeting the last listener `tls-passthrough`, `kinds: [TLSRoute]`) is accepted. All 3 HTTPRoutes and 2 GRPCRoutes are rejected because `CheckGatewayRouteKindAllowed` evaluates all listeners globally and the last listener's `SetParentCondition` call overwrites the result. See [#45559](https://github.com/cilium/cilium/issues/45559).
⁸ **Fixed by `fix/allowed-routes` branch** — all 6 routes accepted (3 HTTPRoutes, 2 GRPCRoutes, 1 TLSRoute), HTTPS + gRPC + HTTP redirect + TLS passthrough data plane verified. Covers [community-reported variant](https://github.com/cilium/cilium/issues/45559#issuecomment-4302047885) (HTTP/HTTPS/TLS mixed listeners with implicit kinds).
⁹ Skipped; `SSL_ERROR_SYSCALL` on branch builds — likely same Envoy listener timing issue as ². See [#42898](https://github.com/cilium/cilium/issues/42898).

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
mise run //scenarios/01-http:delete           # delete a single scenario
mise run cluster:delete                       # delete the cluster (removes everything)
```
