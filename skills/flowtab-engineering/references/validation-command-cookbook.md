# Validation Command Cookbook

Use this reference when choosing concrete local commands for FlowTab validation. Prefer the smallest command that proves the affected layer, then broaden when shared behavior or wiring changed.

## General Rules

- Prefer repository-local build products and caches under `./.build-local`.
- Use a distinct `-derivedDataPath` for before-change and after-change runs when comparing bugfix signals.
- Use `-only-testing:` filters for targeted validation first, then broaden when the touched code is shared.
- Report the command, outcome, and layer. If a command is blocked by sandbox, permissions, code identity, or missing fixtures, report that blocker explicitly.

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

Use this for pure `FlowTabCore` models, grouping, preferences, switcher session, and other deterministic rules:

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

Use this for `FlowTabTests`, including app-scoped unit tests and in-process behavior tests:

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

## UI Tests

Prepare a stable fixed-path app before relying on UI automation:

```bash
./scripts/testing/install-ui-test-app.sh
```

Then run UI tests through the wrapper so temp directories and caches stay under `./.build-local/ui-tests`:

```bash
./scripts/testing/run-ui-tests-local.sh
```

Target a single UI test while iterating:

```bash
./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testHomePageSelectingMockAppUpdatesWindowList
```

Use `ui-automation-prerequisites.md` before declaring UI automation blocked. Common blockers include missing Accessibility permission, missing Screen & System Audio Recording permission, fixed-path app mismatch, code-identity mismatch, and sandboxed temp/cache access.

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

Tab switching pressure:

```bash
./scripts/perf/tab-switch-stress.sh 20 20 0.5
./scripts/perf/tab-switch-stress.sh 20 50 0.5
```

Search quick regression for the current high-window deterministic path:

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
