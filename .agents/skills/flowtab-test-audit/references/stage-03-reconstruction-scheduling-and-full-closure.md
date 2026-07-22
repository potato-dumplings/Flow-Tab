# Stage 03: Reconstruction Scheduling And Full Closure

## Outcome

Schedule every Required slice through committed C1 anchors and establish a committed C2 for one final current test-asset set and same-candidate full-system validation.

## Entry

- Require the current committed C0 and reproducible rollback anchor, production snapshot, shared-rule snapshot, boundary hash, validation plan, slice queue and dependency DAG.
- Validate every completed slice against its committed C1, chained validation-plan input/output hashes, selected row IDs and hashes, generated asset paths, delta hash and current upstream inputs.
- Inherit the Campaign `commit_policy`, preserve unrelated user changes and resolve dirty-path ownership.
- Ensure at least one slice is entry-ready, or every Required slice is ready for final closure.

## Work

1. Select one entry-ready slice by prerequisites, invalidations, risk, dependency depth, consumer impact and stable slice ID.
2. Invoke Stage 02 and wait for its committed C1.
3. Regenerate C1's selected canonical validation-plan references, validate its complete plan-hash transition and exact generated file delta, then recompute the queue, consumers, interactions and invalidations.
4. Run a Wave combination check after high-fan-out, shared TestingSupport, Fixture, Runner, runtime, persistence or lifecycle assets change, after the last Required slice in a dependency level and after risk-significant cumulative deltas.
5. Turn every Wave finding into a new or reopened Stage 02 slice. Continue until every Required slice has a current C1.
6. Freeze one final candidate tree. Run the canonical full index and write `.build-local/test-audit/rebuild/TEST_ASSET_LEDGER.jsonl`.
7. Run canonical `assert-boundary-closure` and write `.build-local/test-audit/rebuild/BOUNDARY_CLOSURE.json`. Reconcile the final ledger with the boundary manifest, C0 and the ordered C1 delta hashes.
8. Run every Required static/build, Unit, Behavior, Mock UI, real-topology UI and Pressure row against the same candidate. Write final observations beneath the transient root.
9. Create `docs/test-audit/C2_HANDOFF.json` with C0, ordered C1 anchors, final validation-plan and ledger hashes, candidate identity, Wave results, full-validation evidence, closure conclusion, remaining items, exact closure file set and rollback order.

Route newly discovered protected behavior or Oracle semantics through a new or reopened Stage 02 slice.

## Completion Eligibility

- Every Required slice has a valid committed C1 and resolved dependency and interaction invalidations.
- The final ledger passes canonical boundary closure and contains the complete current asset candidate derived by this reconstruction.
- Every Required plan row maps to current executable assets and current observations.
- Every Required row ran against the same frozen candidate and artifact identities.
- Execution, Reliability, Architecture and Pressure close with current evidence or a risk-calibrated not-applicable result.
- Required gaps, unexpected Skip, open Flake and active Required blockers are cleared.
- C2 and its exact Stage-owned file set are frozen.

## Commit

- Commit final integration changes, current anchors and C2. Keep the full ledger and execution detail beneath `.build-local`.
- Apply the shared policy with title `test-audit(rebuild): complete FlowTab test-asset reconstruction`.
- Use the resulting commit as the current C2 anchor.

## Blocked And Resume

- Continue every entry-ready independent branch while one slice is blocked.
- Enter Campaign-level `BLOCKED` only when no safe branch remains runnable.
- Route Wave and full-validation failures through a new or reopened Stage 02 slice.
- Retain valid same-candidate evidence when a Required environment is unavailable and resume at the affected row.
- Apply engineering's role-based drift mapping when source, rules, boundary, plan, candidate, Runner or environment changes.
- Preserve an eligible candidate after a Commit failure and resume at Commit while its parent and exact file set remain current.
