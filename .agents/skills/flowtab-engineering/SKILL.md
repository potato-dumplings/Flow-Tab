---
name: flowtab-engineering
description: "Use for FlowTab repository engineering work including implementation, code review, bug triage, architecture, transient full-validation test-asset handling, test strategy, performance analysis, and validated change delivery. Apply FlowTab module boundaries, evidence-first debugging, risk-calibrated validation layers, canonical test tooling, and task-specific handoff requirements."
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
   Fan out the seed scenario, then add the unit, behavior, UI, and pressure evidence required by `references/risk-calibration.md`. Add new test files and new test declarations without clarification. Route necessary changes to existing test semantics through the project guard and the active workflow's clarification boundary.

6. Give every validation layer unique evidence.
   Use unit coverage for deterministic rules, behavior coverage for in-process orchestration, UI coverage for the visible user path or real topology, and pressure validation for sustained-load and scale risk. Required layers must pass before completion; report blocked and unproven layers explicitly.

7. Keep generated test-asset data transient.
   Use `references/test-asset-contract.md` and `references/test-asset-boundaries.json` for tracked test definitions, canonical records, protected behavior, Oracles and test-semantic changes. Routine work updates tracked definitions directly. A selected full validation exclusively owns one fresh `.build-local/test-assets` workspace through `scripts/test_asset_workspace.py` and removes it at terminal exit. `$flowtab-test-audit` owns explicit full reconstruction separately.

8. Use canonical validation paths.
   Follow `references/validation-command-cookbook.md`, the FlowTabTests wrapper contract, UI prerequisites, and pressure workflow. Keep build roots and evidence under the repository-local ignored tree.
   Bound raw evidence by the owning validation slice. In a long-running audit or migration, record the slice's durable result, commit or hand off its terminal state, and remove reproducible build products, result bundles, fixture products, caches, and temporary homes before the next slice starts. Retain a compact blocker bundle only when named remediation work explicitly depends on it.

9. Use evidence-driven synchronization.
   Drive production and test progress from callbacks, notifications, readbacks, generations, explicit state transitions, and independent Oracles. Reject fixed-delay temporal coupling, raw settling sleeps, fixed RunLoop waits, and magic timeouts as sequencing, readiness, success, or correctness signals. Allow condition polling only when no event source exposes the required transition; keep the observable condition or readback as the sole success signal. Use centralized cancellable watchdogs only as terminal failure bounds, and model domain time through injectable clocks or schedulers. Follow `references/evidence-driven-synchronization.md`.

10. Keep production paths clean.
   Keep tests, test-only hooks, temporary diagnostics, and investigation-only logging outside final production files. Retain only production logging owned by runtime behavior.

11. Preserve FlowTab window identity and activation evidence.
    Keep exact target-window identity, CG/AX reconciliation, activation routing, and post-attempt verification. Private Space switching and app Window-menu routing do not satisfy the product or test contract.

12. Apply repository maintenance guardrails.
    Keep new source files near 400 lines, preserve a single responsibility through 800 lines, split oversized files instead of expanding them, and place detailed project documentation under `docs/`.

## Reference Routing

- Feature work: read `references/feature-workflow.md`.
- Bug investigation or repair: read `references/bugfix-workflow.md`.
- Risk and required-layer decisions: read `references/risk-calibration.md`.
- Test layer, Oracle, or scenario decisions: read `references/test-layer-boundaries.md`.
- Test-asset discovery, maintenance, semantic changes or audit inputs: read `references/test-asset-contract.md`.
- Full-reconstruction ownership or clearing boundaries: read `references/test-asset-boundaries.json` with `references/test-asset-contract.md`.
- Build and validation commands: read `references/validation-command-cookbook.md`.
- App unit or behavior validation: read `references/flowtabtests-workflow.md`.
- UI automation, permission, or code-identity setup: read `references/ui-automation-prerequisites.md`.
- Pressure Requiredness and performance evidence: read `references/performance-pressure-workflow.md`.
- Architecture and file placement: read `references/module-boundaries.md`.
- Timing, waiting, retry, polling, deadline, or test-synchronization decisions: read `references/evidence-driven-synchronization.md`.
- Concurrency, lifetime, permissions, logging, or dependency ownership: read `references/engineering-specialty-rules.md`.
- Engineering closure or transferable handoff: read `references/handoff-contract.md`.

## Working Method

1. Classify the request, affected ownership boundaries, and risk.
2. Load the task workflow plus only the supporting references selected above.
3. For a feature, define the shared rule and representative scenario family. For a defect, establish the stable signal, Oracle, and root-cause evidence.
4. Select the smallest required test set and identify optional or intentionally deferred variants.
5. When tracked test definitions may change, apply the semantic guard and inspect their Git diff as defined by `references/test-asset-contract.md`.
6. Implement within the owning module without one-off production behavior.
7. Run the required runtime and pressure commands. When full validation generates canonical test-asset data, run its complete entry through `scripts/test_asset_workspace.py`.
8. During an active audit Campaign, publish current observations through the selected `$flowtab-test-audit` stage.
9. When closing or transferring the engineering task, read `references/handoff-contract.md` and report runtime validation separately from process/tooling validation.

## Bundled Resources

- `references/feature-workflow.md`
- `references/bugfix-workflow.md`
- `references/risk-calibration.md`
- `references/test-layer-boundaries.md`
- `references/test-asset-contract.md`
- `references/test-asset-boundaries.json`
- `references/shared-test-asset-rules.json`
- `references/test-asset.schema.json`
- `references/validation-plan-row.schema.json`
- `references/execution-observation.schema.json`
- `references/asset-delta.schema.json`
- `references/validation-command-cookbook.md`
- `references/flowtabtests-workflow.md`
- `references/ui-automation-prerequisites.md`
- `references/performance-pressure-workflow.md`
- `references/module-boundaries.md`
- `references/evidence-driven-synchronization.md`
- `references/engineering-specialty-rules.md`
- `references/handoff-contract.md`
- `scripts/test_asset_model.py`
- `scripts/test_asset_boundary.py`
- `scripts/test_asset_clear_plan.py`
- `scripts/test_asset_index.py`
- `scripts/test_asset_views.py`
- `scripts/test_asset_workspace.py`
- `scripts/test_asset_selftest.py`
- `scripts/validate-skill.py`
