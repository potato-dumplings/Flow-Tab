# UI Automation Prerequisites

Use this reference before declaring FlowTab UI automation blocked by the environment.

FlowTab UI failures often come from repository-specific setup. Complete these checks before classifying permission-like failures, missing windows, or real-environment workflow failures as unexplained blockers.

## Required Outcome

- Prepare a fixed-path UI test app before relying on UI automation for local validation.
- Verify the permissions and designated requirements that macOS actually uses for privacy decisions.
- Use the repository scripts in the recommended order before escalating to an environment blocker.
- For audit runs, give the UI wrapper a fresh attempt-specific output root so prior result bundles and xcodebuild logs remain intact.
- Keep audit build roots, output roots, and private manifests inside the current project under the Git-ignored `./.build-local/` tree.
- Persist each project-local location as `{resource_boundary: repository_root, relative_path_intent: <relative-path>}` and resolve it against the current repository root at the resource-owning boundary immediately before use.
- Keep normal non-audit wrapper calls without output overrides available.
- Distinguish sandbox or cache failures from permission, bundle-path, or code-identity mismatches.

## Standard Local Setup

1. Install a fixed-path UI test app:

```bash
./scripts/testing/install-ui-test-app.sh
```

Default install path:

- `~/Applications/Flow Tab UITest.app`

The script uses `FLOWTAB_DEVELOPMENT_TEAM`. When the current shell does not export that variable, the script reads the same setting from `xcconfigs/LocalSigning.xcconfig`. When a matching local `Apple Development` identity exists, the script signs the fixed-path app. When none exists, it keeps the default ad hoc installation so the fixed path can still be refreshed.

2. Grant these permissions to that fixed-path app in macOS:

- `System Settings -> Privacy & Security -> Accessibility`
- `System Settings -> Privacy & Security -> Screen & System Audio Recording`

Before running real-workflow tests, open the same fixed-path app once. The first launch is the permission-acquisition step: complete the macOS prompts or use FlowTab's permission UI, quit FlowTab, relaunch the same app path, and confirm that FlowTab has cleared the Home permission gate.

3. Run UI automation through the repository wrapper:

```bash
./scripts/testing/run-ui-tests-local.sh
```

The script prefers `~/Applications/Flow Tab UITest.app` when it exists. When the fixed-path app is absent, it falls back to the DerivedData build product.

## Audit Evidence Run

Allocate attempt-specific build and output leaf paths under the current project's ignored `./.build-local/test-audit/` tree. Leave the output leaf absent and pass both paths to the UI wrapper:

```bash
./scripts/testing/run-ui-tests-local.sh \
  --build-root ./.build-local/test-audit/<campaign-id>/build/<command-id> \
  --output-root ./.build-local/test-audit/<campaign-id>/<attempt-id>
```

The wrapper creates the attempt directory and rejects an existing path. Resolve stored path intents against the current repository root immediately before invocation. A test action preserves `results/FlowTabUITests.xcresult`; build and test stages preserve `logs/xcodebuild-<action>.log`; fixture preparation and runner signing preserve their own stage logs; and `status.json` preserves every child-process and log-writer exit code. Evidence validation fails when a test action does not produce a result bundle. Inventory these files before starting the next attempt. Normal non-audit runs that use the fixed local paths omit the audit overrides.

For a runtime-topology pressure audit, first run `create-ui-app-identity-manifest.sh --app-path <fixed-app> --output-file <new-project-local-private-manifest>`. Pass that manifest and a fresh `--output-dir` leaf to `runtime-topology-pressure.sh`. The pressure wrapper passes `attempts/ui-tests/run/` to this UI wrapper as the child `--output-root`; the pressure root retains the launch receipt, per-sample PID bindings, FlowTab samples, aggregate UI logs and summary, and the top-level `status.json`.

## Why The Fixed Path Matters

- macOS privacy decisions recognize the app's designated requirement, including the installed identity and path context.
- A `FlowTabUITests` run that launches a DerivedData product can present a different privacy identity from the authorized app.
- A test run that appears to have lost permission commonly indicates a path or identity mismatch.
- Stable reuse in this project requires mutually compatible designated requirements with the same signing identifier (`io.github.potato-dumplings.flowtab`) and Apple Developer Team.
- An Apple Development build's `CDHash` can change across rebuilds, so use it as supporting evidence for an ad hoc or build-specific signature.

## Real-Environment And Multi-App Workflow Prerequisites

For UI tests that launch real fixture apps, drive Home or the switcher from live runtime state, or validate multi-app Space workflows, verify all of the following:

