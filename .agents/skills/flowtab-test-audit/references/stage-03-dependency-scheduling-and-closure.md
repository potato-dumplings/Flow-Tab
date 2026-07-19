# Stage 03: Dependency Scheduling and Full Closure

## Outcome

Schedule all Required dependency slices through committed C1 anchors, detect integration problems through risk-driven Wave checks, and establish a committed C2 anchor from one same-candidate full-system validation.

## Entry

- Require a current committed C0 anchor and reconstructible asset ledger, baseline, slice queue, dependency DAG and interaction information.
- Validate every existing completed slice against its committed C1 anchor and current upstream and interaction inputs.
- Inherit the campaign `commit_policy`, establish the target branch, preserve user-owned changes, and resolve dirty-path ownership.
- Ensure Stage 02 is available for one-slice execution and that at least one slice is entry-ready or all Required slices are ready for final closure.

## Work

1. Select one entry-ready slice by confirmed prerequisites, active blockers, interaction invalidations, priority, dependency depth, consumer impact, risk and stable slice ID.
2. Invoke Stage 02 for that slice and wait for its committed C1 anchor.
3. Validate the C1 handoff and exact delta. Recompute the slice queue, direct consumers, interaction peers, dependency invalidations and interaction invalidations before selecting the next write-producing slice.
4. Run a Wave combination check after a high-fan-out base slice, a shared TestingSupport/Fixture/Runtime/persistence/lifecycle slice, the last Required slice in a dependency level, or a risk-significant cumulative delta. Bind the Wave build, core Unit, cross-slice Behavior, representative smoke UI and asset/coverage reconciliation to the current cumulative candidate.
5. Turn every Wave finding into a new or reopened Stage 02 slice, propagate its invalidations, and continue scheduling until all Required slices have current C1 anchors.
6. Freeze one exact final candidate tree, command plan and artifact set. Run every risk-required static/build, Unit, Behavior, Mock UI, real-topology UI and Pressure validation against that candidate, then close Reliability, Architecture, Coverage and applicable Compatibility evidence.
7. Produce C2 with the C0 anchor, ordered current C1 anchors, final candidate identity, Wave results, full-validation evidence, five-dimension conclusion, compatibility conclusion, remaining items, exact closure file set and rollback order.

## Completion

- Give every current Required slice a valid committed C1 anchor and resolve all dependency and interaction invalidations.
- Resolve every Wave finding through a current slice and refresh invalidated integration evidence.
- Run all Required validation against the same frozen candidate and artifact identities.
- Make Execution, Coverage, Reliability, Architecture and Pressure `GREEN`, or give a risk-calibrated not-relevant conclusion where the dimension has no applicable Required item.
- Close applicable Compatibility evidence and clear Required gaps, unexpected Skip, open Flake and active Required blockers.
- Validate C2 and its exact stage-owned file set. Completion makes the C2 candidate eligible for Commit.

## Commit

- Limit the candidate to final integration evidence, coverage and queue closure facts, and `docs/test-audit/C2_HANDOFF.json`; deliver semantic content through the committed C1 anchors.
- Apply the shared `commit_policy` after the applicable full-closure and Skill Process/Tooling checks pass, using title `test-audit(campaign): complete FlowTab full-system closure`.
- Use the resulting commit as the C2 campaign anchor.

## Blocked and Resume

- For one blocked slice, continue every entry-ready independent branch and retain the blocked slice's Owner, impact and recovery point.
- Enter campaign-level `BLOCKED` when no safe branch remains runnable. Resume at scheduling after the blocker clears and recompute both dependency and interaction invalidations.
- For a Wave failure, create or reopen the responsible Stage 02 slice and resume at scheduling after its new C1 anchor is committed.
- For a functional full-validation failure, create or reopen the responsible Stage 02 slice and resume at scheduling; refreeze the final candidate after the new C1 anchor.
- For an unavailable Required validation environment, retain valid same-candidate evidence and resume at the affected validation layer while the candidate and artifact identities remain current.
- For candidate, command-plan, build-setting, signing, artifact or environment identity drift, invalidate affected final evidence and resume at final-candidate freeze.
- For a policy-authorized Commit failure, preserve the eligible closure candidate and resume at Commit when its exact file set and expected parent remain current.
- Record the shared blocker fields from `SKILL.md` and the independent work that remains runnable.
