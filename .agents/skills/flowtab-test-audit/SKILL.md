---
name: flowtab-test-audit
description: "Use for explicit repository-wide FlowTab test-audit campaigns, C0 pre-change baseline establishment, C1 dependency-slice audit and remediation, C2 or G10 same-candidate full closure, and recovery from audit handoffs, blockers, or checkpoints. Apply Stage 01/02/03 gates, default commit-on-stage-complete policy, committed C0/C1/C2 anchors, and deterministic resume points. Route ordinary feature development, bug fixes, test additions, and routine validation through $flowtab-engineering."
---

# FlowTab Test Audit

Run FlowTab test audits as three committed stages. Use `$flowtab-engineering` for project-specific engineering rules, evidence selection, module ownership, canonical validation commands, and final reporting. Use this Skill for stage routing, handoff freshness, commit gates, and blocked-state recovery.

## Core Contract

1. Read the repository `AGENTS.md`, then use `$flowtab-engineering` and load the references required by the active stage.
2. Treat this Skill and the selected stage reference as the active campaign contract. Use repository-owned validation paths for execution and keep historical prompt archives outside runtime decisions.
3. Preserve user-owned changes. Freeze a reconstructible audited snapshot and assign every dirty path to an unambiguous owner before dynamic validation or staging.
4. Persist paths as `{resource_boundary, relative_path_intent}` and resolve each intent at the resource-owning boundary immediately before use.
5. Track each stage as `IN_PROGRESS`, `BLOCKED`, or `COMPLETED`. Treat actionable failures, findings and independently runnable work as `IN_PROGRESS`; reserve `BLOCKED` for conditions that prevent all safe progress.
6. Default every campaign and standalone Stage 02 invocation to `commit_policy=commit_on_stage_complete` without prompting. Honor `prepare_only` only when the user explicitly requests it before the campaign or standalone stage begins. Freeze the resulting policy at Entry and inherit it unchanged across the campaign.
7. Let the stage Completion gate establish commit eligibility. Under `prepare_only`, keep the stage `IN_PROGRESS` at Commit, report the exact candidate and title, and preserve the Git index and history. Under `commit_on_stage_complete`, stage the exact stage-owned file set, inspect the staged diff, run `git diff --cached --check`, and create the local commit.
8. Mark the stage `COMPLETED` after its local commit succeeds. Treat push as a separately authorized delivery action.

## Stage Routing

- For a full campaign without a current committed C0 anchor, run Stage 01 and then enter Stage 03.
- For a full campaign with a current committed C0 anchor, enter Stage 03.
- For one explicitly selected dependency slice, require a current committed C0 anchor, inherit the campaign policy or apply the default policy for a standalone invocation, and run Stage 02.
- From Stage 03, invoke Stage 02 for exactly one entry-ready slice at a time and consume its committed C1 anchor before scheduling the next write-producing slice.
- When a stage is blocked, load that stage's `Blocked and Resume` section and retain unaffected evidence and independent work.

Read the matching stage reference completely before acting:

- Stage 01: `references/stage-01-assets-and-baseline.md`
- Stage 02: `references/stage-02-slice-audit-and-remediation.md`
- Stage 03: `references/stage-03-dependency-scheduling-and-closure.md`

## Handoff Anchors

| Handoff | Producer | Repository-relative path intent | Consumer | Promise |
| --- | --- | --- | --- | --- |
| C0 | Stage 01 | `docs/test-audit/C0_HANDOFF.json` | Stage 02 and Stage 03 | Reconciled assets, trustworthy baseline, classified findings and initial slice topology |
| C1 | Stage 02 | `docs/test-audit/slices/<slice-id>/SLICE_HANDOFF.json` | Stage 03 | One completed slice, its semantic delta, validation, invalidations and rollback boundary |
| C2 | Stage 03 | `docs/test-audit/C2_HANDOFF.json` | Campaign delivery | One same-candidate full-system closure over all current C1 anchors |

Produce C0, C1, or C2 content after the corresponding Completion gate passes. Under `prepare_only`, treat that content as a commit candidate. Use the local commit containing it as the consumable handoff anchor. Consume an anchor only while its audited snapshot, confirmed semantics, dependency and interaction inputs, and exact delta remain current. On drift, invalidate downstream evidence and resume from the earliest affected stage or work item.

Every completion-eligible handoff candidate and committed handoff must state:

- input anchors and audited snapshot;
- scope, Owner, outcome and decisive evidence;
- required validation results and remaining uncertainty;
- dependency and interaction effects;
- exact stage-owned file set and rollback boundary.

Represent an incomplete stage with a blocker or checkpoint record containing the shared fields below. Treat that record as resume state; downstream stages consume committed C0/C1/C2 anchors.

## Blocked and Resume Contract

Enter `BLOCKED` when any of these conditions prevents all safe progress:

- a required entry anchor is missing, stale, ambiguous, or unreconstructible;
- required product behavior remains ambiguous after repository evidence is exhausted;
- an existing test semantic change is necessary and user clarification is still unresolved;
- dirty-path, module, dependency, interaction, or change ownership is unresolved;
- a required canonical runner, environment prerequisite, permission, fixture, signing identity, or evidence channel remains unavailable after its required setup;
- required evidence is missing, corrupt, stale, or insufficient to support the next edit or completion claim;
- the exact stage commit cannot be established safely.

Continue safe discovery, new-test coverage, production remediation, validation and independent slices before declaring `BLOCKED`. Historical or optional process resources do not block work supported by the active stage contract and repository validation paths.

Record `stage`, `blocked_at`, `owner`, `decisive_evidence`, `facts_proven`, `facts_unproven`, `minimum_unblock_action`, `resume_from`, `input_anchors`, and `unaffected_work`.

After the blocker clears, verify the recorded input anchors. Resume at `resume_from` when they remain current. Return to the earliest invalidated work item when the snapshot, semantics, scope, graph, candidate, or evidence identity changed. In Stage 03, continue entry-ready independent branches and declare campaign-level `BLOCKED` only when no safe branch remains runnable.

A `prepare_only` candidate waiting for an explicit commit instruction remains `IN_PROGRESS` at Commit and retains its eligible candidate state.

## Commit Contract

Apply the frozen policy, defaulting to `commit_on_stage_complete`, to every eligible stage candidate:

- `prepare_only`: report the handoff candidate, exact file set, expected parent, validation results, rollback boundary and commit title. On a later explicit commit instruction, revalidate those inputs and resume at Commit.
- `commit_on_stage_complete`: stage only the exact stage-owned file set, inspect it, run `git diff --cached --check`, and create the local stage commit.

Apply these stage-specific candidate contracts:

- Stage 01: create `test-audit(baseline): establish FlowTab test baseline` from Stage 01 audit facts and C0.
- Stage 02: create one C1 commit per completed slice, using the semantic commit type selected in the Stage 02 reference.
- Stage 03: create `test-audit(campaign): complete FlowTab full-system closure` from final integration evidence and C2.

Downstream stages consume a handoff after its commit succeeds. Preserve unrelated working-tree and index changes throughout staging and commit creation.
