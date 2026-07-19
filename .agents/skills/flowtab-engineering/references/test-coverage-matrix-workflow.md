# Test Coverage Contract And Projection Workflow

Use this reference when adding, changing, auditing, or explaining FlowTab test coverage across product scenarios.

## Required Outcome

- Keep `docs/TEST_COVERAGE_MATRIX.md` as the stable contract for cross-layer product scenarios.
- Store each scenario's product contract in the matrix: product scenario, Oracle, requiredness, coverage responsibility, applicable layers, and risk classification.
- Keep current validation evidence in its owning engineering handoff or active test-audit stage artifacts.
- Store an audit campaign's current scenario-layer view in `docs/test-audit/COVERAGE_EVIDENCE_PROJECTION.jsonl` when that projection is needed.
- Distinguish persistence or control-state evidence from visible UI/E2E behavior evidence.

## Stable Contract

Read `docs/TEST_COVERAGE_MATRIX.md` before making coverage decisions for user-visible features, bug fixes, settings, hotkeys, search, panels, permissions, runtime, fixtures, real-window workflows, audits and test strategy proposals.

Update the matrix when the stable product contract changes, including:

- adding, removing, renaming, merging, or retiring a product scenario;
- changing a scenario's Oracle, requiredness, coverage responsibility, applicable layers, or risk classification;
- correcting a contract field that changes which evidence is required.

During an active audit campaign, include stable-contract changes in the applicable C1 or C2 delta.

## Audit Boundary

Ordinary implementation, diagnosis, review and validation use the matrix, engineering references and canonical Runner paths directly. When work belongs to an active audit campaign, return these facts to the selected stage:

- scenario and layer;
- current evidence and command result;
- blocker and remaining proof;
- semantic or coverage delta;
- invalidation effects.

The selected stage owns its handoff, current projection and completion decision. Historical prompt archives remain design inputs.

## Current Evidence Projection

When the active stage maintains `docs/test-audit/COVERAGE_EVIDENCE_PROJECTION.jsonl`, each row records:

- `current_status=Strong|Partial|Gap|Not relevant`;
- `scenario_id` and `layer`;
- `observation_refs`, `blocker_refs` and `evidence_refs`;
- `invalidation_reason` when prior evidence is no longer current.

Use these status meanings:

- `Strong`: direct automated evidence proves the scenario for that layer.
- `Partial`: related evidence exists and leaves part of the outcome unproven.
- `Gap`: the scenario still needs evidence for that layer.
- `Not relevant`: the stable contract marks the layer inapplicable and states why.

UI/E2E reaches `Strong` when the resulting visible or runtime behavior is exercised. Persistence or control-state evidence belongs to its owning unit or behavior layer and can support a `Partial` UI/E2E projection.

## Workflow

1. Identify the affected product scenario and layer.
2. Read or update the stable scenario contract in `docs/TEST_COVERAGE_MATRIX.md`.
3. Select the distinct evidence required from each applicable layer using `test-layer-boundaries.md` and `risk-calibration.md`.
4. Add or update the required tests and run the canonical validation path.
5. Record the evidence, blocker, semantic delta and invalidation effects in the engineering handoff.
6. During an active audit campaign, publish those facts through the selected stage handoff and update its current evidence projection when applicable.

## Reporting

Include the affected scenario and layer, stable-contract changes, current projected status, decisive evidence, remaining proof and blockers.
