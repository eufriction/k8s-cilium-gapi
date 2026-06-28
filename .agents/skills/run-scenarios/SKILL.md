---
name: run-scenarios
description: Runs one or more Gateway API scenarios in k8s-cilium-gapi and helps debug a failing scenario. Use when asked to run a single scenario, a scenario group, or a focused repro.
---

# Run Specific Scenarios

Run individual or grouped Gateway API scenarios in `k8s-cilium-gapi`.

Follow cluster mode and version profile guidance in `k8s-cilium-gapi/README.md`.

Copyable progress tracker:

```md
Scenario progress:

- [ ] Verify cluster health
- [ ] Choose the scenario path or group
- [ ] Run `:start`, `:verify`, or `:delete`
- [ ] Inspect failures if any
- [ ] Re-run verification after fixes
- [ ] Clean up resources if needed
```

## 1. Verify prerequisites

Run from `k8s-cilium-gapi`:

```sh
kubectl get nodes -o wide
cilium status --wait-duration 10s --interactive=false
```

## 2. Use the scenario path syntax

Scenarios use mise monorepo paths:

```text
//scenarios/<group>/<name>:<action>
```

Actions:

- `:start` — deploy manifests, run verification, and optionally delete resources
- `:verify` — run `verify.sh` only; the scenario must already be deployed
- `:delete` — remove scenario resources

## 3. Run scenarios

Run one scenario:

```sh
mise run //scenarios/01-basic/http:start --delete
```

Omit `--delete` when you want to leave resources in place for inspection.

Run a whole group:

```sh
mise run --continue-on-error --jobs 1 '//scenarios/03-multi-listener/...:start' --delete
```

Run multiple specific scenarios:

```sh
mise run --continue-on-error --jobs 1 \
  //scenarios/01-basic/http:start \
  //scenarios/01-basic/grpc:start \
  //scenarios/02-http-routing/redirect:start \
  --delete
```

List the available scenario tasks dynamically instead of relying on a hardcoded inventory:

```sh
mise tasks --all | grep scenarios
```

## 4. Re-verify after a suspected fix

After changing cluster state or manifests, prefer a focused verify first:

```sh
mise run //scenarios/01-basic/http:verify
```

If the scenario is no longer deployed, rerun `:start` instead.

## References

- Failure investigation: `troubleshooting.md`
