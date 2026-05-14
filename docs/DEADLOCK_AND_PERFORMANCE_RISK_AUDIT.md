# Deadlock And Performance Risk Audit

Updated: 2026-05-14

## Scope

This audit covers FlowTab production Swift code under `FlowTab/` and `FlowTabCore/`, with attention to:

- blocking calls, locks, semaphores, serial queues, and main-actor handoff paths that could deadlock;
- hot paths whose cost grows with app, window, result, preview, observer, or repeated interaction count;
- existing pressure coverage and gaps that should gate remediation.

## Validation Snapshot

Checks run on 2026-05-14:

- `swift test --filter SwitcherSessionTests` in `FlowTabCore`: passed, 15 tests.
- `./scripts/testing/run-flowtabtests-local.sh -only-testing:FlowTabTests/FlowTabTests/testSearchPerformanceWindowScope -only-testing:FlowTabTests/FlowTabTests/testSearchPressureWindowScopeUnified -only-testing:FlowTabTests/FlowTabTests/testOptionTabWindowScalePressureKeepsBackgroundApplyAndPreviewCaptureBounded`: passed, 3 tests.
- `./scripts/testing/run-ui-tests-local.sh -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherInitialPresentationStaleOcclusionDoesNotHardRecover`: failed before the panel recovery fix, then passed after the fix.
- `./scripts/testing/run-flowtabtests-local.sh -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testSwitcherPanelControllerRecoverableOcclusionKeepsSessionVisible -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testSwitcherPanelControllerActiveSpaceChangeKeepsSessionVisibleWithoutReactivatingApp -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testSwitcherPanelControllerActiveSpaceNotificationKeepsSessionVisibleWithoutReactivatingApp`: passed, 3 tests.

Observed local pressure numbers:

- Search realistic window scope: `400` apps / `10000` windows, build `2257.12ms`, query `3413.63ms`, `132` queries, `38.67 qps`.
- Search unified pressure: `400` apps / `10000` windows, build `2182.14ms`, query `3415.94ms`, `132` queries, `38.64 qps`.
- Option+Tab 1000-window preview pressure: apply p95 `0.40ms`, window-layer entry p95 `0.01ms`, preview items p95 `0.08ms`, preview capture calls `360`.

These results match the existing pressure shape in `docs/TEST_COVERAGE_CHECKLIST.md`: search is CPU-heavy but already has a same-machine baseline, and current-page preview capture remains bounded for the covered 1000-window path.

## Priority Findings

### Deadlock Classification

This audit does not conclude that FlowTab has zero deadlock risk. It concludes that no reviewed production path currently has a reproducible circular wait or a stable hang signal.

Deadlock-like risks are tracked as watchpoints until there is evidence of a real cycle, because FlowTab bugfix rules require a reproducible signal before production logic changes. The current watchpoints are:

- synchronous work submitted to a private serial queue in `RuntimeSnapshotService`;
- blocking waits around ScreenCaptureKit callbacks in `RuntimeWindowPreviewProvider`, bounded by explicit timeouts;
- lock-protected shared state in `RuntimeWindowRecencyTracker`, `SystemAppMRUTracker`, and `AXLiveWindowRegistry`, currently without nested lock acquisition or main-thread synchronous handoff in the reviewed call paths.

### P0 Resolved: Initial Option+Tab Panel Presentation Could Flicker

Status: user-visible flicker; reproduced and fixed. This was not a deadlock.

Stable reproduction:

- The UI test launches FlowTab with mock runtime data and a test-only stale occlusion window: `--flowtab-ui-initial-panel-occlusion-stale-ms 260`.
- It triggers the global switcher through the same presentation path used by Option+Tab.
- Before the fix, runtime logs showed `visibleProbe ... userVisible=0` followed by `presentationRecovery trigger=global_show action=attempt`.

Root cause:

- Initial `global_show` / `in_app_show` visibility recovery treated a short-lived stale `NSWindow.occlusionState` as a real hidden panel.
- The generic recovery path called `panel.orderOut(nil)` before reordering the panel, so a healthy panel could visibly disappear and reappear during the first few hundred milliseconds.

Fix:

