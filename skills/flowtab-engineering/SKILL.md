---
name: flowtab-engineering
description: "FlowTab project engineering workflow and architecture rules. Use when changing this repository for feature extensions, new features, bug fixes, refactors, logging or test-code placement, or module-boundary decisions. Enforce FlowTab-specific rules: state assumptions and resolve ambiguity before coding; feature work must add unit, behavior, and UI coverage and pass related tests before submission; bug fixes must run or explicitly attempt the relevant tests and gather a reproducible signal before production edits, stopping to report blockers when that cannot be done; never introduce single-feature or single-scenario special cases; keep test-only or debug-only code out of production files; respect FlowTabCore, FlowTab, TestingSupport, and test-target boundaries."
---

# FlowTab Engineering

Apply this skill to repository changes in FlowTab. Use it to keep implementation, test coverage, file placement, and architectural decisions aligned with project rules.

## Core Rules

1. Think before coding.
   State assumptions, current evidence, and open questions before implementation. If multiple interpretations or root-cause theories exist, name them instead of choosing silently. Push back when a simpler path would satisfy the request. Stop and report blockers when the remaining ambiguity would force guesswork.

2. Do not introduce single-feature or single-scenario special cases.
   If a change only works by adding one-off branching for a single feature, single scenario, page, caller, or bug case, treat the design as invalid and rework it from a global perspective.

3. Treat feature work as incomplete until test coverage exists in all required layers.
   For every feature extension or new feature, add or update unit, behavior, and UI tests. Do not submit code until the related unit, behavior, and UI suites pass.

4. Diagnose bugs before changing production logic.
   Before editing production files, run or explicitly attempt the relevant existing unit, behavior, and UI tests for the affected layers. Reproduce the bug with tests or stable logs first. If existing tests cannot reproduce, analyze stable logs first and, when logs support a concrete scenario, add a failing scenario-based test before production edits. If there is no reproducible signal yet, a required test layer cannot run, or the environment is missing required permissions, fixtures, or tooling, stop and report the blocker instead of patching by guesswork. Keep regression coverage after the fix.

5. Keep test-only and debug-only code out of production files.
   Place unit tests in test targets, test scaffolding in testing support files, and temporary bug-investigation logs or hooks outside the final production path. Keep only minimal production logging that is genuinely part of runtime behavior.

6. Respect module boundaries and dependency direction.
   Put code in the lowest reasonable layer, avoid duplicated logic across modules, and do not break package boundaries just to land a quick fix.

7. Extract repeated properties into shared constants.
   When the same property, spacing value, or behavior configuration is needed in more than two places, introduce a shared constant instead of repeating literals. For example, shared top, bottom, leading, and trailing spacing used by Home, Settings, and Logs should come from a constant.

8. Enforce file-size guardrails.
   New source files should usually stay within 400 lines. Files between 400 and 800 lines must still have a clear single responsibility. Files over 800 lines are oversized and should be split instead of expanded. When changing an already oversized file, prefer extracting focused helpers, state, UI pieces, or services, and do not keep growing the file without also reducing or isolating responsibilities.

9. Keep detailed project documentation under `docs/`.
   Reserve repo root for entry documents such as `README*`, `AGENTS.md`, and top-level build or configuration files. Move development, testing, architecture, and other detailed project documents into `docs/`.

## Choose the Right Reference

- For feature extensions or new features, read `references/feature-workflow.md`.
- For bug investigation and bug fixes, read `references/bugfix-workflow.md`.
- For file placement, refactoring, or architecture decisions, read `references/module-boundaries.md`.

## Working Method

1. Classify the task before editing, then state the assumptions, evidence, and unknowns that matter to the design.
2. If multiple interpretations or implementation paths exist, name them and resolve them before editing. Prefer the simplest path that still satisfies the request.
3. Classify each affected file by architecture role and feature ownership before choosing a module.
4. Choose the correct module before writing code.
5. For bug fixes, run or explicitly attempt the relevant existing tests before production edits and stop if reproduction evidence or required environment access is missing.
   If existing tests cannot reproduce, analyze stable logs first and add a scenario-based failing test from the log-supported hypothesis when feasible before production edits.
   If relevant UI automation is blocked by sandboxed temp or cache paths, first try `./scripts/testing/run-ui-tests-local.sh`. If that still fails for environment reasons, report the blocker and request the required elevation or external Terminal run instead of continuing with production edits.
6. Design the solution so it generalizes beyond the current case and does not rely on a one-off branch.
7. Add or update tests alongside the code change.
8. Run the related test suites before considering the task complete.
9. Final bugfix handoff must state the pre-change failing signal, pre-change tests attempted, evidence supporting the root cause, post-change tests run, and any required test layer that could not be run with the reason.

## References

- `references/feature-workflow.md`
- `references/bugfix-workflow.md`
- `references/module-boundaries.md`
