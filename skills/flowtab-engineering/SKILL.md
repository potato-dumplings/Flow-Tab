---
name: flowtab-engineering
description: "FlowTab project engineering workflow and architecture rules. Use when changing this repository, reviewing code in it, triaging defects, auditing tests or module boundaries, or analyzing root causes or performance without editing. Enforce FlowTab-specific rules: state assumptions and resolve ambiguity before coding or prescribing changes; feature work must expand the user-named seed scenario into a representative scenario family, add unit, behavior, and UI coverage, and pass related tests before submission; test coverage decisions must consult and maintain the product-scenario coverage matrix; bug fixes and investigations must run or explicitly attempt the relevant tests and gather a reproducible signal before production edits or confident diagnosis, stopping to report blockers when that cannot be done; never introduce single-feature or single-scenario special cases; keep test-only or debug-only code out of production files; respect FlowTabCore, FlowTab, TestingSupport, and test-target boundaries."
---

# FlowTab Engineering

Apply this skill to repository changes and repository-specific analysis in FlowTab. Use it to keep implementation, review, triage, test coverage, file placement, and architectural decisions aligned with project rules.

For no-edit work such as review, audit, root-cause triage, or performance analysis, follow the same evidence, boundary, and validation rules first, then stop at diagnosis and recommendation instead of implementation.

## Core Rules

1. Think before coding.
   State assumptions, current evidence, and open questions before implementation. If multiple interpretations or root-cause theories exist, name them instead of choosing silently. Push back when a simpler path would satisfy the request. Stop and report blockers when the remaining ambiguity would force guesswork.

2. Do not introduce single-feature or single-scenario special cases.
   If a change only works by adding one-off branching for a single feature, single scenario, page, caller, or bug case, treat the design as invalid and rework it from a global perspective.

3. Treat feature work as incomplete until test coverage exists in all required layers.
   Read `risk-calibration.md` before deciding which layers are required. For user-visible feature extensions or new features, add or update unit, behavior, and UI tests. Make each layer provide distinct evidence instead of repeating the same assertion three times. Do not claim completion until the required related suites pass. If a layer is not applicable, state the concrete reason; if a required layer is blocked, report the blocker instead of claiming completion.

4. Keep the product-scenario coverage matrix current.
   For feature work, user-visible bug fixes, regression coverage, coverage audits, or test strategy changes, read `test-coverage-matrix-workflow.md` and update `docs/TEST_COVERAGE_MATRIX.md` when a product scenario's unit, behavior/integration, UI/E2E, pressure, real-topology, or known-gap status changes. Do not mark UI/E2E coverage strong when it only proves persistence or control state.

5. Fan out test scenarios before choosing coverage.
   Treat the user's example as a seed scenario, not the full test plan. Before adding or recommending tests, expand it across the relevant product axes from `test-layer-boundaries.md`: state variants, input variants, runtime topology, lifecycle and persistence, permission or fallback paths, and hot-path or scale pressure. Select a representative set that gives distinct evidence at the cheapest responsible layer, and record important unproven variants as matrix gaps when they affect product-scenario status. Before editing test files to add new scenarios, present the proposed scenario set for confirmation and keep it lean; do not add every plausible variant just because it was identified.

6. Diagnose bugs before changing production logic.
   Before editing production files, run or explicitly attempt the relevant existing unit, behavior, and UI tests for the affected layers. Reproduce the bug with a stable signal first: failing tests, stable logs, crash output, compiler or static analyzer output, deterministic configuration or permission evidence, or another observation that clearly narrows the defect. If existing tests cannot reproduce, analyze stable logs first and, when logs support a concrete scenario, add a confirmed failing scenario-based test before production edits. If there is no reproducible signal yet, a required test layer cannot run, the needed scenario plan is not confirmed, or the environment is missing required permissions, fixtures, or tooling, stop and report the blocker instead of patching by guesswork. Keep regression coverage after the fix.

7. Keep test-only and debug-only code out of production files.
   Place unit tests in test targets, test scaffolding in testing support files, and temporary bug-investigation logs or hooks outside the final production path. Keep only minimal production logging that is genuinely part of runtime behavior.

8. Run pressure validation when changes can affect sustained load or scale-sensitive paths.
   If a change touches a high-frequency interaction path, a cost that grows with app or window count, long-lived caches or tasks, repeated runtime sampling, or heavy SwiftUI panel or tab rendering, treat pressure testing as required validation rather than optional follow-up.

9. Respect module boundaries and dependency direction.
   Put code in the lowest reasonable layer, avoid duplicated logic across modules, and do not break package boundaries just to land a quick fix.

10. Extract repeated properties into shared constants.
   When the same property, spacing value, or behavior configuration is needed in more than two places, introduce a shared constant instead of repeating literals. For example, shared top, bottom, leading, and trailing spacing used by Home, Settings, and Logs should come from a constant.

