---
name: run-all-scenarios
description: Runs the full Gateway API scenario suite in k8s-cilium-gapi and summarizes PASS, FAIL, and SKIP results. Use when asked to run the complete suite, validate a Cilium version, or check whether all scenarios pass.
---

# Run All Scenarios

Run the full Gateway API scenario suite in `k8s-cilium-gapi`.

Follow cluster mode, version profile, and branch-build guidance in `k8s-cilium-gapi/README.md`.

Copyable progress tracker:

```md
Run progress:

- [ ] Verify cluster health
- [ ] Choose cluster mode
- [ ] Verify the shared-fixture safety invariant
- [ ] Run the full suite
- [ ] Summarize PASS / FAIL / SKIP counts
- [ ] Investigate any failures
- [ ] Re-run failing scenarios if needed
```

## 1. Verify prerequisites

Run from `k8s-cilium-gapi`:

```sh
kubectl get nodes -o wide
cilium status --wait-duration 10s --interactive=false
```

If no cluster exists, ask the user which mode to use:

- `hostNetwork`: `mise run cluster:start`
- `LoadBalancer`: `mise run cluster:start --lb`

In `LoadBalancer` mode, remind the user that `mise run cloud-provider-kind:start` must be running in another terminal.

## 2. Protect the shared fixture

`scenarios:run-all` sets `FIXTURE_DEPLOYED=true`. In this mode, each scenario must deploy and delete only its scenario-owned resources through `gateway/kustomization.yaml`. The shared `gateway-system` namespace comes from `config/fixture` and must remain until the suite finishes. The full scenario kustomization may still include that namespace for standalone runs, so do not use a standalone `:start --delete` command while the shared fixture is active.

Before adding or debugging a scenario in fixture mode, render its gateway overlay and confirm that it does not contain `Namespace/gateway-system`:

```sh
kubectl kustomize scenarios/<group>/<name>/gateway/ --load-restrictor=LoadRestrictionsNone \
  | kubectl get -f - --ignore-not-found \
    -o custom-columns='KIND:.kind,NAMESPACE:.metadata.namespace,NAME:.metadata.name'
```

If the scenario has no `gateway/` directory, add a fixture-only overlay containing only the scenario-owned Gateway, Route, filter, certificate, and related resources before including it in `run-all`.

The fixture is intentionally deleted at the end of the full suite, so checking `gateway-system` after `scenarios:run-all` is expected to return `NotFound`. For a focused safety check, use the fixture-mode command in `run-scenarios` and verify the namespace before and after the scenario cleanup.

## 3. Run the full suite

Default to the shared-fixture path because it is the fastest supported full-suite workflow:

```sh
mise run scenarios:run-all
```

Use the fixtureless fallback only when a scenario needs per-scenario resources that are not part of the shared fixture, or when the user explicitly asks for the slower per-scenario run:

```sh
mise run --continue-on-error --jobs 1 '//scenarios/...:start' --delete 2>&1 | tee run.log
```

- `--continue-on-error` keeps the run going after failures.
- `--jobs 1` keeps scenarios sequential so namespaces do not collide.
- `--delete` cleans up each scenario after verification.
- `tee run.log` keeps a log for later analysis.
- `bash scripts/summarize-results.sh --results run-all-results.tsv run.log` writes the machine-readable result file.

Set `timeout_ms` to at least `1800000` for full-suite commands.

## 4. Summarize results

`mise run scenarios:run-all` writes `run-all-results.tsv` automatically. For the fixtureless workflow, generate the same file explicitly:

```sh
bash scripts/summarize-results.sh --results run-all-results.tsv run.log
```

Read the TSV result file instead of parsing the log. It contains:

- `version<TAB><Cilium version>`
- `status<TAB>PASS|FAIL`
- `counts<TAB>pass=<n><TAB>fail=<n><TAB>skip=<n>`
- one `scenario` row per scenario with its status, failure detail, and rerun command

Present the PASS, FAIL, and SKIP counts, every failed scenario, its failure detail, and its copy-pasteable rerun command.

## 5. Re-run failing scenarios

Use a concrete scenario path when narrowing down a failure. Example:

```sh
mise run //scenarios/02-http-routing/redirect:start --delete
```

If the failure needs deeper investigation, use the checks in `troubleshooting.md`.

## References

- Failure investigation: `troubleshooting.md`
- Timeout and version knobs: `reference.md`
