# Stage 01: Empty Boundary And Reconstruction Plan

## Outcome

Establish a committed C0 over a proven empty test-asset boundary and a reproducible production-code-driven reconstruction plan.

## Entry

- Start every new full reconstruction here.
- Establish the Campaign ID, dedicated branch or worktree, target branch, current HEAD and frozen `commit_policy`.
- Require a committed rollback anchor containing the complete current asset set.
- Load engineering's `asset_contract`, `asset_boundaries`, `asset_model`, `asset_discovery`, `asset_views`, `boundary_enforcement`, `reconstruction_safety`, `requiredness`, `layer_assignment`, `pressure`, `command_interface`, `ui_prerequisite` and `ownership` roles.
- Verify that every replaceable asset path and shared carrier is free of uncommitted user changes. Preserve unrelated changes outside the Stage-owned boundary.
- Record toolchain, signing and permission prerequisites, assumptions and unknowns.

## Work

1. Resolve `test-asset-boundaries.json` from the engineering Skill boundary and record its content hash.
2. Record path identities and Git status for the replaceable set without consuming existing test contents as scenario, Oracle or design input.
3. Clear `.build-local/test-audit/rebuild/`, run canonical `reconstruction-clear-plan` from the rollback commit and write `RECONSTRUCTION_CLEAR_PLAN.json`. Require matching HEAD/rollback identity, clean owned paths, complete boundary closure, resolvable fragment selectors, current path fingerprints, owned shared-carrier identifiers and canonical production-residual hashes.
4. Remove exactly the planned asset-boundary paths and structured shared-carrier fragments. Clear `docs/test-audit/` while retaining the current clear plan beneath the transient root.
5. Run canonical `assert-reconstruction-empty` with `RECONSTRUCTION_CLEAR_PLAN.json`. Resolve every remaining fragment, planned project identifier, unexpected asset or production-residual mismatch before continuing.
6. Inspect production source, production-owned project configuration, explicit product or API contracts, platform APIs and independent observations. Derive protected behaviors, Owners, dependencies, lifecycle paths and externally observable results.
7. Build `.build-local/test-audit/rebuild/VALIDATION_PLAN.jsonl` with `record_lifecycle: transient` and `scope_kind: reconstruction`. Give every row a scenario, layer, requiredness, protected-behavior status, independent Oracle, future Runner responsibility and prerequisite plan.
8. Seed the dependency DAG and slice queue from production ownership and behavior dependencies. Give every unresolved semantic fact an Owner and recovery action.
9. Run production-only static and build validation against the cleared candidate.
10. Create `docs/test-audit/C0_HANDOFF.json` with the rollback anchor, production snapshot, shared-rule snapshot, boundary and clear-plan hashes, empty-gate evidence, validation-plan hash, slice topology, findings, blockers and resume points.

## Completion Eligibility

- The dedicated reconstruction branch or worktree and rollback anchor are reproducible.
- The clear plan is eligible, belongs to the rollback/current HEAD and classifies every current test asset and shared-carrier fragment.
- Every replaceable asset path is empty and every shared carrier is free of test-owned fragments.
- Prior audit outputs and the transient reconstruction root were cleared before new records were generated.
- Every plan row is derived from allowed reconstruction inputs and keeps protected behavior separate from implementation details.
- Every Required scenario has an Owner, layer assignment and valid, provisional or explicitly missing independent Oracle.
- Production-only static/build validation has a current result or evidenced blocker.
- C0, its clear-plan hash and its exact Stage-owned deletion and anchor set are frozen.

## Commit

- Commit the complete asset-boundary deletion, test-owned shared-carrier cleanup, prior-anchor deletion and current C0.
- Apply the shared policy with title `test-audit(rebuild): establish empty test-asset boundary`.
- Use the resulting commit as the only C0 consumed by Stage 02 and Stage 03.

## Blocked And Resume

- Resume dirty replaceable paths or a missing rollback anchor at Entry.
- Resume an ineligible clear plan at its dirty path, unresolved fragment, boundary-closure error or rollback mismatch.
- Resume an incomplete clear operation at the exact boundary or shared-carrier fragment.
- Resume empty-gate failures before production behavior discovery.
- Resume behavior or Oracle ambiguity at the affected validation-plan row.
- Preserve completed independent planning when an external prerequisite is unavailable.
- Preserve an eligible candidate after a Commit failure and resume at Commit while its parent and exact file set remain current.
