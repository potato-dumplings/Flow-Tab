---
name: flowtab-test-audit
description: "Use for explicit repository-wide FlowTab test-asset replacement and reconstruction, C0 empty-boundary planning, C1 dependency-slice asset generation, C2 same-candidate full closure, and recovery from reconstruction handoffs, blockers, or checkpoints. Apply Stage 01/02/03 gates, committed C0/C1/C2 anchors, and deterministic resume points. Route ordinary feature development, bug fixes, test additions, and routine validation through $flowtab-engineering."
---

# FlowTab Test Audit

Run a full reconstruction as three committed stages. Use `$flowtab-engineering` for the shared asset contract, replacement boundary, schemas, canonical tooling, behavior evidence, ownership and validation. Use this Skill for clearing the current asset set, Stage routing, compact anchors, commit gates and recovery.

## Core Contract

1. Read the repository `AGENTS.md`, then use `$flowtab-engineering`. Load `shared-test-asset-rules.json`, `test-asset-boundaries.json`, the asset contract, reconstruction safety tooling and the additional roles required by the active Stage.
2. Treat production source, project configuration, explicit product or API contracts, platform APIs and independent observations as reconstruction inputs. Keep pre-reconstruction test contents and prior audit artifacts in Git history for recovery only.
3. Start every new full reconstruction on a dedicated branch or worktree with a committed rollback anchor. Require every replaceable test-asset path to be free of uncommitted user changes before clearing it.
4. Clear `.build-local/test-audit/rebuild/`, generate its safety-qualified reconstruction clear plan, then clear the planned asset boundary, shared-carrier fragments and `docs/test-audit/`. Pass the canonical empty-boundary check with that retained plan before deriving scenarios or writing test assets.
5. Persist paths as `{resource_boundary, relative_path_intent}` and resolve each intent at the owning boundary immediately before access.
6. Track each Stage as `IN_PROGRESS`, `BLOCKED` or `COMPLETED`. Keep current obligations and independently runnable work `IN_PROGRESS`. Reserve `BLOCKED` for conditions that prevent all safe progress.
7. Default every full reconstruction and standalone Stage 02 invocation to `commit_policy=commit_on_stage_complete`. Honor `prepare_only` only when the user explicitly requests it before Entry and freeze the policy for the Campaign.
8. Let Completion establish commit eligibility. Under `prepare_only`, retain the frozen candidate as `IN_PROGRESS`. Under `commit_on_stage_complete`, stage the exact Stage-owned set, inspect the staged diff, run `git diff --cached --check` and create the local commit.
9. Mark a Stage `COMPLETED` after its local commit succeeds. Treat push as a separately authorized action.

## Stage Routing

- Start every new full reconstruction at Stage 01.
- Enter Stage 03 with the committed current C0; let Stage 03 schedule one entry-ready Stage 02 slice at a time.
- Run standalone Stage 02 only from a current committed C0 whose empty-boundary and reconstruction-plan inputs remain reproducible.
- Consume a committed C1 before scheduling the next write-producing slice.
- Resume from the latest current C0, C1 or C2 only while its source snapshot, shared rules and exact current asset candidate remain valid.

Read the selected Stage reference completely before acting:

- Stage 01: `references/stage-01-empty-boundary-and-reconstruction-plan.md`
- Stage 02: `references/stage-02-dependency-slice-reconstruction.md`
- Stage 03: `references/stage-03-reconstruction-scheduling-and-full-closure.md`

## Current Anchors

| Anchor | Producer | Repository path intent | Promise |
| --- | --- | --- | --- |
| C0 | Stage 01 | `docs/test-audit/C0_HANDOFF.json` | Rollback identity, qualified clear plan, proven empty boundary, reconstruction inputs, validation-plan hash and initial slice topology |
| C1 | Stage 02 | `docs/test-audit/slices/<slice-id>/SLICE_HANDOFF.json` | Canonical validation-plan row references, one reconstructed slice, generated assets, validation and rollback boundary |
| C2 | Stage 03 | `docs/test-audit/C2_HANDOFF.json` | One final current test-asset set and same-candidate full-system closure |

Keep only the current reconstruction's anchors in the working tree. Git history stores earlier anchors and asset sets.

Create each anchor as a draft during Work, validate and freeze it at Completion, then use its local commit as the downstream anchor. Every eligible anchor states:

- Campaign ID, input commits and production-source snapshot;
- shared-rule snapshot and asset-boundary hash;
- scope, Owner, outcome and decisive evidence;
- transient dataset hashes and reproducible generation commands;
- selected canonical record IDs, row hashes and aggregate hashes when an anchor consumes transient semantics;
- required validation results and remaining uncertainty;
- exact Stage-owned files and rollback boundary.

## Transient Records

Resolve the active working root as `.build-local/test-audit/rebuild/`. Clear it at Stage 01 Entry and keep these generated records there:

- `VALIDATION_PLAN.jsonl`
- `TEST_ASSET_LEDGER.jsonl`
- `EXECUTION_OBSERVATIONS.jsonl`
- `RECONSTRUCTION_CLEAR_PLAN.json`
- `BOUNDARY_CLOSURE.json`
- `slices/<slice-id>/BEFORE_ASSETS.jsonl`
- `slices/<slice-id>/AFTER_ASSETS.jsonl`
- `slices/<slice-id>/ASSET_DELTAS.jsonl`
- `slices/<slice-id>/VALIDATION_PLAN_REFS.json`
- raw commands, logs, result bundles and environment manifests

Commit hashes, decisive summaries and recovery facts through C0/C1/C2. Recreate a missing transient record from its anchor's source snapshot, rules and generation command.

## Blocked And Resume

Enter `BLOCKED` when a condition prevents all safe progress:

- the rollback anchor, dedicated branch or replaceable-path ownership is unavailable;
- the empty-boundary gate fails;
- required protected behavior or independent Oracle remains ambiguous;
- a required Runner, environment prerequisite, permission, Fixture, signing identity or evidence channel is unavailable after its setup path;
- required evidence is missing, corrupt or insufficient for the next asset generation or completion claim;
- the exact Stage commit cannot be established safely.

Continue safe production-source discovery, contract analysis, independent scenario planning and unaffected slices before declaring `BLOCKED`. Record `stage`, `blocked_at`, `owner`, `decisive_evidence`, `facts_proven`, `facts_unproven`, `minimum_unblock_action`, `resume_from`, `input_anchors` and `unaffected_work`.

After recovery, verify the current anchor and candidate. Resume at the recorded work item when they remain current; return to the earliest invalidated Stage when source, rules, boundary, plan, candidate or evidence changed.

## Commit Contract

- Stage 01: commit the cleared test-asset boundary, cleared prior anchors and current C0 as `test-audit(rebuild): establish empty test-asset boundary`.
- Stage 02: commit one reconstructed slice and current C1 using the semantic type selected from the generated asset delta.
- Stage 03: commit final integration evidence and current C2 as `test-audit(rebuild): complete FlowTab test-asset reconstruction`.

Under `prepare_only`, report the exact candidate, expected parent, validation, rollback boundary and title. Under `commit_on_stage_complete`, preserve unrelated working-tree and index changes while committing only the frozen Stage-owned set.
