# UI Automation Prerequisites

Use this reference before declaring FlowTab UI automation blocked by the environment.

FlowTab UI failures are often caused by repository-specific setup issues rather than generic XCTest instability. Do not treat permission-like failures, missing windows, or real-environment workflow failures as unexplained blockers until these checks are complete.

## Required Outcome

- Prepare a fixed-path UI test app before relying on UI automation for local verification.
- Confirm the permissions and code identity that macOS actually uses for privacy gating.
- Use the repository scripts in the recommended order before escalating to an environment blocker.
- Distinguish sandbox or cache failures from permission, bundle-path, or code-identity mismatches.

## Standard Local Preparation

1. Install the fixed-path UI test app:

```bash
./scripts/testing/install-ui-test-app.sh
```

Default install path:

- `~/Applications/Flow Tab UITest.app`

2. Grant permissions to that fixed-path app in macOS:

- `System Settings -> Privacy & Security -> Accessibility`
- `System Settings -> Privacy & Security -> Screen & System Audio Recording`

3. Run UI automation through the repository wrapper:

```bash
./scripts/testing/run-ui-tests-local.sh
```

That script prefers `~/Applications/Flow Tab UITest.app` when it exists. It only falls back to a `DerivedData` build product when the fixed-path app is missing.

## Why Fixed Path Matters

- macOS privacy permissions are sensitive to the app instance and code identity, not only to the bundle name.
- If `FlowTabUITests` launches a `DerivedData` product directly, macOS may not treat it as the already-authorized app.
- A test run that looks like "permissions disappeared again" is often a path or identity mismatch, not a flaky test.

## Real-Environment And Multi-App Workflow Prerequisites

These checks are required for UI tests that launch real fixture apps, drive the Home page or switcher against live runtime state, or verify multi-app space workflows:

- FlowTab has `Accessibility`
- FlowTab has `Screen & System Audio Recording`
- `Flow Tab.app` and `Flow Tab UITest.app` use the same macOS code identity

Important interpretation:

- macOS privacy permissions are bound to code identity, not just bundle id or app name.
- If `/Applications/Flow Tab.app` is still `adhoc` but `~/Applications/Flow Tab UITest.app` is signed with `Apple Development`, the system may not reuse the granted permissions.
- When a real-environment workflow still shows permission reminders after permissions were granted, first check code identity mismatch before calling it a blocker.

## Recommended Preparation For Stable Real-Environment UI Runs

1. Install a fixed-path UI test app with a stable local development signing identity when available:

```bash
./scripts/testing/install-ui-test-app.sh --development-team <TEAM_ID>
```

2. Ensure the regularly launched FlowTab app also uses the same signing identity.

3. Reconfirm `Accessibility` and `Screen & System Audio Recording` permissions after signing or path changes.

4. Run:

```bash
./scripts/testing/run-ui-tests-local.sh
```

## Before Reporting A UI Environment Blocker

Check these in order:

1. Was `./scripts/testing/install-ui-test-app.sh` run?
2. Does `~/Applications/Flow Tab UITest.app` exist?
3. Was `./scripts/testing/run-ui-tests-local.sh` used instead of raw `xcodebuild`?
4. Does the fixed-path UI test app have `Accessibility`?
5. Does the fixed-path UI test app have `Screen & System Audio Recording`?
6. For real-environment or multi-app workflows, do `Flow Tab.app` and `Flow Tab UITest.app` share the same code identity?
7. Only after those checks, decide whether the remaining failure is really a sandbox, cache, or external environment blocker.

## Common Misdiagnoses

- `windows=0` is often a permission or authorized-path mismatch.
- Preview content missing real frames is often a missing screen-recording permission.
- UI automation that "always loses permission" is often using a `DerivedData` app instead of the fixed-path UI test app.
- Real multi-app workflow tests that still show permission reminders often indicate code-identity mismatch between `Flow Tab.app` and `Flow Tab UITest.app`.
