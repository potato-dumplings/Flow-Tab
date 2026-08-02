# SYNC-036BC UI Automation Initialization Recovery Evidence

## Scope and status

SYNC-036BC names the Home exact-window activation watchdog while preserving
the SYNC-034Q exact bundle plus topmost CGWindowID Oracle. Implementation,
direct Swift parsing, inventory readback, `git diff --check`, signed UI, and
100-lifecycle Pressure validation pass. The canonical XCTest-owned Xcode
Helper Accessibility path entered every selected test body and closed the
temporary initialization blocker.

## Preserved evidence

Both elevated attempts used the fixed-path app
`/Users/lk/Applications/Flow Tab UITest.app`, signed by
`Apple Development: gobestsoft@qq.com (RF9WCUVKH8)` with TeamIdentifier
`96PUA726W9`. The runner identifier
`io.github.potato-dumplings.flowtab.uitests.xctrunner` has the same signing
identity and team.

| Attempt | Local time | Wrapper stage | Exit | xcresult summary | Runner evidence |
| --- | --- | --- | --- | --- | --- |
| `ui-current-001` | 2026-08-02 18:12–18:13 Asia/Taipei | `xcodebuild_test-without-building_failed` | 65 | `status=failed`, `testsCount=1`, `errorCount=1` | `Timed out while enabling automation mode` before any selected test body |
| `ui-current-002` | 2026-08-02 18:14–18:16 Asia/Taipei | `xcodebuild_test-without-building_failed` | 65 | `status=failed`, `testsCount=1`, `errorCount=1` | same initialization failure before any selected test body |

Fixture generation, fixture-log inspection, runner signing,
build-for-testing, and build-log inspection returned zero in each wrapper
status ledger. The first and second status ledgers both have SHA-256
`491a9cad8186515ff0117861b877e02f2fe1d063a9a5e81ba926f773da503b2d`.
Their xcodebuild test-log SHA-256 values are respectively
`b29e82f2b66e41fff8a02d2dbe787db655f2c89ac09ed45490c3265d0bac7d3b`
and
`fcde5db1f5cb9f3fc2c86cabc320f8e2394533f91da7938c2734018afe24c7c0`.

The unified log at `2026-08-02 18:14:56.977 +0800` records a correlated
`kTCCServiceListenEvent` preflight for requesting process
`com.apple.DTServiceHub` with responsible process `com.openai.codex`. At
`2026-08-02 18:15:58.525 +0800`, the runner reports the automation-mode
watchdog failure. This temporal correlation does not establish Input
Monitoring as the XCTest authorization requirement. Apple documents the
macOS UI-testing authorization owner as the special Xcode Helper app and the
permission as Accessibility; XCTest prompts automatically on first use and
directs the user to enable Xcode Helper in Accessibility settings:
<https://developer.apple.com/documentation/XCUIAutomation/recording-ui-automation-for-testing>.

Read-only CoreGraphics/ApplicationServices preflight from a separate Swift
child reported:

```text
accessibility=false
listenEvent=false
postEvent=false
screenCapture=false
```

Those child-process values describe that diagnostic process and do not prove
the signed XCTest helper's Accessibility state. The active Console session
belongs to `lk`, login is complete, and no screen-lock marker is present in
`IOConsoleUsers`. Exact final process-name readback found no `FlowTab`,
`FlowTabUITests-Runner`, `xcodebuild`, or `FlowTabSpaceFixture` process after
either attempt.

## Exact reproduction

```sh
./scripts/testing/install-ui-test-app.sh \
  --build-root ./.build-local/evidence-driven-sync/SYNC-036BC/install

./scripts/testing/run-ui-tests-local.sh test \
  --build-root ./.build-local/evidence-driven-sync/SYNC-036BC/ui-build \
  --output-root ./.build-local/evidence-driven-sync/SYNC-036BC/ui-current-003 \
  -only-testing:FlowTabUITests/FlowTabUITests/testHomeActivationWatchdogPolicyCompatibility \
  -only-testing:FlowTabUITests/FlowTabUITests/testWorkflowWindowActivationObserverAcceptsExactInitialState \
  -only-testing:FlowTabUITests/FlowTabUITests/testWorkflowWindowActivationObserverInstallsBeforeReadbackAndGatesBaseline \
  -only-testing:FlowTabUITests/FlowTabUITests/testWorkflowWindowActivationObserverRequiresExactBundleAndWindow \
  -only-testing:FlowTabUITests/FlowTabUITests/testWorkflowWindowActivationObserverSlowReadbacksOnlyDelayResolution \
  -only-testing:FlowTabUITests/FlowTabUITests/testWorkflowWindowActivationObserverRejectsCancelledAndReplacedEventsUnderPressure \
  -only-testing:FlowTabUITests/FlowTabUITests/testWorkflowWindowActivationWatchdogReportsFinalReadback \
  -only-testing:FlowTabUITests/FlowTabUITests/testHomePageClickingRealWorkflowWindowActivatesExactFixtureWindow
```

## Recovery proof

The fixed-path app was rebuilt and signed at 2026-08-02 19:07 with
`Apple Development: gobestsoft@qq.com (RF9WCUVKH8)` and TeamIdentifier
`96PUA726W9`. The canonical wrapper then used XCTest directly; the existing
Xcode Helper Accessibility authorization allowed immediate test-body entry,
so macOS had no new authorization decision to request.

| Invocation | Local time | Wrapper status | XCTest result | Independent evidence |
| --- | --- | --- | --- | --- |
| `auth-current-001` | 2026-08-02 19:07–19:08 Asia/Taipei | every applicable stage completed, exit 0 | 1/1 passed in 1.141 seconds | policy test body entered and returned normally |
| `ui-current-003` | 2026-08-02 19:08 Asia/Taipei | every stage completed, exit 0 | `xcresult status=succeeded`, 8/8 passed in 30.978 seconds | real fixture exact-window activation passed in 29.358 seconds; 100-lifecycle cancellation/replacement Pressure passed in 0.197 seconds |

The full run also covered already-satisfied initial state, observer-before-
trigger gating, exact bundle/window rejection and acceptance, slow scheduled
readbacks, cancellation/replacement, and final watchdog diagnostics. Exact
post-run process readback found no `FlowTab`, `FlowTabUITests-Runner`,
`xcodebuild`, or `FlowTabSpaceFixture` process. The automation watchdog alone
carries no product or runtime result.

## Artifact disposition

The two failed invocation directories occupied 434 MB and 425 MB. Their
status, signing identity, hashes, exact diagnostic, reproduction command,
correlated TCC record, corrected authorization classification, Console state,
and process cleanup evidence are preserved
above. Both exact invocation directories were removed after capture. A third
read-only permission preflight remained false for Accessibility, Listen
Event, Post Event, and Screen Capture, with every exact test process absent.
The remaining 794 MB install/build root was then removed as rebuildable
DerivedData, fixture variants, caches, and logs. The successful rebuilt
authorization probe and full validation currently occupy 805 MB under the
exact `SYNC-036BC` artifact root. They are scheduled for post-commit deletion;
the canonical commands above recreate every validation artifact.