- Initial presentation recovery now uses a soft reorder mode that reasserts level, position, `makeKeyAndOrderFront`, and `orderFrontRegardless` without `orderOut` or app activation.
- Real interruption recovery paths still use the existing hard reorder behavior for active-space changes, occlusion notifications, and resign-key/application-interruption cases.

### P1: App-Local Window Recency Overlay Can Repeatedly Scan Large Window Sets

Status: performance risk; remediation should add a pressure test before production changes.

Evidence:

- `RuntimeWindowRecencyTracker.appWithRecencyApplied` applies recency during full snapshots, focused-app snapshots, selected-app window snapshots, Home snapshots, and switcher/session startup paths.
- `matchingWindowID` converts `appWindowIDs` to arrays and scans the selected app windows for each retained recency record. The tracker keeps up to `128` records per app, so the matching path can grow toward `records * windows` during hot snapshot application.
- Existing pressure coverage proves 1000-window preview paging and capture bounds, but it does not isolate the recency overlay cost at the maximum retained-record count.

Impact:

- The current algorithm is acceptable for small apps, but it is avoidable repeated work on large selected-app window sets.
- The path can run while the user opens the switcher, enters a window layer, views Home windows, or applies selected-app scoped snapshots, so latency spikes would be user visible.

Smallest corrective path:

- Precompute reusable per-app lookup structures once while applying recency to an app snapshot.
- Keep matching semantics unchanged: exact runtime window ID first, then unique CG window match, then unique title/frame semantic match.
- Add a deterministic pressure test with `1000` windows and `128` retained records, recording latency and preserving the expected ordering proof.

### P2: Window Preview Batch Capture Uses Blocking Semaphores Inside `concurrentPerform`

Status: monitored performance risk; no current failing signal.

Evidence:

- `RuntimeWindowPreviewProvider.captureWindowPreviews` uses `DispatchQueue.concurrentPerform` and a semaphore to cap live capture work.
- The current switcher path already limits requests to the visible page, shares one `SCShareableContent` lookup per batch, and has pressure coverage proving capture calls are bounded for the 1000-window selected-app path.

Impact:

- The implementation should be watched if a future change increases request counts beyond the current page or moves capture work closer to a user-blocking path.
- Current evidence does not justify a production rewrite ahead of the recency overlay risk.

Smallest corrective path if this regresses:

- Replace broad `concurrentPerform` scheduling with an explicitly bounded worker loop and add a provider-level concurrency pressure test.

### P3: Runtime Snapshot Service Uses Serial `sync` Calls

Status: deadlock risk reviewed; no reproducible deadlock found in current call graph.

Evidence:

- `RuntimeSnapshotService` serializes provider access through a private `DispatchQueue` and uses `sync` for synchronous APIs.
- Static scan did not find `DispatchQueue.main.sync`, recursive service calls from provider internals, or a production path that calls the service again while already executing on its private queue.
- Current callers that need selected-app or background snapshots dispatch work off the main actor before calling synchronous snapshot APIs.

Impact:

- This is a design watchpoint, not a confirmed defect. A future provider callback that re-enters the same service could deadlock, but that scenario is not present today.

Required reproduction before fixing:

- Add a stable failing signal only if a real re-entrant path is discovered or introduced. Until then, document the watchpoint rather than patching a hypothetical deadlock.

## Proposed Test Scenario Set For P1

Required:

- Pressure/behavior layer: add one `FlowTabTests` case in `FlowTabPriorityCoverageTests+WindowRecency.swift`.
- Dataset: one app with `1000` windows and a `RuntimeWindowRecencyTracker` configured with `maxRecordsPerApp: 128`.
- Activity: record the maximum retained records using CG-window IDs and title/frame data, then apply `snapshotWithRecencyApplied` repeatedly.
- Assertions: the most recent recorded windows sort ahead of fallback windows; total application latency is printed as a local pressure baseline and kept under a conservative threshold.

Optional:

- Provider-level preview concurrency pressure for `RuntimeWindowPreviewProvider`; not adding by default because existing switcher pressure already proves current-page capture bounds.

Intentionally Not Adding:

- UI automation for recency pressure. The risk is deterministic in the in-process recency overlay and does not require visible UI proof.
- Deadlock regression test for `RuntimeSnapshotService`. No re-entrant production path has been reproduced.
