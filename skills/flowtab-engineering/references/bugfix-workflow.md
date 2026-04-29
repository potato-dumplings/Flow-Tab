# Bugfix Workflow

Use this workflow for regressions, flaky behavior, broken edge cases, and user-reported defects.

## Required Outcome

- State what is known, what is assumed, and what remains unproven before changing production logic.
- Run or explicitly attempt the relevant existing unit, behavior, and UI tests before changing production logic.
- Reproduce the bug with a stable signal before changing production logic. Acceptable signals include a failing test, an existing failing suite, stable logs, crash output, compiler or static analyzer output, deterministic configuration mismatch, permission or code-identity evidence, or another observation that clearly narrows the defect.
- If existing tests cannot reproduce the issue, analyze stable logs first; when logs support a concrete scenario, add a failing test that captures the scenario and expected log-backed behavior before changing production logic.
- Stop and report the blocker if no reproducible signal exists yet or a required environment, permission, fixture, or test layer is unavailable.
- Use tests and logs to narrow the root cause instead of guessing.
- Keep each regression layer focused on different evidence instead of cloning the same assertion everywhere.
- Read `test-coverage-matrix-workflow.md` and update `docs/TEST_COVERAGE_MATRIX.md` when the bugfix changes a product scenario's coverage status or leaves a known gap.
- Run pressure validation when the bug or the fix touches sustained-load, repeated-interaction, or scale-sensitive behavior.
- Keep regression coverage after the fix.

## Workflow

1. State the observed failure in one sentence.
2. List the current evidence, assumptions, and open questions. If more than one plausible root-cause theory exists, name the contenders instead of choosing silently.
3. Identify the affected layer or layers: unit, behavior, UI, runtime integration.
4. Read `risk-calibration.md` and decide which layers are required, not relevant, or blocked.
5. Read `test-layer-boundaries.md` and decide which layer should hold the failing reproduction, which layer should hold app-orchestration coverage, and whether a visible UI regression is required.
6. Read `test-coverage-matrix-workflow.md` when the defect maps to a product scenario in the matrix or reveals a missing scenario.
7. Read `validation-command-cookbook.md` and choose the concrete pre-change commands to run or attempt.
8. If UI automation is relevant, read `ui-automation-prerequisites.md` and satisfy the repo-specific setup before deciding the environment is blocked.
9. Read `performance-pressure-workflow.md` and decide whether the defect or fix requires pressure validation in addition to functional regression coverage.
10. Identify any required environment prerequisites for reproduction, such as Accessibility trust, screen capture permission, seeded fixtures, launch arguments, fixed-path UI app preparation, or code-identity matching.
11. Before touching production code, run or explicitly attempt the relevant existing unit, behavior, and UI tests and record which layers failed, passed, were not relevant, or were blocked.
12. If existing tests cannot reproduce the defect, analyze existing stable logs first, inspect crash/compiler/static output when that is the signal, or add temporary diagnostic logging when needed to confirm a concrete hypothesis.
13. When logs, tests, compiler output, crash output, or deterministic environment evidence support a concrete scenario, add a missing failing test that captures that scenario and expected behavior when feasible. Start at the lowest layer that can express the failure and add higher-layer coverage when the bug is user-visible.
14. If there is still no reproducible signal, if the evidence does not clearly support one theory, or a required layer cannot run because the environment is blocked, stop and report the blocker. Do not edit production files past this point.
15. Change production code only after the stable signal supports the root-cause theory, and prefer the smallest fix that explains the evidence.
16. Remove temporary debug-only logging or hooks from the final production path.
17. Update `docs/TEST_COVERAGE_MATRIX.md` if the regression coverage changes matrix status, adds a scenario, or records a remaining product-scenario gap.
18. Re-run the relevant unit, behavior, and UI tests and any required pressure checks, then keep the new regression coverage.

## Hard Gates

