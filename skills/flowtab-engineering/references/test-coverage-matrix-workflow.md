# Test Coverage Matrix Workflow

Use this reference when adding, changing, auditing, or explaining FlowTab test coverage across product scenarios.

## Required Outcome

- Keep `docs/TEST_COVERAGE_MATRIX.md` as the cross-layer product-scenario index.
- Use the matrix to record whether each product scenario has unit, behavior/integration, UI/E2E, and pressure or real-topology evidence.
- Distinguish persistence/control-state checks from true UI/E2E behavior proof.
- Update the matrix whenever a change adds, removes, renames, materially changes, or newly identifies a product-scenario coverage gap.

## When To Read Or Update The Matrix

Read `docs/TEST_COVERAGE_MATRIX.md` before making coverage decisions for:

- User-visible feature work or feature extensions.
- User-visible bug fixes and regressions.
- Settings changes where a persisted value must affect runtime behavior.
- Hotkey, search, panel, Home, Logs, permission, runtime, fixture, or real-window workflow changes.
- Coverage audits, remediation plans, and test strategy proposals.

Update `docs/TEST_COVERAGE_MATRIX.md` when:

- A new product scenario is added.
- A scenario's unit, behavior/integration, UI/E2E, pressure, or real-topology status changes.
- A test only proves persistence or a control value, and the remaining user-visible behavior gap should be explicit.
- A bugfix adds regression coverage that changes a scenario from `Gap` to `Partial` or `Strong`.
- A required layer is blocked and the scenario should record the remaining unproven path.

For docs-only, skill-only, or mechanical edits that do not affect coverage meaning, inspect the matrix only when the edit mentions coverage status, test scenarios, or validation expectations.

## Status Semantics

- `Strong`: direct automated evidence proves the scenario for that layer.
- `Partial`: related automated evidence exists, but does not prove the full user-visible or runtime outcome.
- `Gap`: coverage is missing for that layer and the scenario still needs evidence.
- `Not relevant`: the layer does not naturally apply; the reason should be concrete when reporting.

Do not mark UI/E2E as `Strong` when the test only proves a setting value persisted or a control changed. UI/E2E becomes `Strong` only when the changed setting is exercised through the resulting visible or runtime behavior.

## Workflow

1. Identify the product scenario affected by the work.
2. Read the current row in `docs/TEST_COVERAGE_MATRIX.md`, or add a row if none exists.
3. Decide what unique evidence each relevant layer should provide using `test-layer-boundaries.md`.
4. During implementation, add or update the test layers required by `risk-calibration.md`.
5. After validation, update the matrix row only to the level actually proven by passing tests or concrete evidence.
6. If a layer remains blocked or intentionally out of scope, keep the status as `Partial` or `Gap` and state the remaining proof needed.

## Reporting

For coverage audits and handoffs, include:

- The affected matrix row or product scenario.
- The old and new status when it changed.
- The evidence that supports `Strong` or `Partial`.
- The remaining gap when the status is not `Strong`.
- Any blocked validation layer and the blocker.
