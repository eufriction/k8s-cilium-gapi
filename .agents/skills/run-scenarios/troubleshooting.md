# Troubleshooting scenario runs

Use this file when a single scenario or small scenario set fails.

Copyable troubleshooting tracker:

```md
Troubleshooting progress:

- [ ] Re-run without `--delete` if inspection is needed
- [ ] Check pods, Gateways, and Routes
- [ ] Check Gateway and Route conditions
- [ ] Check CiliumEnvoyConfig state
- [ ] Check Cilium agent logs
- [ ] Run `:verify` again after a fix
- [ ] Delete resources after inspection
```

## Investigation flow

### 1. Re-run without delete when you need live state

```sh
mise run //scenarios/02-http-routing/redirect:start
```

### 2. Check resource status

```sh
kubectl get pods -A | grep -v Running
kubectl get gateways -A -o wide
kubectl get httproutes,grpcroutes,tlsroutes -A
```

### 3. Check Gateway conditions

Concrete example:

```sh
kubectl describe gateway -n gateway-system same-namespace
```

Look for `Programmed=True` and `Accepted=True`.

### 4. Check Route conditions

Concrete example:

```sh
kubectl describe httproute -n same-namespace backend-v1
```

Look for `Accepted=True` and `parentRef` status. Important messages include:

- `Accepted HTTPRoute`, `Accepted GRPCRoute`, `Accepted TLSRoute`
- `NotAllowedByListeners`

### 5. Check CiliumEnvoyConfig state

```sh
kubectl get cec -A
kubectl describe cec -n gateway-system cilium-gateway-same-namespace
```

If no CEC exists for the Gateway, the operator probably did not produce Envoy config.

### 6. Check listener readiness and LB state

```sh
kubectl get svc -n gateway-system
```

If you are in LB mode and the service shows `<pending>`:

```sh
docker ps | grep kindccm
```

### 7. Check Cilium agent logs

```sh
kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium
kubectl logs -n kube-system -l app.kubernetes.io/name=cilium --tail=30 | grep -i 'panic\|fatal\|level=error'
```

### 8. Run the verify script directly

Run from `k8s-cilium-gapi`.

This uses `sh -c` so the directory change and `REPO_ROOT` lookup happen in one shell invocation:

```sh
sh -c 'cd scenarios/02-http-routing/redirect && REPO_ROOT="$(git rev-parse --show-toplevel)" ./verify.sh "$REPO_ROOT/lib"'
```

### 9. Re-run verification, then clean up

```sh
mise run //scenarios/02-http-routing/redirect:verify
mise run //scenarios/02-http-routing/redirect:delete
```

## Common failure patterns

| Symptom                              | Likely cause                                 | Check                                          |
| ------------------------------------ | -------------------------------------------- | ---------------------------------------------- |
| `FAIL: ... missing header`           | ext-proc or filter wiring is missing         | CEC state and extension-ref config             |
| `FAIL: ... 404`                      | Route did not attach to the listener         | Route `Accepted` condition and `allowedRoutes` |
| `FAIL: ... connection refused`       | Listener or service port is not ready        | Gateway status and LB service state            |
| `SKIP: known broken on Cilium X.Y.Z` | Version guard fired                          | Scenario `SCENARIO_SKIP_VERSIONS`              |
| Cilium pod `CrashLoopBackOff`        | Agent crash during reconciliation or cleanup | Agent logs                                     |
