# Feature Workflow

Use this workflow for new features and for extending existing behavior.

## Required Outcome

- State the user-visible behavior, shared rule, and material assumptions before implementation.
- Add or update coverage in all three layers: unit, behavior, and UI.
- Pass the related unit, behavior, and UI tests before submission.
- Keep the implementation generic rather than feature-specific.

## Thinking Checkpoint

- Name the smallest behavior change that would satisfy the request.
- State any assumptions that affect module placement, data flow, or user-visible behavior.
- If multiple interpretations or designs exist, resolve them before editing instead of choosing silently.
- Prefer the simplest design that satisfies the behavior without introducing a one-off path.

## Workflow

1. Define the user-visible behavior, the shared rule behind it, and the assumptions that materially affect the design.
2. If the request supports multiple interpretations, resolve them before editing. Do not silently pick one.
3. Read `module-boundaries.md` and choose the lowest reasonable module for the change.
4. Reject any design that only works through a one-off special case or unnecessary abstraction.
5. Add or update unit tests for the smallest reusable logic first.
6. Add or update behavior tests for the feature flow or integration path.
7. Add or update UI tests for the user-visible path.
8. Implement the production change.
9. Run the related test suites and iterate until they pass.

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

- Do not consider the task ready to implement if key assumptions or expected behavior are still ambiguous enough to force guesswork.
- Do not consider the task done if any required test layer is missing.
- Do not consider the task done if tests were added but not run.
- Do not consider the task done if the change depends on a feature-specific branch that does not generalize.

## Practical Test Selection

- Start with the smallest directly related unit or behavior suite.
- Run the directly related UI tests for the affected surface.
- Expand to broader suites when the change touches shared state, launch flow, search, runtime bridging, hotkeys, or panel presentation.
