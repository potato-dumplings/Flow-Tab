# Feature Workflow

Use this workflow for new features and for extending existing behavior.

## Required Outcome

- State the user-visible behavior, shared rule, and material assumptions before implementation.
- Read `risk-calibration.md` and classify the change before deciding validation scope.
- For user-visible features and feature extensions, add or update coverage in all three layers: unit, behavior, and UI.
- Read `test-coverage-matrix-workflow.md` and update `docs/TEST_COVERAGE_MATRIX.md` when the feature changes a product scenario's coverage status or exposes a new gap.
- For documentation-only or mechanical changes that are not feature work, use the calibrated minimum and state why any layer is not relevant.
- Make each test layer prove a different part of the change instead of repeating the same assertion.
- Run pressure validation when the change touches hot paths, scale-sensitive logic, or repeated heavy UI or runtime work.
- Pass the required related unit, behavior, and UI tests before completion. If a required layer is blocked, report the blocker instead of calling the feature complete.
- Keep the implementation generic rather than feature-specific.

## Thinking Checkpoint

- Name the smallest behavior change that would satisfy the request.
- State any assumptions that affect module placement, data flow, or user-visible behavior.
- If multiple interpretations or designs exist, resolve them before editing instead of choosing silently.
- Prefer the simplest design that satisfies the behavior without introducing a one-off path.

## Workflow

1. Define the user-visible behavior, the shared rule behind it, and the assumptions that materially affect the design.
2. If the request supports multiple interpretations, resolve them before editing. Do not silently pick one.
3. Read `risk-calibration.md` and decide which layers are required, not relevant, or blocked.
4. Read `test-layer-boundaries.md` and decide what distinct evidence unit, behavior, and UI coverage should provide.
5. Read `test-coverage-matrix-workflow.md` when the feature maps to an existing matrix scenario or creates a new product scenario.
6. Read `validation-command-cookbook.md` and choose the smallest concrete command for each required layer.
7. If UI automation is relevant, read `ui-automation-prerequisites.md` before planning the validation run.
8. Read `performance-pressure-workflow.md` and decide whether the change also requires pressure validation.
9. Read `module-boundaries.md` and choose the lowest reasonable module for the change.
10. Reject any design that only works through a one-off special case or unnecessary abstraction.
11. Add or update unit tests for the smallest reusable rule first when unit coverage is required.
12. Add or update behavior tests for the app-level flow or integration path when behavior coverage is required.
13. Add or update UI tests for the visible user path when UI coverage is required.
14. Implement the production change.
15. Update `docs/TEST_COVERAGE_MATRIX.md` if the feature changes matrix status, adds a scenario, or leaves an explicit gap.
16. Run the related test suites and any required pressure checks, then iterate until they pass. If a required validation layer is blocked, stop at a blocker report instead of completion.

## Coverage Expectations

- Unit tests should verify pure logic, state transitions, normalization rules, deterministic helpers, and the smallest shared rule behind the feature.
- Behavior tests should verify application-level flows, persistence, launch options, permissions, logging behavior, or integration seams that are still stable in-process.
- UI tests should verify the visible user path, not just internal state.
- A UI test that only proves a Settings control changed or persisted is not enough to mark UI/E2E matrix coverage `Strong`; the resulting runtime or visible behavior must also be exercised.
- Treat these as coverage layers, not simple aliases for Xcode target names. Use `test-layer-boundaries.md` when placement feels ambiguous.
- Do not make all three layers assert the same branch. The unit layer should prove the rule, the behavior layer should prove orchestration, and the UI layer should prove visibility.

## Layer Placement Guide

- Use `FlowTabCore/Tests/FlowTabCoreTests` for pure `FlowTabCore` unit rules.
- Use `FlowTabTests` for app-scoped unit tests and behavior tests that stay in-process.
- Use `FlowTabUITests` for XCUI-visible paths and fixture-app workflows.
- If a feature seems to have no unit seam, that is usually a signal to extract or isolate the deterministic rule rather than skipping unit coverage.

## File Placement

- Put reusable pure logic in `FlowTabCore` when it can avoid app-framework dependencies.
- Put app-level orchestration and feature integration in `FlowTab`.
- Put UI automation support and launch-time test hooks in `FlowTab/TestingSupport`.
- Put tests only in `FlowTabCoreTests`, `FlowTabTests`, or `FlowTabUITests`.

## Validation Standard

- Do not consider the task ready to implement if key assumptions or expected behavior are still ambiguous enough to force guesswork.
- Do not consider user-visible feature work done if any required test layer is missing.
- Do not consider the task done if tests were added but not run, unless a required environment blocker is reported.
- Do not consider the task done if required pressure validation was skipped without a concrete not-applicable reason.
- Do not consider the task done if the change depends on a feature-specific branch that does not generalize.
- For docs-only, skill-only, or mechanical changes, explicitly report layers as not relevant using `risk-calibration.md` instead of pretending full feature validation was required.

## Practical Test Selection

- Start with the smallest directly related unit or behavior suite.
- Run the directly related UI tests for the affected surface.
- When UI tests depend on live permissions, fixed app paths, or real fixture apps, prepare the repo-specific prerequisites before treating failures as generic environment issues.
- Prefer one strong assertion per layer over many duplicated assertions across layers.
- Run the matching pressure scenario when the change affects repeated interaction cost, scale-sensitive search or runtime work, or heavy repeatedly rendered UI.
- Expand to broader suites when the change touches shared state, launch flow, search, runtime bridging, hotkeys, or panel presentation.
