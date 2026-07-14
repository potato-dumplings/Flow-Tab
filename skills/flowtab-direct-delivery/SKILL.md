---
name: flowtab-direct-delivery
description: "Direct answer and FlowTab-specific handoff rules for FlowTab tasks. Use when writing implementation guidance, architecture proposals, bugfix explanations, review findings, diagnostic summaries, change summaries, or remediation plans in this repository. Require concrete conclusions, affected modules or files, explicit assumptions, layer-by-layer validation outcomes, blocked-layer reasons, performance or pressure baselines when relevant, and rollback or failure handling when it matters. Push toward the simplest viable path and avoid placeholder offers such as 'if you want, I can...'."
---

# FlowTab Direct Delivery

Apply this skill when explaining how to implement, change, fix, review, diagnose, or summarize work in FlowTab. The answer should deliver the usable content first instead of offering to provide it later.

This skill is not only a generic answer-style guide. It is the FlowTab delivery wrapper around the repository's engineering workflows, so handoffs must include the project-specific closure fields that make the work reviewable and transferable inside this codebase.

## When To Load FlowTab References

- For feature delivery or feature handoff, read `../flowtab-engineering/references/feature-workflow.md`.
- For bugfix delivery or bugfix handoff, read `../flowtab-engineering/references/bugfix-workflow.md`.
- For risk-calibrated validation, not-relevant layer decisions, or compact reporting, read `../flowtab-engineering/references/risk-calibration.md`.
- For test-layer ownership, coverage audits, or layer-by-layer validation reporting, read `../flowtab-engineering/references/test-layer-boundaries.md`.
- For product-scenario coverage contracts, evidence projections, or coverage-gap reporting, read `../flowtab-engineering/references/test-coverage-matrix-workflow.md`.
- For exact validation commands or command-selection explanations, read `../flowtab-engineering/references/validation-command-cookbook.md`.
- For `FlowTabTests` command attempts, allowed narrowing, signing blockers, or app unit/behavior validation reporting, read `../flowtab-engineering/references/flowtabtests-workflow.md`.
- For UI blocker diagnosis, local UI test triage, or permission-path explanations, read `../flowtab-engineering/references/ui-automation-prerequisites.md`.
- For architecture, refactor, or file-placement guidance, read `../flowtab-engineering/references/module-boundaries.md`.
- For pressure or performance statements, read `../flowtab-engineering/references/performance-pressure-workflow.md` when the change touches hot paths, repeated interaction, scale-sensitive work, or long-lived resources.
- For concurrency, permissions, logging, dependency, and lifetime tradeoffs, read `../flowtab-engineering/references/engineering-specialty-rules.md`.

## Required Response Contract

1. Deliver substance before invitation.
   Give the recommendation, implementation path, and key details before offering optional follow-up help.

2. Do not replace the answer with a placeholder offer.
   Avoid lines that only say the next step could be provided later, such as "if you want, I can give a concrete plan" or "I can add implementation details next." These are only acceptable after the concrete answer is already present.

3. Think before prescribing.
   State the assumptions or missing information that materially affect the recommendation. If multiple interpretations exist, say so instead of silently choosing one. If the simpler path is better, recommend it directly.

4. Make implementation guidance concrete.
   State the implementation approach, the affected ownership boundary, and the execution order. First state how the change should be implemented, then state the sequence for carrying it out.

5. Prefer direct recommendations over meta commentary.
   If one path is clearly best, recommend it directly instead of narrating that a plan could be created.

6. Keep optional next steps genuinely optional.
   Offer follow-up actions only after the answer is complete, and only when there are multiple meaningful directions the user may want.

7. Treat FlowTab closure fields as required, not decorative.
   Do not stop at generic `what / why / where / how validated`. Include the repository-specific fields that make the handoff actionable for reviewers and the next engineer.

8. Report validation by layer.
   When tests or validation matter, name the relevant layers individually. State whether each layer passed, failed, was not relevant, or was blocked, and give the blocking reason when a layer could not run.

9. Report scenario fan-out before test conclusions.
   For implementation guidance, coverage audits, and remediation plans, state the seed scenario, the representative variants considered, which layer owns each variant, and any important variant left as a known gap or blocker.

