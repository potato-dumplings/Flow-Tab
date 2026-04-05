# Feature Workflow

Use this workflow for new features and for extending existing behavior.

## Required Outcome

- Add or update coverage in all three layers: unit, behavior, and UI.
- Pass the related unit, behavior, and UI tests before submission.
- Keep the implementation generic rather than feature-specific.

## Workflow

1. Define the user-visible behavior and the shared rule behind it.
2. Read `module-boundaries.md` and choose the lowest reasonable module for the change.
3. Reject any design that only works through a one-off special case.
4. Add or update unit tests for the smallest reusable logic first.
5. Add or update behavior tests for the feature flow or integration path.
6. Add or update UI tests for the user-visible path.
7. Implement the production change.
8. Run the related test suites and iterate until they pass.

## Coverage Expectations

- Unit tests should verify pure logic, state transitions, normalization rules, and deterministic helpers.
- Behavior tests should verify application-level flows, persistence, launch options, permissions, logging behavior, or integration seams that are still stable in-process.
- UI tests should verify the visible user path, not just internal state.

## File Placement

- Put reusable pure logic in `FlowTabCore` when it can avoid app-framework dependencies.
- Put app-level orchestration and feature integration in `FlowTab`.
- Put UI automation support and launch-time test hooks in `FlowTab/TestingSupport`.
- Put tests only in `FlowTabCoreTests`, `FlowTabTests`, or `FlowTabUITests`.

## Validation Standard

- Do not consider the task done if any required test layer is missing.
- Do not consider the task done if tests were added but not run.
- Do not consider the task done if the change depends on a feature-specific branch that does not generalize.

## Practical Test Selection

- Start with the smallest directly related unit or behavior suite.
- Run the directly related UI tests for the affected surface.
- Expand to broader suites when the change touches shared state, launch flow, search, runtime bridging, hotkeys, or panel presentation.
