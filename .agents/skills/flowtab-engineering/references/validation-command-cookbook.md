# Validation Command Cookbook

Use this reference when choosing concrete local commands for FlowTab validation. Prefer the smallest command that proves the affected layer, then broaden when shared behavior or wiring changed.

## Contents

- [General Rules](#general-rules)
- [Test Asset Tooling](#test-asset-tooling)
- [Build](#build)
- [FlowTabCore Unit Tests](#flowtabcore-unit-tests)
- [App Unit And Behavior Tests](#app-unit-and-behavior-tests)
- [UI Tests](#ui-tests)
- [Space Fixture Workflow](#space-fixture-workflow)
- [Pressure Checks](#pressure-checks)
- [Validation Report Shape](#validation-report-shape)

## General Rules

- Keep repository-local build products, caches, raw evidence, and private manifests under `./.build-local/`. The repository's `.gitignore` excludes this tree so the same relative layout can move with any checkout.
- Persist project-local locations as `{resource_boundary: repository_root, relative_path_intent: <relative-path>}`. Resolve each intent against the current repository root at the resource-owning boundary immediately before use.
- Use distinct before-change and after-change build-root intents when comparing bugfix signals: SwiftPM `--scratch-path`, repository wrappers `--build-root`, and direct `xcodebuild` `-derivedDataPath`.
- Use `-only-testing:` filters for targeted validation first, then broaden when the touched code is shared.
- For an audit run, allocate a fresh attempt-specific output path and leave its leaf absent. Pass it to the repository wrapper, which atomically creates the directory and rejects reuse so prior evidence remains intact.
- Resolve `--build-root`, `--scratch-path`, and `-derivedDataPath` below the current project's ignored `./.build-local/` tree.
- Normal non-audit calls can omit audit-output options and continue using the existing fixed local paths.
- Report the command, outcome, and validation layer. For audit work, Git-tracked reports use a redacted command ID/hash while non-secret argv, secret references, and resolved local paths remain in the ignored private evidence manifest. Report sandbox, permission, code-identity, or missing-fixture blockers explicitly.

## Test Asset Tooling

Resolve the `flowtab-engineering` Skill root, then use its canonical indexer. For a routine task, capture the same path scope before and after edits:

```bash
python3 .agents/skills/flowtab-engineering/scripts/test_asset_index.py index \
  --repository-root . \
  --scope paths \
  --path-intent <task-owned-path> \
  --output .build-local/test-assets/<task-id>/before.jsonl

python3 .agents/skills/flowtab-engineering/scripts/test_asset_index.py index \
  --repository-root . \
  --scope paths \
  --path-intent <task-owned-path> \
  --output .build-local/test-assets/<task-id>/after.jsonl

python3 .agents/skills/flowtab-engineering/scripts/test_asset_index.py delta \
  --before .build-local/test-assets/<task-id>/before.jsonl \
  --after .build-local/test-assets/<task-id>/after.jsonl \
  --output .build-local/test-assets/<task-id>/asset-delta.jsonl
```

For a full reconstruction, clear `.build-local/test-audit/rebuild/`, materialize the shared boundary definition and generate the safety-qualified clear plan from the committed rollback anchor:

```bash
python3 .agents/skills/flowtab-engineering/scripts/test_asset_index.py boundaries \
  --output .build-local/test-audit/rebuild/asset-boundaries.json

python3 .agents/skills/flowtab-engineering/scripts/test_asset_index.py reconstruction-clear-plan \
  --repository-root . \
  --rollback-commit <rollback-commit> \
  --output .build-local/test-audit/rebuild/RECONSTRUCTION_CLEAR_PLAN.json
```

Clear exactly the planned asset paths and shared-carrier fragments, clear `docs/test-audit/`, then run the empty-boundary gate against the retained plan:

```bash

python3 .agents/skills/flowtab-engineering/scripts/test_asset_index.py assert-reconstruction-empty \
  --repository-root . \
  --clear-plan .build-local/test-audit/rebuild/RECONSTRUCTION_CLEAR_PLAN.json
```

Use path scope for each Stage 02 slice. Generate the selected validation-plan references for C1 from canonical rows:

```bash
python3 .agents/skills/flowtab-engineering/scripts/test_asset_index.py references \
  --record-kind validation_plan_row \
  --input .build-local/test-audit/rebuild/VALIDATION_PLAN.jsonl \
  --record-id <plan-row-id> \
  --output .build-local/test-audit/rebuild/slices/<slice-id>/VALIDATION_PLAN_REFS.json
```

Use `--scope all` at Stage 03 to generate the final current ledger under `.build-local/test-audit/rebuild/`; full indexing applies boundary closure automatically. Run the explicit closure command when producing reusable evidence:

```bash
python3 .agents/skills/flowtab-engineering/scripts/test_asset_index.py assert-boundary-closure \
  --repository-root . \
  --ledger .build-local/test-audit/rebuild/TEST_ASSET_LEDGER.jsonl \
  --output .build-local/test-audit/rebuild/BOUNDARY_CLOSURE.json
```

Validate generated rows with the matching `validate --record-kind` command. Keep routine and reconstruction datasets under `.build-local`; commit only current C0/C1/C2 anchors through the audit Stage.

## Build

Use this for compile-only validation or mechanical refactors that do not need tests:

```bash
xcodebuild \
  -project FlowTab.xcodeproj \
  -scheme FlowTab \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath ./.build-local/build \
  build
```

## FlowTabCore Unit Tests

Use this for pure `FlowTabCore` models, grouping, preferences, switcher sessions, and other deterministic rules:

```bash
swift test \
  --package-path FlowTabCore \
  --scratch-path ./.build-local/flowtabcore-tests
```

Target a single SwiftPM test by name when narrowing a signal:

```bash
swift test \
  --package-path FlowTabCore \
  --scratch-path ./.build-local/flowtabcore-tests \
  --filter <TestClassOrMethod>
```

For a before/after bugfix comparison, use distinct scratch roots such as `./.build-local/flowtabcore-tests/before` and `./.build-local/flowtabcore-tests/after`.

## App Unit And Behavior Tests

Use this for `FlowTabTests`, including app-scoped unit tests and in-process behavior tests.

Before running or reporting these commands, follow `flowtabtests-workflow.md`. That workflow controls signing setup, allowed command variations, blocked outcomes, and handoff reporting.

Full target:

```bash
./scripts/testing/run-flowtabtests-local.sh
```

Target one class or method while reproducing or iterating:

```bash
./scripts/testing/run-flowtabtests-local.sh \
  -only-testing:FlowTabTests/<ClassName>/<testMethod>
```

For an audit attempt, pass fresh project-local build and output leaves:

```bash
./scripts/testing/run-flowtabtests-local.sh \
  --build-root ./.build-local/test-audit/rebuild/build/<command-id> \
  --output-root ./.build-local/test-audit/rebuild/attempts/<attempt-id>
```

The wrapper creates the attempt directory and rejects reuse. It writes the test result bundle to `results/FlowTabTests.xcresult`, the action log to `logs/xcodebuild-<action>.log`, and child-process/log-writer exit codes to `status.json`. A `build-for-testing` action produces a log without a test result bundle.

## UI Tests

Prepare a stable fixed-path app before relying on UI automation:

```bash
./scripts/testing/install-ui-test-app.sh
```

Then run UI tests through the wrapper so temporary directories and caches stay under `./.build-local/ui-tests`:

```bash
./scripts/testing/run-ui-tests-local.sh
```

Target a single UI test while iterating:

```bash
./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/<ClassName>/<testMethod>
```

For an audit attempt, pass fresh project-local build and output leaves:

```bash
./scripts/testing/run-ui-tests-local.sh \
  --build-root ./.build-local/test-audit/rebuild/build/<command-id> \
  --output-root ./.build-local/test-audit/rebuild/attempts/<attempt-id>
```

The wrapper creates the attempt directory and rejects reuse. It writes the UI test result bundle to `results/FlowTabUITests.xcresult`, writes build/test output to `logs/xcodebuild-<action>.log`, retains fixture and signing stage logs, and records child-process/log-writer exit codes in `status.json`. A standalone `build-for-testing` action produces logs without a test result bundle.

Use `ui-automation-prerequisites.md` before declaring UI automation blocked. Common blockers include missing Accessibility permission, missing Screen & System Audio Recording permission, a fixed-path app mismatch, a code-identity mismatch, and sandboxed temporary/cache access.

## Space Fixture Workflow

Use these scripts when a UI scenario depends on real fixture apps or generated workflow variants:

```bash
./scripts/testing/build-space-fixture-app.sh \
  --app-name "Chrome Fixture" \
  --bundle-id "com.example.chrome.fixture"

./scripts/testing/build-space-fixture-workflow.sh \
  --workflow-config docs/fixtures/space-fixture-switcher-multi-app-workflow.json
```

Then run the relevant `FlowTabUITests` case through `run-ui-tests-local.sh`.

## Pressure Checks

Tab-switch pressure:

```bash
./scripts/perf/tab-switch-stress.sh 20 20 0.5 \
  --build-root ./.build-local/test-audit/rebuild/build/<command-id-20ms> \
  --output-dir ./.build-local/test-audit/rebuild/attempts/<attempt-20ms>
./scripts/perf/tab-switch-stress.sh 20 50 0.5 \
  --build-root ./.build-local/test-audit/rebuild/build/<command-id-50ms> \
  --output-dir ./.build-local/test-audit/rebuild/attempts/<attempt-50ms>
```

Each output directory preserves `samples.csv`, `summary.txt`, `build.log`, `app.log`, and `status.json`. Every run uses a fresh attempt directory; the script atomically creates the leaf and rejects reuse. The summary reports CPU/RSS `avg/p95/max`, and `status.json` preserves build, app, sampling, summary, and log-writer results. Positional-only non-audit calls remain supported and receive a unique default directory under `./.build-local/tab-switch-stress/`.

Full search pressure still requires process-level `%CPU` and `RSS` sampling for at least `30s` per scenario. Use `performance-pressure-workflow.md` for the required dataset, cadence, and reporting fields.

Committed-index process-level search pressure:

```bash
./scripts/perf/search-committed-index-pressure.sh 0.5 \
  --scenario realistic \
  --scenario-duration-seconds 30 \
  --build-root ./.build-local/test-audit/rebuild/build/<realistic-command-id> \
  --output-dir ./.build-local/test-audit/rebuild/attempts/<search-attempt-id>

./scripts/perf/search-committed-index-pressure.sh 0.5 \
  --scenario stress \
  --scenario-duration-seconds 30 \
  --build-root ./.build-local/test-audit/rebuild/build/<stress-command-id> \
  --output-dir ./.build-local/test-audit/rebuild/attempts/<search-stress-attempt-id>
```

The output leaf must not exist before the run. The wrapper preserves `process-samples.csv`, `summary.txt`, aggregate logs, `child-attempts.jsonl`, and `status.json`. Its `build-for-testing` invocation and every `test-without-building` batch receive a distinct `attempts/flowtabtests/<child-attempt-id>/` output root, so every test batch retains its own result bundle, xcodebuild log, and child status.

Runtime-topology pressure for the representative noisy fullscreen/off-Space fixture path:

```bash
./scripts/testing/create-ui-app-identity-manifest.sh \
  --app-path "$HOME/Applications/Flow Tab UITest.app" \
  --output-file ./.build-local/test-audit/rebuild/private/<ui-app-identity>.json

./scripts/perf/runtime-topology-pressure.sh 0.5 \
  --ui-app-identity-manifest ./.build-local/test-audit/rebuild/private/<ui-app-identity>.json \
  --build-root ./.build-local/test-audit/rebuild/build/<command-id> \
  --output-dir ./.build-local/test-audit/rebuild/attempts/<topology-attempt-id>
```

The identity-manifest leaf and output-directory leaf must not exist before the run. The wrapper runs the four-window Noisy Option+Tab UI fixture, samples CPU/RSS for the uniquely bound `FlowTab` process, and preserves `flowtab-samples.csv`, `pid-bindings.csv`, `target-launch-receipt.json`, `summary.txt`, aggregate logs, and the top-level `status.json`. The inner UI wrapper receives the unique `attempts/ui-tests/run/` output root, which retains the result bundle, stage logs, and child status. Use this path for Space topology, fullscreen/off-Space activation, or repeated topology-aware panel-interaction pressure. A normal non-audit run can omit `--output-dir`; the script then creates a unique default result directory.

## Validation Report Shape

Use this compact shape unless the task needs the full handoff from `handoff-contract.md`:

- Unit: `passed`, `failed`, `blocked`, `not relevant`, or `not run`; include the command or reason.
- Behavior: `passed`, `failed`, `blocked`, `not relevant`, or `not run`; include the command or reason.
- UI: `passed`, `failed`, `blocked`, `not relevant`, or `not run`; include the command or reason.
- Pressure: `passed`, `failed`, `blocked`, `not relevant`, or `not run`; include the command, baseline, or reason.
- Process/Tooling: `passed`, `failed`, `blocked`, or `not run`; include every applicable structural, path, command-contract, protocol, package, or eval check.