- Do not edit production files before steps 4 through 9 establish either a reproducible failing signal or a clearly reported blocker.
- Do not let an unverified theory or silent assumption become the production fix.
- If existing tests do not reproduce the issue, do not skip directly to production edits. Use logs to form a hypothesis and encode that hypothesis as a failing scenario test whenever feasible.
- If a bug is user-visible and affects switcher behavior, keyboard interaction, window selection, launch flows, settings flows, or permission flows, keep or add a higher-layer regression. Prefer UI coverage when the scenario can be automated reasonably.
- If a test layer is relevant but cannot run, treat that as a blocker to completion. Report it explicitly instead of silently proceeding.
- If required permissions or OS capabilities are unavailable, stop and report the blocker rather than inferring runtime behavior from code inspection alone.
- If the defect or fix involves hot paths, scale growth, repeated async work, or long-lived resources, treat skipped pressure validation as a blocker unless there is a concrete not-applicable reason.

## Sandboxed Test Blockers

- Before calling UI automation blocked, first satisfy the repository prerequisites from `ui-automation-prerequisites.md`.
- When a fixed-path UI test app has not been prepared yet, first run `./scripts/testing/install-ui-test-app.sh`.
- Then run `./scripts/testing/run-ui-tests-local.sh`, because it redirects `DerivedData`, `TMPDIR`, module caches, and source packages into `./.build-local/ui-tests` and prefers the fixed-path UI test app when present.
- If the run still looks like a permission loss or missing live-runtime signal, check fixed-path app usage, Accessibility permission, Screen & System Audio Recording permission, and code-identity matching before reporting a blocker.
- If those checks are satisfied and the fallback script still fails for sandbox or external-environment reasons, stop and report the blocker, then request the needed elevated run or an external Terminal run. Do not continue with production edits while that blocker remains unresolved.

## Logging Rules

- Prefer existing runtime logging and stable observability points first.
- Add temporary logs only when they materially improve diagnosis.
- Do not leave temporary bug-hunt logging scattered in production files after the fix.
- If a reusable logging capability is needed, move that capability into dedicated logging or infrastructure code.

## Test Strategy

- Add the lowest-layer failing reproduction you can express.
- When existing suites cannot reproduce, derive the new failing test from the observed runtime scenario and the stable signal that supports the hypothesis.
- Run every relevant existing test layer before production edits. If a layer is not relevant, say why. If it is relevant but blocked, stop and report the blocker.
- Keep or add a higher-layer regression when the bug was user-visible or crossed module boundaries.
- Use the layer that owns the evidence instead of cloning the same assertion across unit, behavior, and UI.
- Let unit tests prove deterministic rules, behavior tests prove in-process orchestration, and UI tests prove visible user impact.
- Add pressure validation when the bug or fix touches repeated interaction cost, scale-sensitive search or runtime work, or memory-lifetime risks.
- Use UI coverage for user-facing regressions, interaction issues, settings flows, switcher behavior, and launch-time behavior.
- Use behavior coverage for app-level state transitions, persistence, permission handling, runtime wiring, and search lifecycle issues.
- Use unit coverage for deterministic logic and state machines.

## Required Final Report

- State the pre-change failing signal.
- List the pre-change tests or test attempts by layer and their outcomes.
- State which logs or observations supported the root-cause theory.
- List the post-change tests run and their outcomes.
- State any product-scenario matrix status change, or why the matrix did not need an update.
- State any relevant layer that was not run and why it was not possible.

## Rejection Criteria

- Reject blind patches that are not backed by a reproducible failing signal.
- Reject bugfixes that edit production code before running or explicitly attempting the relevant pre-change tests.
- Reject bugfixes where existing tests could not reproduce, stable evidence was available for diagnosis, but no scenario-based failing test was added from that evidence when feasible.
- Reject completions that omit blocked test layers or missing-environment reasons from the final report.
- Reject fixes that add test-only or debug-only logic into the production code path.
