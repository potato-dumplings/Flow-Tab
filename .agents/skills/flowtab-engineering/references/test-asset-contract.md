# Test Asset Contract

Use this reference whenever FlowTab engineering changes tracked test definitions or generates canonical test-asset records for full validation or reconstruction. Routine engineering and `$flowtab-test-audit` use this single contract.

## Contents

- [Truth And Lifecycle](#truth-and-lifecycle)
- [Generated Workspace Lifecycle](#generated-workspace-lifecycle)
- [Asset Boundary](#asset-boundary)
- [Record Model](#record-model)
- [Identity And Location](#identity-and-location)
- [Discovery And Normalization](#discovery-and-normalization)
- [Protected Behavior And Oracle](#protected-behavior-and-oracle)
- [Existing-Test Semantic Guard](#existing-test-semantic-guard)
- [Requiredness And Execution](#requiredness-and-execution)
- [Routine Engineering](#routine-engineering)
- [Full Reconstruction](#full-reconstruction)
- [Shared Rule Snapshot And Drift](#shared-rule-snapshot-and-drift)

## Truth And Lifecycle

Use production source, project configuration, explicit product or API contracts, stable external inputs, platform APIs and independent observations to establish the behavior that tracked test definitions protect.

Treat these repository-owned files as the current executable test definitions:

- test source and declarations;
- Fixtures, test data and `FlowTab/TestingSupport`;
- test-owned Target, Scheme, test-plan and configuration content;
- canonical Runners, pressure scenarios and repository-owned prerequisite probes.

Routine engineering maintains those definitions in place and uses Git as their history. A full reconstruction replaces the complete definition set from an empty boundary.

Canonical test-asset records, validation plans, execution observations, deltas and generated projections describe one current full-validation or reconstruction candidate. They are generated views rather than durable repository state.

The lifecycle of `.build-local/test-assets` is exactly one selected full validation. That validation may generate canonical records there for its own execution lifetime. Full reconstruction uses the separate `$flowtab-test-audit` Stage roots and compact C0, C1 and C2 anchors.

Mark every validation-plan row with `record_lifecycle: transient` and `scope_kind: task | reconstruction`. Store complete protected behavior, Oracle and requiredness semantics in the canonical row. Let compact anchors identify selected rows by ID and canonical row SHA-256.

## Generated Workspace Lifecycle

Use `scripts/test_asset_workspace.py` as the only owner of `.build-local/test-assets`.

- Wrap one selected full-validation entry with it. Targeted and routine validation operate on tracked definitions while `.build-local/test-assets` remains absent.
- The runner resolves the path intent from `repository_root`, acquires the repository-local workspace lock, clears stale data and creates one fresh workspace.
- The full-validation child receives `FLOWTAB_TEST_ASSET_ROOT` as the resolved accessible path and `FLOWTAB_TEST_ASSET_PATH_INTENT=.build-local/test-assets` as the persisted intent.
- Store only canonical ledgers, plans, observations, deltas and derived views for the active full validation there. Keep build roots, result bundles, logs, pressure samples and diagnostic working trees in their owning validation output roots.
- Remove the entire workspace when the full-validation command reaches any terminal exit, including success or failure. A later invocation clears residue from an abnormal process termination before creating its workspace.
- Serialize full validations through the workspace lock. A concurrent owner fails without modifying the active workspace.
- Its data lifecycle ends with the owning validation. Report only the terminal validation outcome and successful workspace cleanup.

## Asset Boundary

Load `references/test-asset-boundaries.json` as the only machine-readable definition of the replaceable FlowTab product test-asset set. The shared contract, schemas, canonical indexer and repository composition/eval tooling form the reconstruction mechanism and remain available while that set is empty.

- Remove every `asset_boundaries` path when starting a full reconstruction.
- Resolve every structured `shared_carriers.test_owned_fragments` selector and preserve its fragment fingerprint and owned project identifiers in the clear plan.
- Generate `RECONSTRUCTION_CLEAR_PLAN.json` from the committed rollback anchor before clearing. Require clean owned paths, complete boundary classification, resolvable fragments, a canonical production-residual hash for every shared carrier and matching rollback/current HEAD identity.
- Remove the planned asset paths and shared-carrier fragments while preserving production-owned carrier content.
- Clear the `active_audit_root` before creating the next C0.
- Clear and recreate the `transient_reconstruction_root`, then retain its current clear plan through the empty-boundary gate.
- Resolve every stored path intent from its declared repository or Skill resource boundary immediately before access.

Use the same boundary manifest for routine discovery, reconstruction clearing, post-reconstruction indexing and composition validation.

## Record Model

Use the fixed schemas bundled beside this reference:

- `references/test-asset.schema.json`
- `references/validation-plan-row.schema.json`
- `references/execution-observation.schema.json`
- `references/asset-delta.schema.json`

Use `scripts/test_asset_model.py`, `scripts/test_asset_boundary.py`, `scripts/test_asset_clear_plan.py`, `scripts/test_asset_index.py` and `scripts/test_asset_views.py` as the executable structure, safety, discovery, validation and serialization path.

Keep these responsibilities distinct:

- `test_asset`: current executable identity, locator, fingerprint, Owner, layer capability, execution entry, dependencies and observed source references.
- `validation_plan_row`: transient task or reconstruction scope, scenario, requiredness, protected behavior, Oracle, Runner and prerequisites.
- `execution_observation`: one attempt's status, evidence and environment identity.
- `asset_delta`: lineage between two current working snapshots.

## Identity And Location

Persist every repository location as `{resource_boundary, relative_path_intent}`. Resolve the intent from the named resource boundary immediately before access.

Derive deterministic asset identity from the asset type and its type-specific key:

- test declaration: Target plus qualified test symbol;
- test file, Fixture, test data and TestingSupport: resource boundary plus path intent;
- Target or Scheme: project identity plus declared name;
- Runner: script path intent plus command interface;
- configuration: Owner plus path intent plus configuration key;
- Pressure scenario: Runner identity plus scenario name;
- capability probe: namespaced capability plus repository-owned declaration.

Keep identity separate from `asset_fingerprint`. Use SHA-256 over the owned source bytes for the fingerprint. Within an active full validation or reconstruction, represent moves, renames, merges and splits with `asset_delta` lineage basis, confidence, candidates and evidence. Resolve `unresolved` lineage before closing the owning run or slice.

## Discovery And Normalization

Run the canonical tooling from the `flowtab-engineering` Skill boundary:

```text
boundaries --output <json>
reconstruction-clear-plan --repository-root <path> --rollback-commit <commit> --output <json>
assert-reconstruction-empty --repository-root <path> --clear-plan <json>
index --repository-root <path> --scope all --output <jsonl>
index --repository-root <path> --scope paths --path-intent <path>... --output <jsonl>
assert-boundary-closure --repository-root <path> --ledger <jsonl>
delta --before <jsonl> --after <jsonl> --output <jsonl>
validate --record-kind <kind> --input <jsonl>
references --record-kind <kind> --input <jsonl> --record-id <id>... --output <json>
project --ledger <jsonl> --plan <jsonl> --observations <jsonl> --output <path>
schemas --check
rules --output <json>
```

Use `paths` only inside an active full validation for its selected scope or for Stage 02 slice generation. A path-scoped record set can describe an empty or partial reconstruction candidate while later slices remain absent; close the selected C1 slice only after its own dependencies resolve. Use `all` after reconstruction work to index the current candidate and at Stage 03 to establish final closure. Full indexing enforces boundary closure: every discovered asset belongs to one declared path or shared-carrier fragment, every owned file is indexed, every fragment produces its declared record, and every dependency resolves to a current asset. Require byte-identical canonical records for overlapping full and path-scoped outputs.

Treat index output as a description of the current asset candidate. Generate it after the relevant asset creation or edit. Exclude prior test assets, generated projections and prior Campaign records from full-reconstruction inputs.

Serialize canonical JSON as UTF-8 with stable object keys, deterministic record and set ordering, POSIX path intents, `[]` for empty collections and `null` for nullable fields. Keep attempt time, resolved local paths and machine-specific values inside execution envelopes.

## Protected Behavior And Oracle

Establish reconstruction scenarios from production paths and explicit behavior contracts. Use production implementation to identify current routing, ownership and dependencies. Confirm the protected result through an independent Oracle.

Build an Oracle from an explicit product or API contract, explicit input, stable external Fixture specification, independent observation, platform API or independent specification. Record its evidence and independence basis. Use `valid`, `provisional`, `missing` or `conflicting` for Oracle status.

After a test asset exists, record its current input, Fixture and assertion locations as `observed_test_semantics`. Keep those observations separate from protected behavior.

Record protected behavior in a validation-plan row as:

- `confirmed`: supported by decisive independent evidence;
- `inferred`: supported by repository evidence and awaiting confirmation;
- `ambiguous`: material interpretations remain unresolved.

## Existing-Test Semantic Guard

During routine engineering, add new test files, test methods and other additive declarations autonomously. Before changing or removing an existing test function or changing existing file-scope test semantics:

1. Establish the protected behavior, authoritative Owner and independent Oracle.
2. Identify the exact symbols and the current input, Fixture, assertion or expected-result conflict.
3. Ask the smallest question that resolves the intended product semantics.
4. After explicit clarification, authorize the pending token with `.codex/hooks/test_semantic_guard.py authorize <token> --note "<clarification summary>"`.
5. Retry the same candidate and retain the clarification summary with its handoff or C1 evidence.

A full reconstruction creates declarations from the confirmed validation plan after the empty-boundary gate. Existing test contents remain recovery-only Git history and do not enter scenario, Oracle or assertion design.

## Requiredness And Execution

Assign `required`, `optional` or `not_applicable` to each validation-plan row. Apply `risk-calibration.md`, `test-layer-boundaries.md` and `performance-pressure-workflow.md`; keep requiredness outside permanent asset records.

Record each attempt as `passed`, `failed`, `blocked`, `not_run`, `skipped`, `flaky` or `unknown`. Resolve `unknown` before completion. Classify a Required Skip caused by an unavailable external prerequisite as `blocked`, and a Required Skip caused by a Runner, test or configuration defect as `failed`. Treat unresolved Required Flake as failed closure.

Keep Mock UI and real-topology UI as separate plan rows. Aggregate applicable Required UI rows for an engineering handoff using `failed > blocked > not_run > passed`. Report Optional rows separately. When every UI row is `not_applicable`, report UI as `not relevant`.

## Routine Engineering

Update the applicable test source, Fixture, TestingSupport, configuration, Runner or prerequisite definition in the same task. Establish protected behavior and an independent Oracle, apply the existing-test semantic guard when required, inspect the tracked Git diff and run the risk-required validation layers.

During targeted and routine validation, `.build-local/test-assets` remains absent. When a selected full validation needs canonical records, run its complete entry through `scripts/test_asset_workspace.py`. When an active reconstruction owns the affected slice, give its Stage current execution observations through the reconstruction root.

## Full Reconstruction

Run full reconstruction only through `$flowtab-test-audit`:

1. Establish a dedicated branch or worktree and a committed rollback anchor.
2. Verify that every replaceable asset path is free of uncommitted user changes.
3. Clear the transient reconstruction root and generate its canonical clear plan from the rollback commit.
4. Clear the complete asset boundary, planned test-owned shared-carrier fragments and active audit root.
5. Pass `assert-reconstruction-empty` with the current clear plan. Require planned fragments and project identifiers to be absent and every shared carrier's production residual to retain its pre-clear hash.
6. Derive the reconstruction-scoped validation plan from production source and independent behavior evidence.
7. Rebuild assets slice by slice through C1 commits; let each C1 reference its selected validation-plan row IDs and hashes.
8. Generate the final full ledger beneath `.build-local`, pass boundary closure, execute every Required row and close C2.

Keep one current test-asset set in the working tree. Use Git commits to recover or inspect earlier sets.

## Shared Rule Snapshot And Drift

Load `references/shared-test-asset-rules.json` from the `flowtab-engineering` Skill boundary. Record each loaded role, path intent and SHA-256 plus the aggregate SHA-256 in C0; inherit and verify it in C1 and C2.

Classify resource drift by role:

- asset boundary, model, identity, locator, discovery or ownership: restart at Stage 01;
- requiredness, layer responsibility or Pressure: rebuild the affected validation plan and observations;
- protected behavior, Oracle or semantic guard: reopen the affected Stage 02 slice, returning to Stage 01 when topology changes;
- Runner, prerequisite or evidence contract: rerun affected plan rows;
- handoff presentation: revalidate the handoff fields.
