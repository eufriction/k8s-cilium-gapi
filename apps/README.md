# App Bases

`apps/` contains reusable, namespace-agnostic app bases.

Rules:

- One app base per directory.
- No `Namespace` resources in `apps/`.
- No Gateway API resources in `apps/`.
- No hardcoded `metadata.namespace` in app manifests.
- Keep the numeric filename convention:
  - `10-*` for the workload object
  - `20-*` for the Service if the app needs one
  - `kustomization.yaml` in every app base

Conventions:

- Use `Pod` for disposable demo clients or very small single-instance workloads.
- Use `Deployment` when rollout behavior, restart semantics, or scaling are part of what you want to test.
- Keep each app base small enough that a scenario overlay only needs to set namespace and occasional tiny patches.
