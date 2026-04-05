# Bugfix Workflow

Use this workflow for regressions, flaky behavior, broken edge cases, and user-reported defects.

## Required Outcome

- Run or explicitly attempt the relevant existing unit, behavior, and UI tests before changing production logic.
- Reproduce the bug with a failing test, an existing failing suite, or stable logs before changing production logic.
- Stop and report the blocker if no reproducible signal exists yet or a required environment, permission, fixture, or test layer is unavailable.
- Use tests and logs to narrow the root cause instead of guessing.
- Keep regression coverage after the fix.

## Workflow

1. State the observed failure in one sentence.
2. Identify the affected layer or layers: unit, behavior, UI, runtime integration.
3. Identify any required environment prerequisites for reproduction, such as Accessibility trust, screen capture permission, seeded fixtures, or launch arguments.
4. Before touching production code, run or explicitly attempt the relevant existing unit, behavior, and UI tests and record which layers failed, passed, were not relevant, or were blocked.
5. Add a missing failing test when the current suite cannot localize the defect. Start at the lowest layer that can express the failure.
6. Use existing logs or add temporary diagnostic logging to confirm the hypothesis.
7. If there is still no reproducible signal, or a required layer cannot run because the environment is blocked, stop and report the blocker. Do not edit production files past this point.
8. Change production code only after tests or logs support the root-cause theory.
9. Remove temporary debug-only logging or hooks from the final production path.
10. Re-run the relevant unit, behavior, and UI tests and keep the new regression coverage.

## Hard Gates

- Do not edit production files before steps 4 through 7 establish either a reproducible failing signal or a clearly reported blocker.
- If a bug is user-visible and affects switcher behavior, keyboard interaction, window selection, launch flows, settings flows, or permission flows, keep or add a higher-layer regression. Prefer UI coverage when the scenario can be automated reasonably.
- If a test layer is relevant but cannot run, treat that as a blocker to completion. Report it explicitly instead of silently proceeding.
- If required permissions or OS capabilities are unavailable, stop and report the blocker rather than inferring runtime behavior from code inspection alone.

## Logging Rules

- Prefer existing runtime logging and stable observability points first.
- Add temporary logs only when they materially improve diagnosis.
- Do not leave temporary bug-hunt logging scattered in production files after the fix.
- If a reusable logging capability is needed, move that capability into dedicated logging or infrastructure code.

## Test Strategy

- Add the lowest-layer failing reproduction you can express.
- Run every relevant existing test layer before production edits. If a layer is not relevant, say why. If it is relevant but blocked, stop and report the blocker.
- Keep or add a higher-layer regression when the bug was user-visible or crossed module boundaries.
- Use UI coverage for user-facing regressions, interaction issues, settings flows, switcher behavior, and launch-time behavior.
- Use behavior coverage for app-level state transitions, persistence, permission handling, runtime wiring, and search lifecycle issues.
- Use unit coverage for deterministic logic and state machines.

## Required Final Report

- State the pre-change failing signal.
- List the pre-change tests or test attempts by layer and their outcomes.
- State which logs or observations supported the root-cause theory.
- List the post-change tests run and their outcomes.
- State any relevant layer that was not run and why it was not possible.

## Rejection Criteria

- Reject blind patches that are not backed by a reproducible failing signal.
- Reject bugfixes that edit production code before running or explicitly attempting the relevant pre-change tests.
- Reject completions that omit blocked test layers or missing-environment reasons from the final report.
- Reject fixes that add test-only or debug-only logic into the production code path.
