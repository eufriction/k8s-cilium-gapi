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

Make sure to activate `mise` in your shell so the `mise run ...` tasks can load the right tools. Don’t skip this. Follow the official `mise activate` instructions for your shell:

- [mise activate documentation](https://mise.jdx.dev/cli/activate.html)

After adding the activation line, restart your shell or open a new terminal.

#### Set a GitHub token to avoid rate limits (recommended)

When `mise` installs tools hosted on GitHub, unauthenticated requests can hit GitHub API rate limits. Create a personal access token (no scopes needed for public tools) and set it for this project with `mise set --prompt`. See the GitHub token creation guide or go directly to the token creation page:

- https://docs.github.com/articles/creating-an-oauth-token-for-command-line-use
- https://github.com/settings/tokens/new

Set the token interactively:

```sh
mise set --prompt GITHUB_TOKEN
```

Avoid setting the token using `export GITHUB_TOKEN=token` or `mise set GITHUB_TOKEN` as that stores the token the history of your shell.

### Run the demo

#### Start the cluster

```sh
mise run cluster:start
```

This creates a `kind` cluster and installs Cilium in kube-proxy-free mode with Hubble observability.

#### Verify the cluster is healthy

_This is already done as part of `mise run cluster:start`. Instruction left here for reference._

```sh
mise run cluster:verify
```

#### Start the first scenario

```sh
mise run scenario:01:start
mise run scenario:01:verify
```

This deploys one `gateway-system` namespace with the Gateway, one `client` namespace with a `netshoot-client` pod, and two backend namespaces that both reuse the same `backend-http` app base:

| Pod               | Namespace   | Role                     |
| ----------------- | ----------- | ------------------------ |
| `netshoot-client` | `client`    | Interactive debug client |
| `api`             | `backend-a` | A `httpbin` container    |
| `api`             | `backend-b` | A `httpbin` container    |

Test the two HTTPRoutes from your machine:

```sh
curl -i -H 'Host: backend-a.example.test' http://localhost/headers
curl -i -H 'Host: backend-b.example.test' http://localhost/headers
```

---

## Scenarios

Read each scenario README for the scenario-specific test flow.

### Numbering convention

Scenarios use a numbered-tier system. The prefix tells you the category at a glance; the slug tells you the content.

| Range   | Category                        | Rule                                                               |
| ------- | ------------------------------- | ------------------------------------------------------------------ |
| `01–09` | Single protocol, single gateway | One route type, one gateway — vary the protocol or routing feature |
| `20–29` | Multi-protocol, single gateway  | Multiple route types on one gateway                                |
| `30–39` | Multi-gateway                   | Topology is the variable — multiple gateways                       |
| `40–49` | Policy & filters                | Kyverno, rate limiting, auth — the protocol is incidental          |
| `50+`   | Advanced topology               | ClusterMesh, federation, cross-cluster                             |

Gap numbering leaves room for insertion without renaming existing scenarios.

### Scenario table

| Scenario                                           | Scope                                                          | Status  |
| -------------------------------------------------- | -------------------------------------------------------------- | ------- |
| [`01-http`](scenarios/01-http/README.md)           | HTTPRoute, plaintext, one gateway, two backend namespaces      | ✅ Done |
| [`02-grpc`](scenarios/02-grpc/README.md)           | GRPCRoute, TLS termination at gateway, two backend namespaces  | ✅ Done |
| `03-https`                                         | HTTPRoute over HTTPS, TLS termination at gateway               | Planned |
| [`04-mtls`](scenarios/04-mtls/README.md)           | TLSRoute passthrough, mTLS at backend, per-namespace PKI       | ✅ Done |
| `05-tcp`                                           | TCPRoute, no TLS                                               | Planned |
| `06-http-header-routing`                           | HTTPRoute with header-based match rules                        | Planned |
| `07-http-canary`                                   | HTTPRoute with weighted backendRefs for traffic splitting      | Planned |
| [`20-http-grpc`](scenarios/20-http-grpc/README.md) | HTTPS + gRPC on one gateway, four routes across two namespaces | ✅ Done |
| `21-http-grpc-mtls`                                | HTTP, HTTPS, mTLS, and gRPC on one gateway                     | Planned |
| `30-multi-gateway-grpc`                            | Two gateways, each serving gRPC                                | Planned |
| `31-multi-gateway-multi-protocol`                  | Two gateways, mixed protocols                                  | Planned |
| `40-kyverno-route-mutation`                        | Kyverno policy injects or mutates routes automatically         | Planned |
| `41-http-rate-limit`                               | HTTPRoute with Envoy rate-limit filter                         | Planned |
| `42-http-ext-auth`                                 | HTTPRoute with OIDC / external authorization                   | Planned |
| `50-clustermesh-grpc`                              | Cross-cluster gRPC with Cilium ClusterMesh                     | Planned |

## Repo Model

- `apps/` contains reusable, namespace-agnostic app bases.
- `scenarios/` contains namespaces, app instances, and Gateway API resources.
- App-base conventions live in [`apps/README.md`](apps/README.md).

## TLS Foundation

TLS-focused scenarios use `cert-manager`, but it is intentionally not part of `mise run cluster:start`.

Install it only when a scenario needs certificates:

```sh
mise run cert-manager:install
mise run cert-manager:verify
```

The self-signed certificate pattern for this repo lives in [`docs/tls-selfsigned.md`](docs/tls-selfsigned.md).

Gateway API CRDs are installed by the repo tasks before Cilium is installed. This repo now uses the Gateway API `experimental` CRD bundle at `v1.5.0`, because current Cilium Gateway behavior can log `v1alpha2.TLSRouteList` registration errors when only the `standard` bundle is installed.

For local TLS and gRPC checks in this repo, use insecure client flags against the self-signed certificates:

```sh
curl -k https://...
grpcurl -insecure ...
```

## Policy Foundation

Kyverno is also optional and is intentionally not part of `mise run cluster:start` because no current scenario depends on it yet.

Install it only when a scenario or experiment needs policy enforcement:

```sh
mise run kyverno:install
mise run kyverno:verify
mise run kyverno:delete
```

---

## Observing with Hubble

Open the Hubble UI to watch network flows in real time as you run each scenario:

```sh
cilium hubble ui
```

Or observe from the command line:

```sh
cilium hubble port-forward &
hubble observe --namespace client --follow
hubble observe --namespace backend-a --follow
hubble observe --namespace backend-b --follow
```

---

### Optional: `k9s`

`k9s` is a terminal UI for browsing and managing Kubernetes resources. Start it with:

```sh
k9s
```

Basic navigation:

- Use `:` to open the command bar, then type a resource (for example, `pods`, `ns`, `deploy`) and press Enter.
- Use `j/k` (or arrow keys) to move, `Enter` to drill in, and `Esc` to go back.
- Press `/` to filter the current list.

---

## Clean up

```sh
mise run scenario:01:delete
mise run cluster:delete
```
