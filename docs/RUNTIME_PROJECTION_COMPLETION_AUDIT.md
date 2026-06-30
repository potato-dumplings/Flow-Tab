# Runtime Projection Completion Audit

Updated: 2026-06-30

This audit is the Phase 7 closure ledger for `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md`.
It records current evidence for the projection-driven runtime exit contract without
reclassifying breadth proof as core completion work.

## Phase 7 Slice

- P0: route activation readback mismatch through runtime-owned dirty/stale
  projection metadata instead of leaving it as Activator/surface-local state.
- P1: keep `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md` and `TEST_COVERAGE_MATRIX.md`
  aligned with this audit.
- P2: keep pure CG-only activation success, broader topology, and public-AX
  breadth gaps explicit.

This slice closes the ownership gap exposed by the pure space-backed CG-only
fullscreen proof: `RuntimeActivator` already rejects success without focused
AX/CG or frontmost CG readback, but the mismatch diagnostic did not previously
enter the runtime read model. `RuntimeProjectionService` now accepts
`signalWindowFocusReadbackMismatch(...)`, marks app/pid/target/readback CG
scopes dirty in `RuntimeReadModelStore`, schedules a high-priority
`activationReadbackMismatch` reconciliation request, and leaves Search on the
last committed index as a degraded/stale committed result until a bounded
freshness barrier commits a new generation. Switcher and Home only forward the
diagnostic; they do not maintain surface-local activation repair state.

## Required Evidence

| Exit contract item | Current evidence | Status |
| --- | --- | --- |
| Switcher normal paths read projection/Search APIs or send dirty signals | `scripts/audit/runtime-projection-exit-contract.sh` verifies Switcher references `readAppSwitcherProjection`, `readCurrentAppWindowProjection`, `readCommittedSearchIndexForSearch`, and `requestSearchIndexFreshnessBarrier`, while rejecting legacy snapshot, repair-provider, CG, and AX sampling APIs in Switcher hot paths. | Proven by source audit |
| Open Switcher sessions refresh from runtime projection commits | `RuntimeProjectionService` posts app-switcher and current-app window projection commit notifications after `RuntimeReadModelStore` commits. `SwitcherPanelController` observes those notifications and only re-reads committed projections; it does not create surface-local scheduler/retry state or call snapshot/CG/AX sampling. `testSwitcherPanelControllerAppSwitcherProjectionCommitRefreshesOpenSession`, `testSwitcherPanelControllerCurrentAppProjectionCommitAppliesPendingManualWindowLayerEntry`, `testSwitcherPanelControllerCurrentAppProjectionCommitRefreshesFrozenWindowLayerPreview`, and `testSwitcherPanelControllerCurrentAppProjectionCommitKeepsWindowLayerWhenSelectedWindowIsRemoved` prove app-cycle, pending manual window-layer, already-open window-layer preview refresh, and selected-window-removed fallback behavior. `testSwitcherPanelRefreshesOpenWindowLayerAfterRealFixtureWindowSetMutation`, `testSwitcherPanelKeepsWindowLayerWhenSelectedFixtureWindowCloses`, and `testSwitcherPanelRefreshesOpenWorkflowAppWindowLayerAfterMultiAppWindowSetMutation` prove real fixture close-window mutations route through shared runtime `runtimeAXDestroyed ... affectedCGWindowID=...` evidence, keep the open Switcher window layer on the remaining committed window while the fixture process remains running, and preserve selected-app isolation in a multi-app workflow with a neighboring fullscreen fixture app. | Proven by behavior and real UI tests |
| Control+Tab focused-current-app path does not synchronously sample frontmost/focused app state | The exit audit now separately rejects `NSWorkspace.shared.frontmostApplication`, `kAXFocusedWindowAttribute`, old focused snapshot/frontmost resolver seams, and the removed frontmost bundle launch override in the Switcher/TestingSupport hot path. It also requires `readFocusedCurrentAppWindowProjection()` and `signalFocusedCurrentAppWindowsChanged()` evidence, proving the focused path either reads runtime projection or sends a dirty signal. | Proven by source audit |
| Home normal paths read projection APIs or send dirty signals | The exit audit verifies Home references `readHomeSummaryProjection`, `readHomeAppDetailProjection`, `readCurrentAppWindowProjection`, and `signalAppWindowsChanged`, while rejecting legacy snapshot, repair-provider, CG, and AX sampling APIs in Home hot paths. | Proven by source audit |
| Search reads only committed index and cannot expose staging/repair/partial/session completeness as latest | The exit audit verifies production Search freshness commits only through `RuntimeMainTableProjectionBuilding.searchIndexPayloadFromMainTables(...)` and `RuntimeReadModelStore.commitSearchFreshnessBarrierFromMainTablePayload(...)`. `TEST_COVERAGE_MATRIX.md` records behavior/UI/pressure proof for pre-commit reads that are `missingCommittedIndex` or degraded/stale committed result, committed-generation async re-entry, and external committed-index Search CPU/RSS sampling. | Proven by source audit plus behavior/UI/pressure evidence |
| Search freshness barrier success requires a committed new generation | `TEST_COVERAGE_MATRIX.md` records `committedGenerationResult` only after bounded barrier commit from main-table payload, and records pre-commit real UI state as `missingCommittedIndex` or degraded/stale committed result rather than fresh/complete/latest. | Proven by matrix-backed tests and UI proof |
| Activation may use cached target route, but success must be verified by focused AX/CG or CG frontmost readback | The exit audit rejects direct Space setting and Window-menu shortcuts, requires `RuntimeActivator` focused AX/CG or frontmost CG readback verification plus mismatch diagnostics, and requires verified readback to flow through `RuntimeProjectionService.signalWindowFocusVerified(...)`, `RuntimeWindowRecordStore.recordWindowFocusVerification(...)`, and `readActivationTargetProjection()`. Readback mismatch now flows through `RuntimeProjectionService.signalWindowFocusReadbackMismatch(...)`, runtime dirty/freshness metadata, and high-priority scoped reconciliation; it is not an activation success and keeps committed Search reads degraded/stale until a new generation is committed. | Proven by source audit plus activation behavior tests |
| Full snapshot/full repair is repair, fallback, cold-start, diagnostic, or migration compatibility only | The exit audit rejects provider-facing full-repair projection payload APIs in production. `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md` records full repair as low-priority repair/fallback with backoff and fact-splitting: app-directory evidence may cross the service boundary, while WindowRecord refresh is only a separate summary. | Proven by source audit plus behavior tests |
| Normal projection rows come from runtime main tables/read model, not repair/full-repair/session/staging/direct fallback payloads | `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md` and `TEST_COVERAGE_MATRIX.md` record main-table builders for app-switcher/Home/current-app/Search, production removal of direct app-switcher/Home/Search projection-cache commit bridges, and evidence-only current/full repair boundaries. | Proven by source audit plus behavior tests |
| Representative real topology, Search, activation, and pressure proof exists | `TEST_COVERAGE_MATRIX.md` records the noisy fullscreen/off-space Option+Tab round trip, committed-index Window Search real UI re-entry and activation proof, runtime-topology pressure, and external committed-index Search CPU/RSS sampling. The fixed-path runner was refreshed on 2026-06-30 and the representative UI proof set below passed again. The pure space-backed CG-only fullscreen fixture now proves projection/selection/CG-route submission plus readback rejection (`targetCGNotVisible`) rather than exact activation success. | Proven for representative paths; pure CG-only fullscreen activation success remains a gap |

