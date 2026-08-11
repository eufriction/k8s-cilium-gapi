# `gamma-ext-proc-ordering-conflicts` - per-Service ordering status

This scenario validates aggregate `CiliumEnvoyExtProcFilter` ordering for GAMMA
HTTPRoute and GRPCRoute resources with multiple source-Service parents.

An older HTTPRoute attached only to `Service/source-a` declares `A < B`. Newer
HTTPRoute and GRPCRoute resources attach to both `source-a` and `source-b` and
declare `B < A`.

The expected result is scoped independently for each source Service:

- `source-a` keeps `A, B` and both newer routes report
  `Accepted=True/OrderingConflict` only for that parent;
- `source-b` selects `B, A` and both routes remain `Accepted/Accepted`; and
- each source Service owns a separate CiliumEnvoyConfig containing only its
  selected aggregate.

## Resources

| Resource                                         | Namespace        | Purpose                                          |
| ------------------------------------------------ | ---------------- | ------------------------------------------------ |
| `Service/source-a`                               | `ext-proc-gamma` | GAMMA source with the older winning declaration  |
| `Service/source-b`                               | `ext-proc-gamma` | Independent GAMMA source without that constraint |
| `Service/backend`, `Service/ext-proc-backend`    | `ext-proc-gamma` | Resolvable control-plane references              |
| `HTTPRoute/00-source-a-foundation`               | `ext-proc-gamma` | Source-A-only `A < B` constraint                 |
| `HTTPRoute/http-multi-parent-conflict`           | `ext-proc-gamma` | Multi-parent `B < A` declaration                 |
| `GRPCRoute/grpc-multi-parent-conflict`           | `ext-proc-gamma` | Multi-parent `B < A` declaration                 |
| `CiliumEnvoyExtProcFilter/order-a` and `order-b` | `ext-proc-gamma` | Filter nodes used by both Service aggregates     |

## Verification

What `verify.sh` checks:

1. The source-A foundation route has creation-time precedence.
2. `CEC/source-a` orders filters as `A, B`, while `CEC/source-b` independently
   orders them as `B, A`.
3. The source-A parent on both newer routes reports
   `Accepted=True/OrderingConflict`.
4. The source-B parent remains `Accepted/Accepted` on both route kinds.
5. Every asserted parent preserves its namespace and port and reports
   `ResolvedRefs=True`.
6. Removing the source-A winner clears only its stale conflict status and makes
   both CECs converge on `B, A`.
7. The verifier restores the staged creation order so standalone `:verify` runs
   remain repeatable.

The separate CEC checks catch ingestion that accidentally includes another
ParentRef's source Service in the CEC currently being reconciled.

## Prerequisites

This scenario requires Cilium with `CiliumEnvoyExtProcFilter` support,
`gatewayAPI.enableExtensionRefFilters=true`, and GAMMA support. No live backend
pods are required because the scenario verifies status and CEC output only.

Cilium `1.19.6` and `1.20.0` are skipped via `SCENARIO_SKIP_VERSIONS`.

## Run

```sh
mise run //scenarios/06-extensions/gamma-ext-proc-ordering-conflicts:start
```
