---
name: flowtab-engineering
description: "Use for FlowTab repository engineering work including implementation, code review, bug triage, architecture, test strategy, performance analysis, and validated change delivery. Apply FlowTab module boundaries, evidence-first debugging, scenario-based coverage, risk-calibrated validation layers, canonical test wrappers, and task-specific handoff requirements."
---

# FlowTab Engineering

Apply FlowTab's project-specific engineering contract to repository changes and repository-scoped analysis. Load only the references needed for the current task. Apply the handoff contract when the response closes or transfers an engineering task.

## Core Contract

1. Classify the task and risk before editing.
   State material assumptions, current evidence, and unresolved uncertainty. Prefer the smallest design that satisfies the request.

2. Design for the shared rule.
   Reject single-feature, single-scenario, page-specific, caller-specific, or bug-only production branches. Extract repeated behavior and properties into the lowest responsible owner.

3. Respect module and resource boundaries.
   Keep pure reusable rules in `FlowTabCore`, app orchestration and platform integration in their `FlowTab` owners, test scaffolding in `FlowTab/TestingSupport`, and tests in test targets. Persist path intents and resolve them against the explicit resource-owning boundary immediately before use.

4. Diagnose defects from stable evidence.
   Establish a reproducible signal and a supported root-cause theory before production edits. Use the modification and completion gates in `references/bugfix-workflow.md`; a blocked higher layer can leave closure blocked without invalidating an otherwise evidence-supported, scoped production edit.

5. Add the smallest risk-required representative test set autonomously.
   Fan out the seed scenario, then add the unit, behavior, UI, and pressure evidence required by `references/risk-calibration.md`. Apply the scenario authorization boundary from `references/test-layer-boundaries.md`; prompt-driven audit campaigns retain their protocol approval gates.

6. Give every validation layer unique evidence.
   Use unit coverage for deterministic rules, behavior coverage for in-process orchestration, UI coverage for the visible user path or real topology, and pressure validation for sustained-load and scale risk. Required layers must pass before completion; report blocked and unproven layers explicitly.

7. Separate stable coverage contracts from audit machine facts.
   Use `docs/TEST_COVERAGE_MATRIX.md` for stable product scenarios, Oracles, requiredness, layer responsibility, and risk. Enter the Registry path only when interpreting or publishing registry-owned facts such as projection rows, typed refs, reducer versions, checkpoints, or C1/C2 deltas. Let the audit coordinator resolve `docs/test-audit/PROTOCOL_REGISTRY.json` and consume its typed result instead of loading the full Registry into ordinary engineering context.

8. Use canonical validation paths.
   Follow `references/validation-command-cookbook.md`, the FlowTabTests wrapper contract, UI prerequisites, and pressure workflow. Keep build roots and evidence under the repository-local ignored tree.

9. Keep production paths clean.
   Keep tests, test-only hooks, temporary diagnostics, and investigation-only logging outside final production files. Retain only production logging owned by runtime behavior.

10. Preserve FlowTab window identity and activation evidence.
    Keep exact target-window identity, CG/AX reconciliation, activation routing, and post-attempt verification. Private Space switching and app Window-menu routing do not satisfy the product or test contract.

11. Apply repository maintenance guardrails.
    Keep new source files near 400 lines, preserve a single responsibility through 800 lines, split oversized files instead of expanding them, and place detailed project documentation under `docs/`.

## Reference Routing

- Feature work: read `references/feature-workflow.md`.
- Bug investigation or repair: read `references/bugfix-workflow.md`.
- Risk and required-layer decisions: read `references/risk-calibration.md`.
- Test layer, Oracle, or scenario decisions: read `references/test-layer-boundaries.md`.
- Stable coverage contract or audit projection work: read `references/test-coverage-matrix-workflow.md`.
- Build and validation commands: read `references/validation-command-cookbook.md`.
- App unit or behavior validation: read `references/flowtabtests-workflow.md`.
- UI automation, permission, or code-identity setup: read `references/ui-automation-prerequisites.md`.
- Pressure Requiredness and performance evidence: read `references/performance-pressure-workflow.md`.
- Architecture and file placement: read `references/module-boundaries.md`.
- Concurrency, lifetime, permissions, logging, or dependency ownership: read `references/engineering-specialty-rules.md`.
- Engineering closure or transferable handoff: read `references/handoff-contract.md`.

## Working Method

1. Classify the request, affected ownership boundaries, and risk.
2. Load the task workflow plus only the supporting references selected above.
3. For a feature, define the shared rule and representative scenario family. For a defect, establish the stable signal, Oracle, and root-cause evidence.
4. Select the smallest required test set and identify optional or intentionally deferred variants.
5. Implement within the owning module without one-off production behavior.
6. Run the canonical commands for each required runtime layer and any required pressure path.
7. When stable contract fields change, update `docs/TEST_COVERAGE_MATRIX.md`. When the task enters an audit publication transaction, use the coordinator and Registry-owned typed results for projection or C1/C2 publication.
8. When closing or transferring the engineering task, read `references/handoff-contract.md` and report runtime validation separately from process/tooling validation.

## Bundled Resources

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
- `references/handoff-contract.md`
- `scripts/validate-skill.py`