## Validation Commands

Required for this audit slice:

```bash
./scripts/audit/runtime-projection-exit-contract.sh
```

Representative neighboring behavior proof already used by the current audit:

```bash
./scripts/testing/run-flowtabtests-local.sh \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testSwitcherPanelControllerAppSwitcherProjectionCommitRefreshesOpenSession \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testSwitcherPanelControllerCurrentAppProjectionCommitAppliesPendingManualWindowLayerEntry \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testSwitcherPanelControllerCurrentAppProjectionCommitRefreshesFrozenWindowLayerPreview \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testSwitcherPanelControllerCurrentAppProjectionCommitKeepsWindowLayerWhenSelectedWindowIsRemoved \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeActivatorDoesNotVerifyCGFallbackWhenTargetIsVisibleButNotFrontmost \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeActivatorVerifiesFocusWhenFocusedAXCGMatchesOffscreenTargetCG \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeProjectionServiceTreatsActivationReadbackMismatchAsDirtyStaleCommittedState
```

Post-runner-fix representative UI proof refreshed for this audit:

```bash
./scripts/testing/install-ui-test-app.sh

./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelOptionTabWindowStateRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelWindowSearchRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithoutAppAXWindows \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelPreviewKeepsIdenticalRealWorkflowWindowsDistinct \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelPreviewCapturesRealMinimizedPublicAXState

./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelRefreshesOpenWindowLayerAfterRealFixtureWindowSetMutation

./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelKeepsWindowLayerWhenSelectedFixtureWindowCloses

./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelRefreshesOpenWorkflowAppWindowLayerAfterMultiAppWindowSetMutation

./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelOptionTabReportsUnverifiedSpaceBackedCGOnlyWorkflowActivation
```