- FlowTab has `Accessibility` permission.
- FlowTab has `Screen & System Audio Recording` permission.
- `Flow Tab.app` and `Flow Tab UITest.app` have mutually compatible macOS designated requirements.

Important interpretation:

- macOS privacy permission binds to the app's designated requirement; the bundle ID, app name, and Team ID are components of that identity.
- An ad hoc `/Applications/Flow Tab.app` and an Apple Development-signed `~/Applications/Flow Tab UITest.app` can receive separate privacy decisions.
- When a real-environment workflow still shows a permission reminder after permission was granted, inspect the launched app path and designated requirement before classifying the condition as a blocker.

## Recommended Setup For Stable Real-Environment UI Runs

1. When a stable local development-signing identity is available, install the fixed-path UI test app with that identity:

```bash
./scripts/testing/install-ui-test-app.sh
```

Use `--development-team <TEAM_ID>` only when the current run requires a different team.

2. Open the fixed-path app that the UI test will launch. For the default wrapper path:

```bash
open "$HOME/Applications/Flow Tab UITest.app"
```

3. Grant `Accessibility` and `Screen & System Audio Recording` to that app, quit FlowTab, relaunch the same path, and confirm that the Home permission gate is clear.

4. To reuse an existing `/Applications/Flow Tab.app` grant, ensure that the UI test app has the same signing identifier and Apple Developer Team in mutually compatible designated requirements. Stable reuse requires the complete compatible designated requirement.

5. Run:

```bash
./scripts/testing/run-ui-tests-local.sh
```

For an auditable run, add fresh project-local `--build-root` and `--output-root <not-yet-existing-attempt-directory>` paths as described in [Audit Evidence Run](#audit-evidence-run).

## Proven Permission-Reuse Flow

Use this sequence when validating whether the fixed-path app can reuse an already-authorized `/Applications/Flow Tab.app` grant:

```bash
./scripts/testing/install-ui-test-app.sh
codesign -dr - "$HOME/Applications/Flow Tab UITest.app"
codesign -dr - "/Applications/Flow Tab.app"
open -n "$HOME/Applications/Flow Tab UITest.app"
./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelWindowSearchActivatesFullscreenWorkflowWindowAcrossSpaces
```

Treat permission acquisition or reuse as successful when:

- `install-ui-test-app.sh` signs the fixed-path app with `Apple Development`.
- Both apps report the signing identifier `io.github.potato-dumplings.flowtab`, and `codesign -dr -` shows compatible Apple Development designated requirements.
- The UI wrapper prints `UI test app: {user-home}/Applications/Flow Tab UITest.app`.
- The UI log reaches the real-fixture markers, opens FlowTab, clears `flowtab.home.permission.open-settings`, and continues to `flowtab.switcher.search.input` or `flowtab.switcher.search.window.*`.

Permission acquisition is proven by those signals. If the test later fails in switcher, search-result, activation, or XCUI snapshot assertions, continue diagnosing that layer and classify its actual result.

When running from Codex or another restricted sandbox, the install script can misreport that no local Apple Development identity is available or fail while SwiftPM creates temporary files. Retry the installation from a normal Terminal, or from an environment with approved access to the local keychain and Xcode temporary/cache locations, before concluding that the machine lacks the signing identity.

## Before Reporting A UI Environment Blocker

Check these in order:

1. Was `./scripts/testing/install-ui-test-app.sh` run?
2. Does `~/Applications/Flow Tab UITest.app` exist?
3. Was `./scripts/testing/run-ui-tests-local.sh` used?
4. For an audit run, did the wrapper receive fresh project-local `--build-root` and `--output-root` paths, and did the output retain the result bundle, fixture/signing/xcodebuild logs, and `status.json`?
5. Does the fixed-path UI test app have `Accessibility` permission?
6. Does the fixed-path UI test app have `Screen & System Audio Recording` permission?
7. For real-environment or multi-app workflows, do `Flow Tab.app` and `Flow Tab UITest.app` have mutually compatible designated requirements?
8. After those checks, classify any remaining sandbox, cache, or external-environment blocker.

## Common Misdiagnoses

- `windows=0` commonly indicates a permission or authorized-path mismatch.
- Preview content without real frames commonly indicates missing screen-recording permission.
- UI automation that repeatedly loses permission commonly launches a DerivedData app with a different privacy identity.
- A real multi-app workflow that still shows permission reminders commonly launches an unauthorized app path or uses incompatible designated requirements between `Flow Tab.app` and `Flow Tab UITest.app`.
