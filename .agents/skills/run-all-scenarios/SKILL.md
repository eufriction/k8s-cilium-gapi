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

## 2. Run the full suite

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

## 3. Summarize results

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

## 4. Re-run failing scenarios

Use a concrete scenario path when narrowing down a failure. Example:

```sh
mise run //scenarios/02-http-routing/redirect:start --delete
```

If the failure needs deeper investigation, use the checks in `troubleshooting.md`.

## References

- Failure investigation: `troubleshooting.md`
- Timeout and version knobs: `reference.md`