The install step built and signed `{user-home}/Applications/Flow Tab UITest.app`
with Apple Development signing. The UI wrapper used that fixed app path and
passed the first 4 selected tests with 0 failures in 123.975 seconds
(`125.622` seconds elapsed in XCTest). The open-window-layer mutation proof
then passed 1 selected UI test in 27.240 seconds, and the selected-window-removed
variant passed 1 selected UI test in 26.796 seconds. The multi-app open-session
mutation proof passed 1 selected UI test in 40.420 seconds (`95.142` seconds
XCTest elapsed including build/test orchestration). The fullscreen target-window
mutation proof passed 1 selected UI test in 41.174 seconds (`42.731` seconds
XCTest elapsed including build/test orchestration). After the UI runner fix, the
pure space-backed CG-only fixture was rerun and the old activation-success
oracle did not hold: the hot-path trigger was made to wait for committed
`window-entries` projection evidence, then activation logged `window-request`
and `focus-attempt route=cg`, but readback remained `targetCGNotVisible` and
`focus-recovery exhausted`. The renamed
`testSwitcherPanelOptionTabReportsUnverifiedSpaceBackedCGOnlyWorkflowActivation`
was rerun after this mismatch-ownership slice. The first runner attempt failed
before the test body with `Timed out while enabling automation mode`; the
immediate retry entered the fixture and passed 1 selected UI test in 28.370
seconds (`36.633` seconds elapsed), proving the runtime does not label that
unverified CG-only activation as a success. Together these refreshed
tests prove
the representative noisy fullscreen/off-space topology round trip, committed
Search-index real UI re-entry and activation, target-app focused public AX
tie-breaker, minimized public AX state capture, real open Switcher window-layer
refresh after shared runtime AX-destroyed reconciliation, and the
selected-window-removed branch preserving `windowCycle` on the repaired runner.
They also prove that a selected Chrome workflow app in a three-app fixture keeps
its open window layer isolated after one of its real windows closes while a
neighboring Notes fullscreen fixture is present, and that the selected Notes
workflow app refreshes an already-open `windowCycle` after its fullscreen target
window closes, removing the closed fullscreen card while keeping the remaining
Notes window isolated.

Broader pressure proof was not re-run for this validation slice because no
production behavior, hot path, activation route, Search barrier, scheduler, or
sampling cadence changes here. Current pressure proof remains recorded in
`TEST_COVERAGE_MATRIX.md`.

## Remaining Gaps

These are breadth/hardening gaps and do not currently contradict the target
runtime shape:

- Real UI occurrence of non-registry focused AX readback is not separately
  forced; production logs can now identify natural fallback hits with
  `verifiedFocusFallbackAX=1`, but no real occurrence has closed the gap yet.
- Public AX main/minimized tie-breaker variants still need real UI occurrence
  and broader state permutation proof; focused/main/minimized deterministic
  matcher coverage is now present.
- Broader multi-display/fullscreen topology and system-authoritative fullscreen
  owner proof remain partial.
- Pure space-backed CG-only fullscreen windows are projection/selection/CG-route
  covered, but the current real UI proof shows `targetCGNotVisible` readback and
  recovery exhaustion rather than exact activation success. The mismatch now
  enters runtime dirty/stale metadata and scoped repair ownership, but do not
  count this as successful activation until focused AX/CG or frontmost CG
  readback proves the selected `CGWindowID`.
- Real UI breadth for open Switcher lifecycle mutation across broader
  cross-Space/multi-display combinations remains open; the representative
  single-app open window-layer mutation, selected-window-removed branch,
  multi-app selected-app isolation branch, and fullscreen target-window close
  branch are now covered by behavior plus real UI proof.

Do not mark these as completed from mock-only evidence. They need representative
UI/E2E, runtime log, or pressure evidence before moving from breadth gap to
closed proof.

## Current Conclusion

The current production boundary is projection-driven for the named normal paths:
Switcher, Home, Search, and activation either read runtime projections/committed
Search index, send dirty signals, or commit activation readback/mismatch
diagnostics. Full repair and snapshot-shaped data are constrained to
repair/fallback/cold-start/diagnostic or test compatibility boundaries. Search
must remain `missingCommittedIndex` or a degraded/stale committed result until a
bounded freshness barrier commits a new main-table generation.

The goal should stay open until the final handoff chooses whether the remaining
breadth gaps are accepted as non-blocking or one of them is promoted to required
completion proof.
