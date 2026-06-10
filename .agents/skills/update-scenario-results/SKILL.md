---
name: update-scenario-results
description: Update Gateway API scenario status and README test-result tables after running LB or hostNetwork scenario tests, including log capture, Cilium branch SHA handling, known bug updates, and extension-ref configuration checks.
---

# Update scenario results

<!-- vale Vale.Terms = NO -->

Use this skill when updating `k8s-cilium-gapi` scenario status after a test run, especially when the user asks to update `README.md`, record results for a Cilium branch build, validate a failed scenario, or refresh the Known Cilium bugs section.

## Source files

- Main status document: `k8s-cilium-gapi/README.md`
- Default Helm values: `k8s-cilium-gapi/config/values.cilium.yaml`
- LB-mode Helm values: `k8s-cilium-gapi/config/values.cilium.lb.yaml`
- Branch-build profile: `k8s-cilium-gapi/mise.local.toml`
- Scenario logs: `k8s-cilium-gapi/logs/`
- Scenario tasks/manifests: `k8s-cilium-gapi/scenarios/<group>/<scenario>/`

## Before running tests

1. Confirm the active Cilium source SHA when recording a branch-build result:

   ```sh
   git --no-pager rev-parse --short origin/main
   git --no-pager merge-base --short HEAD origin/main
   git --no-pager log -1 --pretty='%h %s'
   ```

   Use the Cilium `origin/main` or merge-base SHA for a column labeled like `main (<sha>)` when the test result represents a branch build based on main.

2. Verify the `k8s-cilium-gapi` branch and current changes:

   ```sh
   git --no-pager status --short
   ```

3. For LB-mode runs that include ExtensionRef/ext_proc scenarios, ensure `config/values.cilium.lb.yaml` contains:

   ```yaml
   gatewayAPI:
     enableExtensionRefFilters: true
   ```

   HostNetwork mode already uses `config/values.cilium.yaml`, which should also contain this setting.

4. If validating an existing cluster, confirm the live Helm/ConfigMap state:

   ```sh
   helm get values cilium -n kube-system --all -o yaml | grep -n 'gatewayAPI\|enableExtensionRefFilters\|enableAlpn'
   kubectl -n kube-system get cm cilium-config -o yaml | grep -n 'enable-gateway-api-extension-ref-filters'
   ```

   If `enable-gateway-api-extension-ref-filters` changes from `false` to `true`, restart `cilium-operator` after `helm upgrade` because the operator may keep the old value in memory:

   ```sh
   kubectl rollout restart deployment/cilium-operator -n kube-system
   kubectl rollout status deployment/cilium-operator -n kube-system --timeout=180s
   ```

## Running scenarios with logs

Prefer LB mode for results table updates unless the user explicitly requests hostNetwork:

```sh
mise run cluster:start:lb 2>&1 | tee logs/cluster-start-lb-<label>.log
# cloud-provider-kind must be running in another terminal:
mise run cloud-provider-kind:start
```

Verify health before running scenarios:

```sh
kubectl get nodes -o wide
cilium status --wait-duration 10s --interactive=false
```

Run all scenarios without the shared fixture when validating scenarios that deploy extra per-scenario resources such as `http-ext-proc-waf`:

```sh
mise run --continue-on-error --jobs 1 '//scenarios/...:start' --delete 2>&1 | tee logs/run-all-<label>.log
```

The shared fixture task is faster, but can be invalid for scenarios whose dependencies are not part of the fixture. For example, `http-ext-proc-waf` needs its own `coraza-waf-extproc` deployment, so a fixture-only run can produce a false failure.

For a focused rerun:

```sh
mise run //scenarios/<group>/<scenario>:start --delete 2>&1 | tee logs/run-<scenario>-<label>.log
```

## Parsing results

Summarize logs with:

```sh
grep -c '^PASS:' logs/<run>.log
grep -c '^FAIL:' logs/<run>.log
grep -c '^SKIP:' logs/<run>.log
grep '^FAIL:' logs/<run>.log
```

Important: a task can exit nonzero without printing a `FAIL:` line if a `kubectl wait` or shell command times out. Inspect the scenario block around the failed task name and record the real cause, for example:

```text
error: timed out waiting for the condition on httproutes/waf-route
```

If a route fails because `ResolvedRefs=False`, inspect status:

```sh
kubectl get httproute <name> -n <namespace> -o yaml
```

For ExtensionRef failures, look for messages such as `ExtensionRef filters are disabled`, which usually indicates missing `gatewayAPI.enableExtensionRefFilters=true` or an operator restart is needed after changing it.

## Updating `README.md`

Update these sections together so they remain consistent:

1. **Scenario table**
   - Mark stable scenario outcomes as `✅ Pass`.
   - Use precise notes for branch-only or known-failure cases.
   - If a formerly failing scenario now passes on the latest branch build, update the status.

2. **Known Cilium bugs**
   - Move bugs fixed by merged PRs out of **Open bugs** and into **Fixed (merged, not yet released)** unless they are in a released version.
   - Keep genuinely open issues in **Open bugs**, but update their status if the latest branch run no longer reproduces them.
   - Do not claim an issue is fixed upstream solely because one local branch run passes; phrase it as “not reproduced by latest branch run” unless the fixing PR is known.

3. **Test results by version**
   - Use a branch-build column like `main (<sha>)` for results from local Cilium branch images based on main.
   - If replacing an older branch column (for example `main + #44889`) after the PR merges, rename it to `main (<sha>)` and use the latest test results for that branch run.
   - Add missing scenario rows when scenarios have been tested but are absent from the grid.
   - Keep result symbols consistent with the legend.

4. **Legend and run notes**
   - Keep the legend stable and limited to symbol meanings. Do not add volatile context such as SHAs, branch names, log paths, run dates, or per-run notes to the legend. Only change it when a result symbol is added, removed, or its meaning changes. Recommended wording:

     ```md
     **Legend:** ✅ = scenario passed, ❌ = scenario failed, ⏭️ = intentionally skipped by version guard (known bug or unsupported feature), · = no result recorded.
     ```

   - Put volatile run context in column titles and run notes instead. Mention LB mode and log paths used to collect the latest branch column in a separate `**Run notes:**` paragraph.

## Validation before final response

Run formatting and whitespace checks:

```sh
mise exec -- prettier --check README.md config/values.cilium.lb.yaml
git --no-pager diff --check -- README.md config/values.cilium.lb.yaml
```

Check status:

```sh
git --no-pager status --short
```

In the final response, include:

- Files changed.
- Logs used for results.
- Commands run and pass/fail outcome.
- Any cluster state left running, if relevant.
