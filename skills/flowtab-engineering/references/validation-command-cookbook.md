# Validation Command Cookbook

Use this reference when choosing concrete local commands for FlowTab validation. Prefer the smallest command that proves the affected layer, then broaden when shared behavior or wiring changed.

## General Rules

- Keep repository-local build products, caches, raw evidence, and private manifests under `./.build-local/`. The repository's `.gitignore` excludes this tree so the same relative layout can move with any checkout.
- Persist project-local locations as `{resource_boundary: repository_root, relative_path_intent: <relative-path>}`. Resolve each intent against the current repository root at the resource-owning boundary immediately before use.
- Use a distinct `-derivedDataPath` for before-change and after-change runs when comparing bugfix signals.
- Use `-only-testing:` filters for targeted validation first, then broaden when the touched code is shared.
- For an audit run, allocate a fresh attempt-specific output path and leave its leaf absent. Pass it to the repository wrapper, which atomically creates the directory and rejects reuse so prior evidence remains intact.
- Resolve `--build-root`, `--scratch-path`, and `-derivedDataPath` below the current project's ignored `./.build-local/` tree.
- Normal non-audit calls can omit audit-output options and continue using the existing fixed local paths.
- Report the command, outcome, and validation layer. For audit work, Git-tracked reports use a redacted command ID/hash while non-secret argv, secret references, and resolved local paths remain in the ignored private evidence manifest. Report sandbox, permission, code-identity, or missing-fixture blockers explicitly.

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
cd FlowTabCore
swift test
```

Target a single SwiftPM test by name when narrowing a signal:

```bash
cd FlowTabCore
swift test --filter SwitcherSessionTests
```

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
  -only-testing:FlowTabTests/FlowTabTests/testSearchPerformanceWindowScope
```

For an audit attempt, pass fresh project-local build and output leaves:

```bash
./scripts/testing/run-flowtabtests-local.sh \
  --build-root ./.build-local/test-audit/<campaign-id>/build/<command-id> \
  --output-root ./.build-local/test-audit/<campaign-id>/<attempt-id>
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
  -only-testing:FlowTabUITests/FlowTabUITests/testHomePageSelectingMockAppUpdatesWindowList
```

For an audit attempt, pass fresh project-local build and output leaves:

```bash
./scripts/testing/run-ui-tests-local.sh \
  --build-root ./.build-local/test-audit/<campaign-id>/build/<command-id> \
  --output-root ./.build-local/test-audit/<campaign-id>/<attempt-id>
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
  --build-root ./.build-local/test-audit/<campaign-id>/build/<command-id-20ms> \
  --output-dir ./.build-local/test-audit/<campaign-id>/<attempt-20ms>
./scripts/perf/tab-switch-stress.sh 20 50 0.5 \
  --build-root ./.build-local/test-audit/<campaign-id>/build/<command-id-50ms> \
  --output-dir ./.build-local/test-audit/<campaign-id>/<attempt-50ms>
```

Each output directory preserves `samples.csv`, `summary.txt`, `build.log`, `app.log`, and `status.json`. Every run uses a fresh attempt directory; the script atomically creates the leaf and rejects reuse. The summary reports CPU/RSS `avg/p95/max`, and `status.json` preserves build, app, sampling, summary, and log-writer results. Positional-only non-audit calls remain supported and receive a unique default directory under `./.build-local/tab-switch-stress/`.

Search quick regression for the current deterministic high-window-count path:

```bash
./scripts/testing/run-flowtabtests-local.sh \
  -only-testing:FlowTabTests/FlowTabTests/testSearchPerformanceWindowScope \
  -only-testing:FlowTabTests/FlowTabTests/testSearchPressureWindowScopeUnified
```

Full search pressure still requires external `%CPU` and `RSS` sampling for at least `30s` per scenario. Use `performance-pressure-workflow.md` for the required dataset, cadence, and reporting fields.

Runtime topology pressure for the representative noisy fullscreen/off-space fixture path:

```bash
./scripts/perf/runtime-topology-pressure.sh 0.5
```

The wrapper runs the four-window Noisy Option+Tab UI fixture and samples the `FlowTab` process CPU/RSS into `./.build-local/runtime-topology-pressure/`. Use it when validating Space topology, fullscreen/off-space activation, or repeated topology-aware panel interaction pressure.

## Validation Report Shape

Use this compact shape unless the task needs a full handoff:

- Unit: `passed`, `failed`, `blocked`, or `not relevant`; include command or reason.
- Behavior: `passed`, `failed`, `blocked`, or `not relevant`; include command or reason.
- UI: `passed`, `failed`, `blocked`, or `not relevant`; include command or reason.
- Pressure: `passed`, `failed`, `blocked`, or `not relevant`; include command, baseline, or reason.
