# Bugfix Workflow

Use this workflow for regressions, flaky behavior, broken edge cases, and user-reported defects.

## Contents

- [Required Outcome](#required-outcome)
- [Workflow](#workflow)
- [Modification Gate](#modification-gate)
- [Completion Gate](#completion-gate)
- [Sandboxed Test Blockers](#sandboxed-test-blockers)
- [Logging Rules](#logging-rules)
- [Test Strategy](#test-strategy)
- [Required Final Report](#required-final-report)
- [Rejection Criteria](#rejection-criteria)

## Required Outcome

- State what is known, what is assumed, and what remains unproven before changing production logic.
- Run or explicitly attempt the relevant existing unit, behavior, and UI tests before changing production logic.
- Reproduce the bug with a stable signal before changing production logic. Acceptable signals include a failing test, an existing failing suite, stable logs, crash output, compiler or static analyzer output, deterministic configuration mismatch, permission or code-identity evidence, or another observation that clearly narrows the defect.
- Treat the reported failing case as the seed regression scenario. After reproducing it, fan out to adjacent scenario variants that could share the same root cause, while keeping the production fix anchored to the stable signal.
- Add the smallest risk-required regression set autonomously, using the authorization boundary in `test-layer-boundaries.md`.
- If existing tests cannot reproduce the issue, analyze stable logs first; when logs support a concrete scenario, add a failing test that captures the scenario and expected log-backed behavior when feasible before changing production logic.
- Stop before production edits when no reproducible signal exists, the evidence does not support a root-cause theory, or unavailable environment evidence is required to satisfy the modification gate.
- Use tests and logs to narrow the root cause instead of guessing.
- Keep each regression layer focused on different evidence instead of cloning the same assertion everywhere.
- For every new regression test, name the oracle that defines the expected result. The oracle must come from the product contract, official API result, stable fixture state, explicit input, or independent specification; legacy fields, stale caches, and known faulty implementation paths may be contamination only.
- Read `test-asset-contract.md` before changing tracked test definitions. Routine bugfix work uses the semantic guard and Git diff. A selected full validation uses the transient `.build-local/test-assets` workspace runner.
- Run pressure validation when the bug or the fix touches sustained-load, repeated-interaction, or scale-sensitive behavior.
- Keep regression coverage after the fix.

## Workflow

1. State the observed failure in one sentence.
2. List the current evidence, assumptions, and open questions. If more than one plausible root-cause theory exists, name the contenders instead of choosing silently.
3. Identify the affected layer or layers: unit, behavior, UI, runtime integration.
4. Read `risk-calibration.md` and decide which layers are required, not relevant, or blocked.
5. Read `test-layer-boundaries.md`, identify the failing seed scenario, and fan out adjacent variants that are likely to share the same rule, wiring, topology, permission, lifecycle, or pressure risk.
6. Decide which layer should hold the failing reproduction, which layer should hold app-orchestration coverage, and whether a visible UI regression is required.
7. Produce a concise regression scenario plan before editing test files. Include the required seed reproduction, the Oracle, the process/result being asserted, contamination used only to recreate the failure environment, higher-layer regression when required, optional adjacent variants, intentionally omitted variants, and the owning layer for each included scenario.
8. Add the smallest required regression set autonomously and apply the optional-expansion rule from `test-layer-boundaries.md`. If the authorized scope excludes a required completion layer, record that layer as incomplete or blocked.
9. Read `test-asset-contract.md`, establish the protected behavior and Oracle for tracked test-definition changes, and apply the semantic guard where required.
10. Read `validation-command-cookbook.md` and choose the concrete pre-change commands to run or attempt.
11. If UI automation is relevant, read `ui-automation-prerequisites.md` and satisfy the repo-specific setup before deciding the environment is blocked.
12. Read `performance-pressure-workflow.md` and decide whether the defect or fix requires pressure validation in addition to functional regression coverage.
13. Identify any required environment prerequisites for reproduction, such as Accessibility trust, screen capture permission, seeded fixtures, launch arguments, fixed-path UI app preparation, or code-identity matching.
14. Before touching production code, run or explicitly attempt the relevant existing unit, behavior, and UI tests and record which layers failed, passed, were not relevant, or were blocked.
15. If existing tests cannot reproduce the defect, analyze existing stable logs first, inspect crash/compiler/static output when that is the signal, or add temporary diagnostic logging when needed to confirm a concrete hypothesis.
16. When logs, tests, compiler output, crash output, or deterministic environment evidence support a concrete scenario, add the missing failing test when feasible. Start at the lowest layer that can express the failure and add higher-layer coverage when the bug is user-visible.
17. Add cheap adjacent regression variants when the shared root cause and risk classification require them; treat other variants according to the authorization boundary in `test-layer-boundaries.md`.
18. Evaluate the modification gate. Proceed only when the stable signal supports the root-cause theory, the intended change is scoped and reviewable, relevant existing tests were attempted, and the regression Oracle is independent.
19. Change production code with the smallest fix that explains the evidence. A blocked higher layer can remain a completion blocker when it is not needed to establish the modification gate.
20. Remove temporary debug-only logging or hooks from the final production path.
21. Inspect the final tracked test-definition diff. During an active Campaign, return current execution observations through the selected audit stage.
22. Re-run the required unit, behavior, UI, and pressure validation. Run a selected full-validation entry through the transient test-asset workspace runner. Apply the completion gate and keep the new regression coverage.

## Modification Gate

Production edits require all of the following:

- A reproducible signal that clearly narrows the defect.
- Evidence supporting the selected root-cause theory over material alternatives.
- A scoped, reviewable, and reversible change boundary.
- Attempts of the relevant existing tests and recorded outcomes.
- An independent Oracle for the regression.
- The smallest failing regression test before the edit when the failure can be expressed deterministically and feasibly.

An unavailable higher layer blocks the modification gate only when its evidence is necessary to establish the signal, root cause, Oracle, or safe change boundary.

## Completion Gate

Completion requires:

- The retained regression coverage passes.
- Every risk-required unit, behavior, and UI layer passes.
- Required pressure validation passes.
- Active Campaign observations are published through their owning workflow.
- Any selected full validation removed `.build-local/test-assets` at terminal exit.
- Remaining uncertainty, blockers, and unproven variants are reported.

When a required layer cannot run, report the implementation as made and the closure as blocked by that layer.

## Sandboxed Test Blockers

- Before calling UI automation blocked, first satisfy the repository prerequisites from `ui-automation-prerequisites.md`.
- Immediately before each UI test action, run `./scripts/testing/install-ui-test-app.sh` so the dedicated app has a fresh one-use receipt.
- Then run `./scripts/testing/run-ui-tests-local.sh`, which redirects `DerivedData`, `TMPDIR`, module caches, and source packages into `./.build-local/ui-tests`, consumes the receipt for the test action, and removes the dedicated app at the terminal boundary.
- If the run still looks like a permission loss or missing live-runtime signal, check fixed-path app usage, Accessibility permission, Screen & System Audio Recording permission, and code-identity matching before reporting a blocker.
- If those checks are satisfied and the fallback script still fails for sandbox or external-environment reasons, classify whether the missing UI evidence blocks the modification gate or only the completion gate. Request the needed elevated or external Terminal run and report the affected gate.

## Logging Rules

- Prefer existing runtime logging and stable observability points first.
- Add temporary logs only when they materially improve diagnosis.
- Do not leave temporary bug-hunt logging scattered in production files after the fix.
- If a reusable logging capability is needed, move that capability into dedicated logging or infrastructure code.

## Test Strategy

- Prefer the lowest-layer failing reproduction you can express.
- When existing suites cannot reproduce, derive the new failing test from the observed runtime scenario and the stable signal that supports the hypothesis.
- Derive expected results from the oracle, not from the old broken implementation path or the proposed fix. Stale data, legacy fields, bad cache entries, and incorrect configuration may be included only as contamination/background.
- Add the required seed reproduction and risk-required nearby variants autonomously. Apply the authorization boundary from `test-layer-boundaries.md` and prefer unit or behavior breadth over many slow UI duplicates.
- Run or attempt every relevant existing test layer before production edits. Classify blocked evidence against the modification and completion gates.
- Keep or add a higher-layer regression when the bug was user-visible or crossed module boundaries.
- Use the layer that owns the evidence instead of cloning the same assertion across unit, behavior, and UI.
- Let unit tests prove deterministic rules, behavior tests prove in-process orchestration, and UI tests prove visible user impact.
- Add pressure validation when the bug or fix touches repeated interaction cost, scale-sensitive search or runtime work, or memory-lifetime risks.
- Use UI coverage for user-facing regressions, interaction issues, settings flows, switcher behavior, and launch-time behavior.
- Use behavior coverage for app-level state transitions, persistence, permission handling, runtime wiring, and search lifecycle issues.
- Use unit coverage for deterministic logic and state machines.

## Required Final Report

Follow `handoff-contract.md` and include:

- State the pre-change failing signal.
- List the pre-change tests or test attempts by layer and their outcomes.
- State which logs or observations supported the root-cause theory.
- List the post-change tests run and their outcomes.
- State any active Campaign observation change and the transient full-validation workspace cleanup result.
- State any relevant layer that was not run and why it was not possible.

## Rejection Criteria

- Reject blind patches that are not backed by a reproducible failing signal.
- Reject bugfixes that edit production code before running or explicitly attempting the relevant pre-change tests.
- Reject regression tests whose expected result is derived from the known faulty path, the proposed fix, or contamination values instead of an independent oracle.
- Reject bugfixes where existing tests could not reproduce, stable evidence was available for diagnosis, but no scenario-based failing test was added from that evidence when feasible.
- Reject production edits that do not satisfy the modification gate.
- Reject completions that do not satisfy the completion gate or omit blocked layers and missing-environment reasons.
- Reject fixes that add test-only or debug-only logic into the production code path.
