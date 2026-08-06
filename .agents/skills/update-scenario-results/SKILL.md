---
name: update-scenario-results
description: Updates Gateway API scenario results in k8s-cilium-gapi after LB or hostNetwork test runs, including README tables, known-bug notes, branch-build columns, and extension-ref validation.
---

# Update scenario results

Update `k8s-cilium-gapi` scenario status after a test run.

Prefer LB mode for results-table updates unless the user explicitly asks for `hostNetwork` mode.

Copyable progress tracker:

```md
Results update progress:

- [ ] Confirm branch and repo context
- [ ] Verify extension-ref settings if relevant
- [ ] Collect logs from the scenario run
- [ ] Parse PASS / FAIL / SKIP results
- [ ] Update README sections together
- [ ] Run formatting and diff checks
- [ ] Fix any validation issues and re-run checks
```

## 1. Confirm repo context

Run `git --no-pager status --short` in `k8s-cilium-gapi` before editing `README.md`.

If the result comes from local Cilium branch images, gather the base SHA from the `cilium` repo, not from `k8s-cilium-gapi`:

```sh
git --no-pager rev-parse --short origin/main
git --no-pager merge-base --short HEAD origin/main
git --no-pager log -1 --pretty='%h %s'
```

Use the `origin/main` or merge-base SHA for a branch column like `main (<sha>)`, for example `main (a1b2c3d)`.

## 2. Verify extension-ref settings when relevant

If the run includes ExtensionRef or `ext_proc` scenarios, verify:

- `config/values.cilium.yaml`
- `config/values.cilium.lb.yaml`

Both should contain:

```yaml
gatewayAPI:
  enableExtensionRefFilters: true
```

If you are validating an existing cluster, also check live values:

```sh
helm get values cilium -n kube-system --all -o yaml | grep -n 'gatewayAPI\|enableExtensionRefFilters\|enableAlpn'
kubectl -n kube-system get cm cilium-config -o yaml | grep -n 'enable-gateway-api-extension-ref-filters'
```

If `enable-gateway-api-extension-ref-filters` changed from `false` to `true`, restart the operator after `helm upgrade`:

```sh
kubectl rollout restart deployment/cilium-operator -n kube-system
kubectl rollout status deployment/cilium-operator -n kube-system --timeout=180s
```

## 3. Collect logs

Typical LB-mode startup:

```sh
mise run cluster:start --lb 2>&1 | tee logs/cluster-start-lb-<label>.log
```

Remind the user that `mise run cloud-provider-kind:start` must be running in another terminal.

For full results updates, prefer the fixtureless run when scenarios need per-scenario dependencies, for example `http-ext-proc-waf`:

```sh
mise run --continue-on-error --jobs 1 '//scenarios/...:start' --delete 2>&1 | tee logs/run-all-<label>.log
```

For a focused rerun:

```sh
mise run //scenarios/06-extensions/http-ext-proc-waf:start --delete 2>&1 | tee logs/run-http-ext-proc-waf-<label>.log
```

## 4. Parse results

Use the commands in `result-parsing.md`.

If a task exits nonzero without a `FAIL:` line, inspect the failing scenario block and record the real cause instead of inventing a `FAIL:` summary.

## 5. Update `README.md`

Update the scenario table, known-bug sections, test-results grid, and run notes together so they stay consistent.

Use the editorial rules in `readme-update-rules.md`.

## 6. Validate before responding

Run:

```sh
mise exec -- prettier --check README.md config/values.cilium.lb.yaml
git --no-pager diff --check -- README.md config/values.cilium.lb.yaml
git --no-pager status --short
```

If a validation command fails, fix the affected file and rerun the validation commands before responding.

## References

- Result parsing: `result-parsing.md`
- README update rules: `readme-update-rules.md`
