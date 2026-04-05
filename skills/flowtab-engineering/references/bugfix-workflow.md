# Bugfix Workflow

Use this workflow for regressions, flaky behavior, broken edge cases, and user-reported defects.

## Required Outcome

- Reproduce the bug before changing production logic.
- Use tests and logs to narrow the root cause instead of guessing.
- Keep regression coverage after the fix.

## Workflow

1. State the observed failure in one sentence.
2. Identify the affected layer or layers: unit, behavior, UI, runtime integration.
3. Run the relevant existing unit, behavior, and UI tests to see where the failure appears or disappears.
4. Add a missing failing test when the current suite cannot localize the defect.
5. Use existing logs or add temporary diagnostic logging to confirm the hypothesis.
6. Change production code only after tests or logs support the root-cause theory.
7. Remove temporary debug-only logging or hooks from the final production path.
8. Re-run the relevant unit, behavior, and UI tests and keep the new regression coverage.

## Logging Rules

- Prefer existing runtime logging and stable observability points first.
- Add temporary logs only when they materially improve diagnosis.
- Do not leave temporary bug-hunt logging scattered in production files after the fix.
- If a reusable logging capability is needed, move that capability into dedicated logging or infrastructure code.

## Test Strategy

- Add the lowest-layer failing reproduction you can express.
- Keep or add a higher-layer regression when the bug was user-visible or crossed module boundaries.
- Use UI coverage for user-facing regressions, interaction issues, settings flows, switcher behavior, and launch-time behavior.
- Use behavior coverage for app-level state transitions, persistence, permission handling, runtime wiring, and search lifecycle issues.
- Use unit coverage for deterministic logic and state machines.

## Rejection Criteria

- Reject blind patches that are not backed by a reproducible failing signal.
- Reject fixes that add test-only or debug-only logic into the production code path.
