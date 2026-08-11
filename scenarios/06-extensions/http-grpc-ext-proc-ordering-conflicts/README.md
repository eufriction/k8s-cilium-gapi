# `http-grpc-ext-proc-ordering-conflicts` - aggregate ordering conflicts

This scenario validates listener-wide `CiliumEnvoyExtProcFilter` ordering across
HTTPRoute and GRPCRoute declarations attached directly to a Gateway and through
an attached ListenerSet.

The routes are created in three precedence groups. Their constraints are:

1. older HTTPRoute: `B < C`;
2. compatible HTTPRoute: `A < B`;
3. newer HTTPRoute: `B < A`; and
4. newer GRPCRoute: `C < D < A`.

The first two declarations combine into `A, B, C`. Both newer declarations
conflict and lose their edges. `D` appears only in the losing GRPCRoute, but it
must remain once in the generated HCM chain, producing `A, B, C, D`.

## Resources

| Resource                                      | Namespace           | Purpose                                             |
| --------------------------------------------- | ------------------- | --------------------------------------------------- |
| `Gateway/ordering-gateway`                    | `ext-proc-ordering` | Primary aggregate domain                            |
| `ListenerSet/ordering-listeners`              | `ext-proc-ordering` | Adds a delegated listener to the primary Gateway    |
| `Gateway/ordering-other-gateway`              | `ext-proc-ordering` | Independent domain for parent and CEC isolation     |
| `HTTPRoute/00-b-before-c`                     | `ext-proc-ordering` | Oldest `B < C` constraint                           |
| `HTTPRoute/01-a-before-b`                     | `ext-proc-ordering` | Compatible `A < B` constraint                       |
| `HTTPRoute/http-reverse-conflict`             | `ext-proc-ordering` | Losing `B < A` constraint                           |
| `GRPCRoute/grpc-cycle-conflict`               | `ext-proc-ordering` | Losing `C < D < A` constraint with multiple parents |
| `CiliumEnvoyExtProcFilter/order-*`            | `ext-proc-ordering` | Filter nodes used by the ordering graph             |
| `Service/backend`, `Service/ext-proc-backend` | `ext-proc-ordering` | Resolvable control-plane references                 |

## Verification

What `verify.sh` checks:

1. Both Gateways and the ListenerSet are Accepted.
2. Route creation timestamps preserve the intended precedence groups.
3. The primary CEC orders filters as `A, B, C, D`; the isolated CEC contains
   only `C, D, A`.
4. Winning parents remain `Accepted/Accepted` and all valid parents report
   `ResolvedRefs=True`.
5. Losing HTTPRoute and GRPCRoute parents report
   `Accepted=True/OrderingConflict`.
6. Both the direct Gateway and attached ListenerSet ParentRefs receive the
   conflict, while the other Gateway remains `Accepted/Accepted`.
7. The rejected ParentRef remains `Accepted=False`; parent group, kind,
   namespace, section name, and port remain intact.
8. Duplicate model occurrences from multiple listeners and gRPC matches do not
   duplicate filters or constraints.
9. Conflict reasons clear after a declaration becomes compatible or the winning
   route is deleted.
10. The verifier restores all staged routes, including their creation-order
    groups, so standalone `:verify` runs remain repeatable.

## Prerequisites

This scenario requires Cilium with `CiliumEnvoyExtProcFilter` support,
`gatewayAPI.enableExtensionRefFilters=true`, and the Gateway API `ListenerSet`
CRD. No live backend pods are required because the scenario verifies status and
CEC output only.

Cilium `1.19.6` and `1.20.0` are skipped via `SCENARIO_SKIP_VERSIONS`.

## Run

```sh
mise run //scenarios/06-extensions/http-grpc-ext-proc-ordering-conflicts:start
```
