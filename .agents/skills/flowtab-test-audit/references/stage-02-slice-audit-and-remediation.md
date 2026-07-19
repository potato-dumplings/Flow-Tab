# Stage 02: Dependency-Slice Audit and Remediation

## Outcome

Audit and close exactly one minimal dependency slice as `remediated` or `audit_completed_no_change`. Establish a committed C1 anchor containing the slice's meaning, quality, representative scenario family, module and system evidence, semantic delta, required validation, invalidation effects and rollback boundary.

## Entry

- Require a current committed C0 anchor whose snapshot, asset ledger, baseline and dependency inputs are reconstructible.
- Select one entry-ready minimal slice with satisfied prerequisites, resolved interaction invalidations, a reconstructible scope and an explicit account of overlap with user-owned changes.
- Inherit the campaign `commit_policy`; for a standalone invocation, default to `commit_on_stage_complete` and honor an explicit pre-stage `prepare_only` request.
- Use C0 evidence as investigation input for product contract, Owner, Oracle, meaning, quality and scenario-family work.

## Work

1. **Test meaning.** Investigate the protected product contract, user risk, candidate Oracle, current production path, correct evidence layer and relationship to neighboring assets. Determine whether an independent Oracle can be established. Classify each asset for retention, rewrite planning, merge planning, retirement planning, coverage gap or invalid Oracle.
2. **Test quality.** Determine whether the asset fails when the protected behavior breaks. Review assertion sensitivity, Fixture fidelity, async waiting, timeout, Skip, cleanup, isolation, Mock boundaries, Target membership, Runner reachability, Flake, lifecycle and pressure risk.
3. **Scenario family.** Fan out the seed across state, input, runtime topology, lifecycle and persistence, permission and fallback, and scale and pressure. Select the smallest Required representative set, record Optional variants, and explain intentionally omitted variants. Add required coverage autonomously as new test files or new test declarations in existing files.
4. **Module boundary.** Determine and confirm the authoritative Owner. Place each rule in the lowest responsible Owner, preserve dependency direction, identify consumers and interaction peers, and determine invalidation propagation. Use reusable abstractions for shared behavior.
5. **System evidence.** Map the smallest contract through the real FlowTab path from input and runtime state to projection, search, activation, feature coordination, UI and lifecycle. Assign distinct Unit, Behavior, Mock UI, real-topology UI and Pressure evidence according to risk.

**Existing-test clarification gate.** Apply the project-local test-semantic guard before editing test sources. New test files, new test methods and other additive test declarations proceed without clarification. When closure requires changing or removing an existing test function or changing existing file-scope test semantics:

- establish the product contract, authoritative Owner and independent Oracle;
- identify the exact existing symbols and explain the decisive evidence, current conflict, and proposed Oracle/input/Fixture/assertion/expected-result delta;
- ask the user the smallest question needed to clarify the intended test semantics;
- after explicit clarification, authorize the guard's pending token with `.codex/hooks/test_semantic_guard.py authorize <token> --note "<clarification summary>"` and retry the same candidate;
- retain the clarification summary in C1 and validate the clarified test together with the new regression coverage.

Continue production diagnosis, production remediation, additive coverage and independent validation while clarification is pending. Enter `BLOCKED` with `owner=user` and `resume_from=Scenario family` only when no safe independent work remains. Before a production edit, establish a stable deficiency signal and evidence supporting the selected root-cause theory; for a clean audit, establish evidence supporting zero semantic delta.

6. **Remediation and validation.** Select the primary disposition: `test_defect`, `coverage_gap`, `production_defect`, `product_contract_change`, `module_boundary_debt`, `runner_or_fixture`, `permission_signing_environment`, `performance_or_lifetime`, or `audit_clean`. Freeze the change boundary and required closure proof, make the smallest evidence-supported change in the authoritative Owner, validate from the lowest decisive layer through every risk-required consumer and system layer, update owned coverage facts, remove temporary diagnostics, and produce C1.

C1 must include the C0 anchor, slice ID, scope, Owner, prerequisites, product contract, Oracle, scenario plan, meaning and quality conclusions, primary and contributing dispositions, deficiency signal or clean-audit proof, root cause when required, semantic delta, changed files, per-layer validation, closure proof, coverage effects, dependency and interaction invalidations, next-candidate hints, remaining uncertainty and rollback boundary.

## Completion

- Complete all six work items for the current slice and keep their evidence current against the same slice candidate.
- Confirm the product contract, authoritative Owner, independent Oracle and actual production path.
- Match the actual semantic delta to the confirmed scenario and change plan.
- Satisfy the disposition-specific closure proof and every risk-required validation layer.
- Resolve Required gaps, unexpected Skip, open Flake, stale evidence and temporary diagnostic delta.
- Update the stable coverage contract or current evidence projection through its owning workflow when applicable.
- For `audit_completed_no_change`, keep production, tests, TestingSupport, Fixture, Runner, project/Scheme and stable product semantics unchanged and retain an audit-clean proof.
- Validate C1 and its exact stage-owned file set. Completion makes the C1 candidate eligible for Commit.

## Commit

- Limit the candidate to one minimal slice, its verified semantic or audit delta, and `docs/test-audit/slices/<slice-id>/SLICE_HANDOFF.json`.
- Select the commit type from the primary outcome and actual delta: `fix` for production defects, `feat` for approved product-contract changes, `test` for test defects and coverage, `refactor` for module boundaries, `build` or `test` for Runner/Fixture/signing ownership, `perf` for performance or lifetime work, and `test-audit` for audit-clean closure.
- Use `<type>(<slice-scope>): <completed semantic outcome>`; use `test-audit(<slice-scope>): complete test audit` for audit-clean closure.
- Apply the shared `commit_policy` after all applicable runtime and Process/Tooling validation passes.
- Use the resulting commit as the C1 anchor consumed by Stage 03.

## Blocked and Resume

- For a stale C0 anchor or unresolved dependency or interaction invalidation, return control to Stage 03 and resume after entry readiness is recomputed.
- For unresolved existing-test semantics, record the exact clarification question and affected symbols, preserve completed evidence, continue independent work, and resume at Scenario family after the clarification is recorded and authorized.
- For an insufficient deficiency signal, root-cause theory, product contract, Owner or Oracle, stop before the affected edit and resume at the earliest investigation item that remains unproven.
- For scope, Owner, consumer or semantic-delta drift, invalidate the candidate and resume at Module boundary or the earlier affected work item.
- For a required validation environment blocker, retain completed lower-layer evidence and resume at the affected validation layer when the candidate remains current.
- For a policy-authorized Commit failure, preserve the eligible candidate and resume at Commit when the exact file set and expected parent remain current.
- Record the shared blocker fields from `SKILL.md`; Stage 03 may continue independently runnable slices.
