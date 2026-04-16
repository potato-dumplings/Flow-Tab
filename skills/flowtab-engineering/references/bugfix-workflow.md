# Bugfix Workflow

Use this workflow for regressions, flaky behavior, broken edge cases, and user-reported defects.

## Required Outcome

- State what is known, what is assumed, and what remains unproven before changing production logic.
- Run or explicitly attempt the relevant existing unit, behavior, and UI tests before changing production logic.
- Reproduce the bug with a failing test, an existing failing suite, or stable logs before changing production logic.
- If existing tests cannot reproduce the issue, analyze stable logs first; when logs support a concrete scenario, add a failing test that captures the scenario and expected log-backed behavior before changing production logic.
- Stop and report the blocker if no reproducible signal exists yet or a required environment, permission, fixture, or test layer is unavailable.
- Use tests and logs to narrow the root cause instead of guessing.
- Keep each regression layer focused on different evidence instead of cloning the same assertion everywhere.
- Keep regression coverage after the fix.

## Workflow

1. State the observed failure in one sentence.
2. List the current evidence, assumptions, and open questions. If more than one plausible root-cause theory exists, name the contenders instead of choosing silently.
3. Identify the affected layer or layers: unit, behavior, UI, runtime integration.
4. Read `test-layer-boundaries.md` and decide which layer should hold the failing reproduction, which layer should hold app-orchestration coverage, and whether a visible UI regression is required.
5. Identify any required environment prerequisites for reproduction, such as Accessibility trust, screen capture permission, seeded fixtures, or launch arguments.
6. Before touching production code, run or explicitly attempt the relevant existing unit, behavior, and UI tests and record which layers failed, passed, were not relevant, or were blocked.
7. If existing tests cannot reproduce the defect, analyze existing stable logs first, or add temporary diagnostic logging when needed to confirm a concrete hypothesis.
8. When logs or tests support a concrete scenario, add a missing failing test that captures that scenario and expected behavior. Start at the lowest layer that can express the failure and add higher-layer coverage when the bug is user-visible.
9. If there is still no reproducible signal, if the evidence does not clearly support one theory, or a required layer cannot run because the environment is blocked, stop and report the blocker. Do not edit production files past this point.
10. Change production code only after tests or logs support the root-cause theory, and prefer the smallest fix that explains the evidence.
11. Remove temporary debug-only logging or hooks from the final production path.
12. Re-run the relevant unit, behavior, and UI tests and keep the new regression coverage.

## Hard Gates

- Do not edit production files before steps 4 through 7 establish either a reproducible failing signal or a clearly reported blocker.
- Do not let an unverified theory or silent assumption become the production fix.
- If existing tests do not reproduce the issue, do not skip directly to production edits. Use logs to form a hypothesis and encode that hypothesis as a failing scenario test whenever feasible.
- If a bug is user-visible and affects switcher behavior, keyboard interaction, window selection, launch flows, settings flows, or permission flows, keep or add a higher-layer regression. Prefer UI coverage when the scenario can be automated reasonably.
- If a test layer is relevant but cannot run, treat that as a blocker to completion. Report it explicitly instead of silently proceeding.
- If required permissions or OS capabilities are unavailable, stop and report the blocker rather than inferring runtime behavior from code inspection alone.

## Sandboxed Test Blockers

- When UI automation is relevant and `xcodebuild` fails because sandboxed temp files, module caches, or SwiftPM caches cannot be created, first try `./scripts/testing/run-ui-tests-local.sh`.
- Treat that script as the standard local fallback because it redirects `DerivedData`, `TMPDIR`, module caches, and source packages into `./.build-local/ui-tests`.
- If the fallback script still fails for environment reasons, stop and report the blocker, then request the needed elevated run or an external Terminal run. Do not continue with production edits while that blocker remains unresolved.

## Logging Rules

- Prefer existing runtime logging and stable observability points first.
- Add temporary logs only when they materially improve diagnosis.
- Do not leave temporary bug-hunt logging scattered in production files after the fix.
- If a reusable logging capability is needed, move that capability into dedicated logging or infrastructure code.

## Test Strategy

- Add the lowest-layer failing reproduction you can express.
- When existing suites cannot reproduce, derive the new failing test from the observed runtime scenario and the log signal that supports the hypothesis.
- Run every relevant existing test layer before production edits. If a layer is not relevant, say why. If it is relevant but blocked, stop and report the blocker.
- Keep or add a higher-layer regression when the bug was user-visible or crossed module boundaries.
- Use the layer that owns the evidence instead of cloning the same assertion across unit, behavior, and UI.
- Let unit tests prove deterministic rules, behavior tests prove in-process orchestration, and UI tests prove visible user impact.
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
- Reject bugfixes where existing tests could not reproduce, logs were available for diagnosis, but no scenario-based failing test was added from that log-backed analysis.
- Reject completions that omit blocked test layers or missing-environment reasons from the final report.
- Reject fixes that add test-only or debug-only logic into the production code path.
