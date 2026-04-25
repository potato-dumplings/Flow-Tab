# UI Automation Prerequisites

Use this reference before declaring FlowTab UI automation blocked by the environment.

FlowTab UI failures are often caused by repository-specific setup issues rather than generic XCTest instability. Do not treat permission-like failures, missing windows, or real-environment workflow failures as unexplained blockers until these checks are complete.

## Required Outcome

- Prepare a fixed-path UI test app before relying on UI automation for local verification.
- Confirm the permissions and designated requirement that macOS actually uses for privacy gating.
- Use the repository scripts in the recommended order before escalating to an environment blocker.
- Distinguish sandbox or cache failures from permission, bundle-path, or code-identity mismatches.

## Standard Local Preparation

1. Install the fixed-path UI test app:

```bash
./scripts/testing/install-ui-test-app.sh
```

Default install path:

- `~/Applications/Flow Tab UITest.app`

The script uses `FLOWTAB_DEVELOPMENT_TEAM`. If it is not exported in the
current shell, the script reads the same setting from
`xcconfigs/LocalSigning.xcconfig`. With a matching local `Apple Development`
identity, the script signs the fixed-path app; without one, it keeps the
default adhoc install so the fixed path can still be refreshed.

2. Grant permissions to that fixed-path app in macOS:

- `System Settings -> Privacy & Security -> Accessibility`
- `System Settings -> Privacy & Security -> Screen & System Audio Recording`

Open the same fixed-path app once before running the real workflow tests. The
first launch is the permission-acquisition step: complete the macOS prompts or
use FlowTab's permission UI, quit FlowTab, relaunch the same app path, and only
continue when FlowTab no longer shows the home permission gate.

3. Run UI automation through the repository wrapper:

```bash
./scripts/testing/run-ui-tests-local.sh
```

That script prefers `~/Applications/Flow Tab UITest.app` when it exists. It only falls back to a `DerivedData` build product when the fixed-path app is missing.

## Why Fixed Path Matters

- macOS privacy permissions are sensitive to the app's designated requirement, not only to the bundle name.
- If `FlowTabUITests` launches a `DerivedData` product directly, macOS may not treat it as the already-authorized app.
- A test run that looks like "permissions disappeared again" is often a path or identity mismatch, not a flaky test.
- `TeamIdentifier` alone is not the complete privacy identity. For this project,
  stable reuse usually means the same signing identifier
  (`io.github.potato-dumplings.flowtab`) and the same Apple Developer Team in a
  mutually compatible designated requirement.
- Do not use `CDHash` equality as the main criterion for Apple Development signed
  builds; it can change across rebuilds. Use it only as supporting evidence for
  adhoc or build-specific signatures.

## Real-Environment And Multi-App Workflow Prerequisites

These checks are required for UI tests that launch real fixture apps, drive the Home page or switcher against live runtime state, or verify multi-app space workflows:

- FlowTab has `Accessibility`
- FlowTab has `Screen & System Audio Recording`
- `Flow Tab.app` and `Flow Tab UITest.app` have mutually compatible macOS designated requirements

Important interpretation:

- macOS privacy permissions are bound to the app's designated requirement, not just bundle id, app name, or Team ID.
- If `/Applications/Flow Tab.app` is still `adhoc` but `~/Applications/Flow Tab UITest.app` is signed with `Apple Development`, the system may not reuse the granted permissions.
- When a real-environment workflow still shows permission reminders after permissions were granted, first check the actual launched app path and designated requirement mismatch before calling it a blocker.

## Recommended Preparation For Stable Real-Environment UI Runs

1. Install a fixed-path UI test app with a stable local development signing identity when available:

```bash
./scripts/testing/install-ui-test-app.sh
```

Use `--development-team <TEAM_ID>` only when the run needs a different team.

2. Open the fixed-path app that UI tests will actually launch. For the default wrapper path:

```bash
open "$HOME/Applications/Flow Tab UITest.app"
```

3. Grant `Accessibility` and `Screen & System Audio Recording` to that app,
   quit FlowTab, then relaunch the same path and confirm the home permission gate
   is gone.

4. If you want to reuse the existing `/Applications/Flow Tab.app` grant, ensure
   the UI test app has the same signing identifier and same Apple Developer Team
   in a mutually compatible designated requirement. Same Team ID alone is not
   enough; adhoc builds do not provide stable reuse.

5. Run:

```bash
./scripts/testing/run-ui-tests-local.sh
```

## Proven Permission-Reuse Flow

Use this sequence when validating whether the fixed-path app can reuse an
already-authorized `/Applications/Flow Tab.app` grant:

```bash
./scripts/testing/install-ui-test-app.sh
codesign -dr - "$HOME/Applications/Flow Tab UITest.app"
codesign -dr - "/Applications/Flow Tab.app"
open -n "$HOME/Applications/Flow Tab UITest.app"
./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelWindowSearchActivatesFullscreenWorkflowWindowAcrossSpaces
```

Treat permission acquisition or reuse as successful when:

- `install-ui-test-app.sh` signs the fixed-path app with `Apple Development`,
  not `adhoc`.
- Both apps report the same signing identifier
  (`io.github.potato-dumplings.flowtab`) and compatible Apple Development
  designated requirements from `codesign -dr -`.
- The UI wrapper prints
  `UI test app: {user-home}/Applications/Flow Tab UITest.app`.
- The UI log reaches the real fixture markers, opens FlowTab, does not show
  `flowtab.home.permission.open-settings`, and continues into
  `flowtab.switcher.search.input` or `flowtab.switcher.search.window.*`.

The UI test does not need to pass completely to prove that permissions were
obtained. If it fails later in switcher, search-result, activation, or XCUI
snapshot assertions, continue diagnosing that layer rather than reporting a
permission-acquisition blocker.

When running from Codex or another restricted sandbox, the install script may
misreport that no local Apple Development identity is available or fail while
SwiftPM creates temporary files. Retry the install from a normal Terminal, or
with approved access to the local keychain and Xcode temp/cache locations, before
concluding that the machine lacks the signing identity.

## Before Reporting A UI Environment Blocker

Check these in order:

1. Was `./scripts/testing/install-ui-test-app.sh` run?
2. Does `~/Applications/Flow Tab UITest.app` exist?
3. Was `./scripts/testing/run-ui-tests-local.sh` used instead of raw `xcodebuild`?
4. Does the fixed-path UI test app have `Accessibility`?
5. Does the fixed-path UI test app have `Screen & System Audio Recording`?
6. For real-environment or multi-app workflows, do `Flow Tab.app` and `Flow Tab UITest.app` have mutually compatible designated requirements?
7. Only after those checks, decide whether the remaining failure is really a sandbox, cache, or external environment blocker.

## Common Misdiagnoses

- `windows=0` is often a permission or authorized-path mismatch.
- Preview content missing real frames is often a missing screen-recording permission.
- UI automation that "always loses permission" is often using a `DerivedData` app instead of the fixed-path UI test app.
- Real multi-app workflow tests that still show permission reminders often indicate that the launched app path was never granted, or that `Flow Tab.app` and `Flow Tab UITest.app` do not satisfy the same designated requirement.
