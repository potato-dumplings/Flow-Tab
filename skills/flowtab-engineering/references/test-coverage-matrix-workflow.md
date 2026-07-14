# Test Coverage Contract And Projection Workflow

Use this reference when adding, changing, auditing, or explaining FlowTab test coverage across product scenarios.

## Required Outcome

- Keep `docs/TEST_COVERAGE_MATRIX.md` as the stable contract for cross-layer product scenarios.
- Store each scenario's product contract in the matrix: product scenario, Oracle, requiredness, coverage responsibility, applicable layers, and risk classification.
- Use `docs/test-audit/PROTOCOL_REGISTRY.json` as the durable protocol authority for projection selectors, reducer versions, and evidence-status semantics.
- Store current evidence status in `docs/test-audit/COVERAGE_EVIDENCE_PROJECTION.jsonl` and its derived presentation in `docs/test-audit/COVERAGE_EVIDENCE_PROJECTION.md`.
- Distinguish persistence/control-state evidence from visible UI/E2E behavior evidence.
- Keep contract changes and evidence changes in their owning publication paths.

## Stable Contract

Read `docs/TEST_COVERAGE_MATRIX.md` before making coverage decisions for:

- User-visible feature work, feature extensions, bug fixes, and regressions.
- Settings changes where a persisted value must affect runtime behavior.
- Hotkey, search, panel, Home, Logs, permission, runtime, fixture, or real-window workflows.
- Coverage audits, remediation plans, and test strategy proposals.

Update `docs/TEST_COVERAGE_MATRIX.md` when the stable product contract changes, including:

- Adding, removing, renaming, merging, or retiring a product scenario.
- Changing a scenario's Oracle, requiredness, coverage responsibility, applicable layers, or risk classification.
- Correcting a contract field that changes which evidence is required.

Publish stable-contract changes through the applicable C1/C2 content delta.

## Dynamic Evidence Projection

`docs/test-audit/COVERAGE_EVIDENCE_PROJECTION.jsonl` is the canonical current evidence projection. Each row records:

- `current_status=Strong|Partial|Gap|Not relevant`
- `projection_candidate_id`
- `scenario_id`
- `layer`
- `observation_refs`
- `blocker_refs`
- `evidence_refs`
- `reducer_version`
- `invalidation_reason`

Update the projection when validation adds, removes, invalidates, restores, or supersedes evidence, or when a blocker changes. Resolve the row's selector and `reducer_version` through the durable protocol registry, then publish the JSONL row and derived Markdown in the same docs-checkpoint generation as the observations, blockers, and evidence refs that determine it.

## Status Semantics

- `Strong`: direct automated evidence proves the scenario for that layer.
- `Partial`: related automated evidence exists and leaves part of the visible or runtime outcome unproven.
- `Gap`: the scenario still needs evidence for that layer.
- `Not relevant`: the stable contract marks the layer inapplicable and provides the applicable rationale.

UI/E2E reaches `Strong` when the resulting visible or runtime behavior is exercised. Persistence or control-state evidence contributes to its owning unit or behavior layer and can support a `Partial` UI/E2E projection.

## Workflow

1. Identify the affected product scenario and layer.
2. Read the scenario's stable contract in `docs/TEST_COVERAGE_MATRIX.md`; add or change the contract row when the product contract requires it.
3. Decide the unique evidence each applicable layer must provide using `test-layer-boundaries.md` and `risk-calibration.md`.
4. Add or update the required tests alongside the implementation.
5. After validation, publish the current projection row at the level proven by passing tests or concrete evidence.
6. Record blocker refs and remaining proof in the projection when an applicable layer is blocked or incomplete.
7. Keep the derived Markdown byte-consistent with the canonical JSONL generation.

## Reporting

For coverage audits and handoffs, include:

- The affected product scenario and layer.
- Any stable-contract field changed.
- The previous and current projected status.
- The evidence refs supporting `Strong` or `Partial`.
- The remaining proof and blocker refs for `Gap` or `Partial`.
