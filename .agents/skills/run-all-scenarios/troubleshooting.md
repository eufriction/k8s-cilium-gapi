# Troubleshooting run-all failures

Use this file when the full-suite run reports one or more failures.

## Investigation order

1. **Check whether the scenario should have been skipped**

   Example:

   ```sh
   grep 'SCENARIO_SKIP_VERSIONS' scenarios/02-http-routing/redirect/mise.toml
   ```

   Generic form:

   ```sh
   grep 'SCENARIO_SKIP_VERSIONS' scenarios/<group>/<scenario>/mise.toml
   ```

   If the active `CILIUM_VERSION` should be in the skip list but was not skipped, treat that as a scenario config bug.

2. **Check pod readiness**

   ```sh
   kubectl get pods -A | grep -v Running
   ```

   Look for `CrashLoopBackOff`, `Pending`, or `Init` states.

3. **Check Cilium health**

   ```sh
   cilium status --interactive=false
   kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium
   kubectl logs -n kube-system -l app.kubernetes.io/name=cilium --tail=50 | grep -i 'panic\|fatal\|error'
   ```

4. **Check Gateway and Route status**

   ```sh
   kubectl get gateways -A -o wide
   kubectl get httproutes,grpcroutes,tlsroutes -A
   ```

   Look for Gateways not reaching `Programmed=True` or Routes not reaching `Accepted=True`.

5. **Check CiliumEnvoyConfig objects**

   ```sh
   kubectl get ciliumenvoyconfigs -A
   ```

   Missing CECs usually mean the operator did not reconcile the Gateway.

6. **Check LoadBalancer readiness when using LB mode**

   ```sh
   kubectl get svc -A | grep LoadBalancer
   docker ps | grep kindccm
   ```

   If `EXTERNAL-IP` stays `<pending>`, `cloud-provider-kind` is probably missing or not ready.

7. **Re-run one failing scenario**

   Example:

   ```sh
   mise run //scenarios/02-http-routing/redirect:start --delete
   ```