10. Report test oracles when proposing regression coverage.
   State the fact, product contract, official API result, stable fixture state, explicit input, or independent specification that defines each expected result. If stale data, legacy fields, cached entries, or incorrect configuration are used to recreate the bug, label them as contamination/background and do not derive the expected value from them.

11. Ask for confirmation before expanding test scenarios.
   Before adding new scenario tests, present a concise plan grouped into required, optional, and intentionally not adding. Explain why the required set is the smallest representative coverage. If the user does not confirm, stop before editing test files or report the affected validation layer as incomplete or blocked.

12. Surface pressure and performance status when relevant.
   If the change affects hot paths, repeated interaction cost, scale-sensitive work, or long-lived resources, include the baseline, the pressure attempt or result, or a concrete not-applicable reason.

13. Scale the handoff to the risk.
   Use the full FlowTab handoff for feature delivery, bugfixes, architecture changes, hot-path changes, or blocked validation. Use the compact handoff for docs-only, skill-only, mechanical, or no-runtime-behavior changes.

## FlowTab Handoff Minimums

- All implementation summaries or handoffs must state what changed, why it changed, where it changed, and the assumptions or constraints that shaped the choice.
- When rollback, fallback, or failure handling materially affects delivery risk, handoffs must state it explicitly instead of leaving it implicit.
- Bugfix handoffs must also state the pre-change failing signal.
- Bugfix handoffs must state the regression test oracle and distinguish any contamination/background values from the expected-result source.
- Bugfix handoffs must list the pre-change test runs or test attempts by layer and their outcomes.
- Bugfix handoffs must state which logs or observations supported the root-cause theory.
- Bugfix handoffs must list the post-change tests run by layer and their outcomes.
- Bugfix handoffs must state any relevant layer that was not run and why it was blocked or not possible.
- When pressure validation is relevant, handoffs must state the performance or pressure baseline, the validation attempt or result, or the concrete reason it did not apply.
- Feature handoffs must state the user-visible behavior, the shared rule behind the change, where the logic should live, the scenario fan-out considered, the confirmed test scenario set, and what unit, behavior, and UI coverage proves.
- Architecture or migration handoffs must state the target design, module ownership, migration stages, fallback path, and validation plan.
- Remediation responses must state the current blocker, the affected layer or environment, what remains unproven, and the next concrete step.
- Review, audit, or diagnosis responses must state the observed gap, the supporting evidence, the affected layer or module, the related product-scenario projected status when coverage is involved, and the next concrete corrective action or blocker.

## Compact Handoff

Use this for documentation-only, skill-only, mechanical, or no-runtime-behavior changes:

- State what changed and where.
- State why full feature or bugfix validation was not relevant.
- List any lightweight verification performed, such as file inspection, path checks, or command-source inspection.
- State any command that was attempted but blocked by the local environment.

Do not use the compact handoff for user-visible features, production bugfixes, permission behavior, runtime topology, hot paths, or any change with a required test layer.

## Response Patterns

- For architecture or migration proposals, state the target design, material assumptions, migration stages, fallback path, and validation plan.
- For bugfix explanations or bugfix handoffs, state the pre-change failing signal, pre-change test attempts by layer, logs or observations supporting the root cause, production change, post-change tests by layer, any blocked layer with the reason, and the relevant pressure or performance baseline when applicable.
- For implementation guidance, state where the code should live, what the API or data flow should look like, which assumptions drive the choice, which validation layer should own each kind of evidence, and whether pressure validation is required.
- For reviews, audits, or no-edit diagnosis, state the finding or gap first, then the evidence, impact, affected ownership boundary, and the smallest corrective path.
- For change summaries or handoffs, do not stop at what changed, why it changed, where it changed, and how it was validated. Include the FlowTab-specific closure fields from the relevant engineering workflow, especially pre-change signal, layer-by-layer test attempts or outcomes, blocked validation reasons, and performance or pressure status when relevant.

## Bad and Better

- Bad: "If you want, I can next provide a concrete no-private-API plan."
- Better: "Implement the no-private-API migration in three stages: first isolate the private calls behind one adapter, then replace each capability with a public-path strategy, then remove the adapter after regression coverage passes."
