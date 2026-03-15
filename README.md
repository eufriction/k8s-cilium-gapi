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
mise run scenario:00:start
mise run scenario:00:verify
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

## Repo Model

- `apps/` contains reusable, namespace-agnostic app bases.
- `scenarios/` contains namespaces, app instances, and Gateway API resources.
- App-base conventions live in [`apps/README.md`](apps/README.md).

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
mise run scenario:00:delete
mise run cluster:delete
```
