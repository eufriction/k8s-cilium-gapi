# Result parsing

Use this file after a scenario run has produced one or more logs in `logs/`.

## Count PASS, FAIL, and SKIP lines

```sh
grep -c '^PASS:' logs/<run>.log
grep -c '^FAIL:' logs/<run>.log
grep -c '^SKIP:' logs/<run>.log
grep '^FAIL:' logs/<run>.log
```

## Important interpretation rules

- A task can exit nonzero without printing a `FAIL:` line.
- When that happens, inspect the scenario block around the failed task name and capture the real cause.
- Example:

```text
error: timed out waiting for the condition on httproutes/waf-route
```

## Route-status follow-up

If a route fails because `ResolvedRefs=False`, inspect status directly:

```sh
kubectl get httproute <name> -n <namespace> -o yaml
```

## ExtensionRef follow-up

If you see a message like `ExtensionRef filters are disabled`, check:

- `gatewayAPI.enableExtensionRefFilters=true` in the relevant values file
- whether `cilium-operator` needs a restart after the value changed