11. Enforce file-size guardrails.
   New source files should usually stay within 400 lines. Files between 400 and 800 lines must still have a clear single responsibility. Files over 800 lines are oversized and should be split instead of expanded. When changing an already oversized file, prefer extracting focused helpers, state, UI pieces, or services, and do not keep growing the file without also reducing or isolating responsibilities.

12. Keep detailed project documentation under `docs/`.
   Reserve repo root for entry documents such as `README*`, `AGENTS.md`, and top-level build or configuration files. Move development, testing, architecture, and other detailed project documents into `docs/`.

## Choose the Right Reference

- For feature extensions or new features, read `references/feature-workflow.md`.
- For bug investigation and bug fixes, read `references/bugfix-workflow.md`.
- For risk, coverage, and not-relevant layer decisions, read `references/risk-calibration.md`.
- For test-scope, test-placement, or unit versus behavior versus UI boundary decisions, read `references/test-layer-boundaries.md`.
- For product-scenario coverage matrix decisions or updates, read `references/test-coverage-matrix-workflow.md`.
- For concrete build, test, UI, and pressure commands, read `references/validation-command-cookbook.md`.
- For `FlowTabTests` startup, narrowing, signing blockers, or app unit/behavior test reporting, read `references/flowtabtests-workflow.md`.
- For FlowTab-specific UI automation setup, fixed-path test app preparation, or permission and code-identity prerequisites, read `references/ui-automation-prerequisites.md`.
- For pressure-test triggers, stress-validation selection, or performance-regression validation, read `references/performance-pressure-workflow.md`.
- For file placement, refactoring, or architecture decisions, read `references/module-boundaries.md`.
- For concurrency, permissions, logging, dependency, and lifetime decisions, read `references/engineering-specialty-rules.md`.

## Working Method

1. Classify the task before editing, then state the assumptions, evidence, and unknowns that matter to the design.
2. If multiple interpretations or implementation paths exist, name them and resolve them before editing. Prefer the simplest path that still satisfies the request.
3. Read `risk-calibration.md` and decide which validation layers are required, not relevant, or blocked.
4. Classify each affected file by architecture role and feature ownership before choosing a module.
5. Choose the correct module before writing code.
6. For bug fixes, run or explicitly attempt the relevant existing tests before production edits and stop if reproduction evidence or required environment access is missing.
   If existing tests cannot reproduce, analyze stable logs first and propose a scenario-based failing test from the log-supported hypothesis when feasible; add it only after confirmation and before production edits.
   If relevant UI automation is involved, first satisfy the repo-specific prerequisites from `ui-automation-prerequisites.md` before deciding the environment is blocked.
   If relevant UI automation is blocked by sandboxed temp or cache paths, first try `./scripts/testing/install-ui-test-app.sh` when a fixed-path UI test app has not been prepared yet, then run `./scripts/testing/run-ui-tests-local.sh`.
   If UI tests still fail, check for fixed-path bundle mismatch, missing Accessibility or Screen Recording permission, or code-identity mismatch before reporting an environment blocker.
   If those checks are satisfied and the fallback script still fails for environment reasons, report the blocker and request the required elevation or external Terminal run instead of continuing with production edits.
7. Design the solution so it generalizes beyond the current case and does not rely on a one-off branch.
8. Expand the seed scenario into the relevant scenario family before selecting tests; avoid letting one named example become the whole coverage plan.
9. Present a concise test scenario plan before adding new tests. Group scenarios as required, optional, and intentionally not adding; state the owning layer for each required scenario and why the set is not bloated. Wait for confirmation before editing test files to add those scenarios. If confirmation narrows coverage below a required layer, report the incomplete or blocked layer instead of claiming completion.
10. Decide what unique evidence each confirmed required test layer should provide, then add or update those tests alongside the code change.
11. Read `test-coverage-matrix-workflow.md` when the work changes test coverage, exposes a coverage gap, or affects a product scenario represented in `docs/TEST_COVERAGE_MATRIX.md`; update the matrix if the scenario status changes.
12. Use `validation-command-cookbook.md` to choose concrete commands for the required layers.
13. Decide whether the change also requires pressure validation by reading `performance-pressure-workflow.md`. If it does, run the relevant stress checks or report the concrete blocker.
14. Run the related test suites before considering the task complete.
    `FlowTabTests` must follow `flowtabtests-workflow.md`.
    Use the documented local wrapper for unsigned app-test builds instead of inventing one-off app-test commands.
15. Final bugfix handoff must state the pre-change failing signal, pre-change tests attempted, evidence supporting the root cause, post-change tests run, any matrix status change, and any required test layer or pressure check that could not be run with the reason.

## References

- `references/feature-workflow.md`
- `references/bugfix-workflow.md`
- `references/risk-calibration.md`
- `references/test-layer-boundaries.md`
- `references/test-coverage-matrix-workflow.md`
- `references/validation-command-cookbook.md`
- `references/flowtabtests-workflow.md`
- `references/ui-automation-prerequisites.md`
- `references/performance-pressure-workflow.md`
- `references/module-boundaries.md`
- `references/engineering-specialty-rules.md`
