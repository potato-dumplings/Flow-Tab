# Feature Workflow

Use this workflow for new features and for extending existing behavior.

## Required Outcome

- State the user-visible behavior, shared rule, and material assumptions before implementation.
- Add or update coverage in all three layers: unit, behavior, and UI.
- Make each test layer prove a different part of the change instead of repeating the same assertion.
- Run pressure validation when the change touches hot paths, scale-sensitive logic, or repeated heavy UI or runtime work.
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
3. Read `test-layer-boundaries.md` and decide what distinct evidence unit, behavior, and UI coverage should provide.
4. If UI automation is relevant, read `ui-automation-prerequisites.md` before planning the validation run.
5. Read `performance-pressure-workflow.md` and decide whether the change also requires pressure validation.
6. Read `module-boundaries.md` and choose the lowest reasonable module for the change.
7. Reject any design that only works through a one-off special case or unnecessary abstraction.
8. Add or update unit tests for the smallest reusable rule first.
9. Add or update behavior tests for the app-level flow or integration path.
10. Add or update UI tests for the visible user path.
11. Implement the production change.
12. Run the related test suites and any required pressure checks, then iterate until they pass.

## Coverage Expectations

- Unit tests should verify pure logic, state transitions, normalization rules, deterministic helpers, and the smallest shared rule behind the feature.
- Behavior tests should verify application-level flows, persistence, launch options, permissions, logging behavior, or integration seams that are still stable in-process.
- UI tests should verify the visible user path, not just internal state.
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
- Do not consider the task done if any required test layer is missing.
- Do not consider the task done if tests were added but not run.
- Do not consider the task done if required pressure validation was skipped without a concrete not-applicable reason.
- Do not consider the task done if the change depends on a feature-specific branch that does not generalize.

## Practical Test Selection

- Start with the smallest directly related unit or behavior suite.
- Run the directly related UI tests for the affected surface.
- When UI tests depend on live permissions, fixed app paths, or real fixture apps, prepare the repo-specific prerequisites before treating failures as generic environment issues.
- Prefer one strong assertion per layer over many duplicated assertions across layers.
- Run the matching pressure scenario when the change affects repeated interaction cost, scale-sensitive search or runtime work, or heavy repeatedly rendered UI.
- Expand to broader suites when the change touches shared state, launch flow, search, runtime bridging, hotkeys, or panel presentation.
