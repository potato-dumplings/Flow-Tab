# Stage 01: Test Assets and Pre-change Baseline

## Outcome

Establish a committed C0 anchor referencing a reconciled test-asset ledger, a trustworthy pre-change baseline, classified findings and initial dependency-slice topology. Accept failed, flaky, skipped, blocked and causal `not_run` baseline rows when their evidence, Owner and recovery information are complete.

## Entry

- Establish the audit scope and target branch, default the campaign to `commit_policy=commit_on_stage_complete`, honor an explicit pre-campaign `prepare_only` request, and freeze the resulting policy.
- Record HEAD, branch, dirty paths, toolchain, signing and permission prerequisites, material assumptions and unknowns.
- Preserve user-owned changes and select a reconstructible audited snapshot with unambiguous dirty-path ownership.
- Resolve evidence and build-root path intents beneath the current repository's ignored `.build-local/` boundary.
- Start when no current C0 anchor exists or when its snapshot, asset plan or baseline identity is stale.

## Work

1. Discover test cases and methods, Target memberships, Runners, Fixtures and configuration, TestingSupport, Schemes, Pressure scenarios, test data, external prerequisites and the stable scenarios in `docs/TEST_COVERAGE_MATRIX.md`.
2. Give every asset a stable ID and reconcile source file, symbol, Target membership, layer, Runner, Fixture, TestingSupport, Owner, product scenario, Oracle, dependencies, consumers, Skip/timeout behavior, permissions and execution entry point. Use an explicit `not_applicable` value for fields that do not apply to an asset class.
3. Reconcile assets and stable product scenarios in both directions. Record duplicates, orphans, target drift, missing Owners, missing Oracles and unmapped scenarios as findings.
4. Build the smallest dependency-aware baseline command plan with the canonical repository commands. State requiredness, prerequisites, expected artifacts and evidence channel for every row.
5. Run the pre-change baseline against the frozen snapshot. Allocate a fresh attempt path for every dynamic command and retain result bundles, logs, status, exit codes, environment identity and artifact identity.
6. Classify every result as `passed`, `failed`, `flaky`, `skipped`, `blocked`, `not_run`, or `unknown`. Assign a decisive signal, Owner, affected layer, unproven fact and minimum recovery action to each non-green result.
7. Cluster shared signals, seed the dependency DAG, record interaction risks, and produce the first entry-ready slice candidates without treating a heuristic cluster as a proven root cause.
8. Publish the asset ledger to `docs/test-audit/TEST_ASSET_LEDGER.jsonl`, baseline rows to `docs/test-audit/BASELINE_RESULTS.jsonl`, and C0 to `docs/test-audit/C0_HANDOFF.json`. C0 references the two datasets and includes the audited snapshot, reconciliation summary, command plan, findings, blockers, dependency topology, first slice candidates and resume points.

## Completion

- Reconcile every active asset to exactly one stable identity and complete its applicable Target, Runner, Fixture and Owner fields with explicit `not_applicable` values where needed.
- Make the command plan, requiredness, snapshot and evidence references reproducible.
- Give every Required baseline row a trustworthy observation, a current evidenced external blocker, or a typed causal `not_run` from a verified upstream result.
- Resolve every `unknown`, stale or corrupt evidence item, identity mismatch and Runner-contract breach.
- Keep baseline failures, unexpected Skip, Flake and performance regression as explicit findings with Owners and downstream slice effects.
- Validate C0 and its exact stage-owned file set. Completion makes the C0 candidate eligible for Commit.

## Commit

- Limit the candidate to Stage 01 audit facts, `docs/test-audit/TEST_ASSET_LEDGER.jsonl`, `docs/test-audit/BASELINE_RESULTS.jsonl` and `docs/test-audit/C0_HANDOFF.json`.
- Apply the shared `commit_policy` with title `test-audit(baseline): establish FlowTab test baseline`.
- Use the resulting commit as the C0 anchor consumed by Stage 02 and Stage 03.

## Blocked and Resume

- For an unreconstructible snapshot or ambiguous dirty ownership, record the conflict and resume at Entry snapshot selection.
- For incomplete asset or ownership reconciliation, resume at the affected discovery or reconciliation row.
- For a missing canonical Runner, evidence path or artifact contract, resume at command planning after the capability is restored.
- For an unavailable external prerequisite, retain completed observations and resume the affected baseline row when the snapshot and plan remain current.
- Treat a current evidenced external blocker with an Owner and recovery action as a classified baseline result; enter `BLOCKED` when the baseline cannot classify the Required row trustworthily.
- For a policy-authorized Commit failure, preserve the eligible candidate and resume at Commit when its snapshot and exact file set remain current.
- Record the shared blocker fields from `SKILL.md` and identify every slice that remains independently runnable.
