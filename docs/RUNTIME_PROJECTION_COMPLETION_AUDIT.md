# Runtime Projection Completion Audit

Updated: 2026-07-01

This audit is the Phase 7 closure ledger for `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md`.
It records current evidence for the projection-driven runtime exit contract without
reclassifying breadth proof as core completion work.

## Phase 7 Slice

- P0: route activation readback mismatch through runtime-owned dirty/stale
  projection metadata and WindowRecord action downgrade instead of leaving it
  as Activator/surface-local state.
- P1: keep `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md` and `TEST_COVERAGE_MATRIX.md`
  aligned with this audit.
- P2: keep pure CG-only activation success, broader topology, and public-AX
  breadth gaps explicit.

This slice closes the ownership gap exposed by the pure space-backed CG-only
fullscreen proof: `RuntimeActivator` already rejects success without focused
AX/CG or frontmost CG readback, but the mismatch diagnostic did not previously
enter the runtime read model or the projection action policy. `RuntimeProjectionService`
now accepts `signalWindowFocusReadbackMismatch(...)`, marks app/pid/target/readback
CG scopes dirty in `RuntimeReadModelStore`, records the failed target route in
`RuntimeWindowRecordStore`, schedules a high-priority `activationReadbackMismatch`
reconciliation request, and leaves Search on the last committed index as a
degraded/stale committed result until a bounded freshness barrier commits a new
generation. WindowRecord projection keeps the failed target visible/previewable
when it is otherwise eligible, but removes `useForCGActivationFallback` until
later exact/verified evidence clears the failure. Switcher and Home only forward
the diagnostic; they do not maintain surface-local activation repair state.

## Required Evidence

| Exit contract item | Current evidence | Status |
| --- | --- | --- |
| Switcher normal paths read projection/Search APIs or send dirty signals | `scripts/audit/runtime-projection-exit-contract.sh` verifies Switcher references `readAppSwitcherProjection`, `readCurrentAppWindowProjection`, `readCommittedSearchIndexForSearch`, and `requestSearchIndexFreshnessBarrier`, while rejecting legacy snapshot, repair-provider, CG, and AX sampling APIs in Switcher hot paths. | Proven by source audit |
| Switcher fullscreen presentation reads runtime Space topology projection, not frontmost/AX fullscreen probes | The exit audit now separately rejects `NSWorkspace.shared.frontmostApplication`, focused-window attributes, AX fullscreen probes, CG window-list sampling, and AX app creation inside `SwitcherPanelController+Presentation`, while requiring `readSpaceTopologyProjection()` / `signalSpaceTopologyChanged()` evidence. `testSwitcherPanelPresentationReadsRuntimeSpaceTopologyProjectionForFullscreenLevel`, `testSwitcherPanelPresentationSignalsRuntimeWhenSpaceTopologyProjectionIsMissing`, and `testSwitcherPanelPresentationFailsClosedForIncompleteSpaceTopologyProjection` prove the panel elevates only from a complete/current runtime Space topology projection, sends the dirty signal when projection is missing, and keeps the normal level without extra dirty signaling when projection freshness is incomplete/pending. | Proven by source audit and behavior tests |
| Open Switcher sessions refresh from runtime projection commits | `RuntimeProjectionService` posts app-switcher and current-app window projection commit notifications after `RuntimeReadModelStore` commits. `SwitcherPanelController` observes those notifications and only re-reads committed projections; it does not create surface-local scheduler/retry state or call snapshot/CG/AX sampling. `testSwitcherPanelControllerAppSwitcherProjectionCommitRefreshesOpenSession`, `testSwitcherPanelControllerCurrentAppProjectionCommitAppliesPendingManualWindowLayerEntry`, `testSwitcherPanelControllerCurrentAppProjectionCommitRefreshesFrozenWindowLayerPreview`, and `testSwitcherPanelControllerCurrentAppProjectionCommitKeepsWindowLayerWhenSelectedWindowIsRemoved` prove app-cycle, pending manual window-layer, already-open window-layer preview refresh, and selected-window-removed fallback behavior. `testSwitcherPanelRefreshesOpenWindowLayerAfterRealFixtureWindowSetMutation`, `testSwitcherPanelKeepsWindowLayerWhenSelectedFixtureWindowCloses`, and `testSwitcherPanelRefreshesOpenWorkflowAppWindowLayerAfterMultiAppWindowSetMutation` prove real fixture close-window mutations route through shared runtime `runtimeAXDestroyed ... affectedCGWindowID=...` evidence, keep the open Switcher window layer on the remaining committed window while the fixture process remains running, and preserve selected-app isolation in a multi-app workflow with a neighboring fullscreen fixture app. | Proven by behavior and real UI tests |
| Current-app sibling preservation is runtime-owned and activation/dirty gated | `scripts/audit/runtime-projection-exit-contract.sh` now rejects Switcher-owned current-app sibling preservation helpers and requires `RuntimeReadModelStore` to own `currentAppWindowPayloadByPreservingPriorCommittedWindowsLocked(...)`, committed current-app/app-switcher projection sources, activation-action gating through `useForAXActivation` / `useForCGActivationFallback`, and dirty `CGWindowID` rejection. `testRuntimeReadModelStorePreservesCommittedCurrentAppSiblingRowsUntilDirtyCGInvalidatesThem`, `testRuntimeReadModelStorePreservesCurrentAppSiblingsFromCommittedAppSwitcherProjection`, and `testLiveSwitcherModelAppliesCommittedRuntimeWindowRecencyWhenProjectionOrderChanges` prove committed sibling preservation, dirty affected-CG invalidation, prior current-app AX/CG preservation, app-switcher-source migration preservation only for AX-activation rows, activation-capable inferred CG-fallback artifact rejection, and restored window-cycle ordering. | Proven by source audit and behavior tests |
| Control+Tab focused-current-app path does not synchronously sample frontmost/focused app state | The exit audit now separately rejects `NSWorkspace.shared.frontmostApplication`, `kAXFocusedWindowAttribute`, old focused snapshot/frontmost resolver seams, and the removed frontmost bundle launch override in the Switcher/TestingSupport hot path. It also requires `readFocusedCurrentAppWindowProjection()` and `signalFocusedCurrentAppWindowsChanged()` evidence, proving the focused path either reads runtime projection or sends a dirty signal. | Proven by source audit |
| Home normal paths read projection APIs or send dirty signals | The exit audit verifies Home references `readHomeSummaryProjection`, `readHomeAppDetailProjection`, `readCurrentAppWindowProjection`, and `signalAppWindowsChanged`, while rejecting legacy snapshot, repair-provider, CG, and AX sampling APIs in Home hot paths. | Proven by source audit |
| Search reads only committed index and cannot expose staging/repair/partial/session completeness as latest | The exit audit verifies production Search freshness commits only through `RuntimeMainTableProjectionBuilding.searchIndexPayloadFromMainTables(...)` and `RuntimeReadModelStore.commitSearchFreshnessBarrierFromMainTablePayload(...)`. `TEST_COVERAGE_MATRIX.md` records behavior/UI/pressure proof for pre-commit reads that are `missingCommittedIndex` or degraded/stale committed result, committed-generation async re-entry, and external committed-index Search CPU/RSS sampling. | Proven by source audit plus behavior/UI/pressure evidence |
| Search freshness barrier success requires a committed new generation | `TEST_COVERAGE_MATRIX.md` records `committedGenerationResult` only after bounded barrier commit from main-table payload, and records pre-commit real UI state as `missingCommittedIndex` or degraded/stale committed result rather than fresh/complete/latest. | Proven by matrix-backed tests and UI proof |
| Activation may use cached target route, but success must be verified by focused AX/CG or CG frontmost readback | The exit audit rejects direct Space setting and Window-menu shortcuts, requires `RuntimeActivator` focused AX/CG or frontmost CG readback verification plus mismatch diagnostics, and requires verified readback to flow through `RuntimeProjectionService.signalWindowFocusVerified(...)`, `RuntimeWindowRecordStore.recordWindowFocusVerification(...)`, and `readActivationTargetProjection()`. Readback mismatch now flows through `RuntimeProjectionService.signalWindowFocusReadbackMismatch(...)`, runtime dirty/freshness metadata, high-priority scoped reconciliation, and WindowRecord-owned route failure evidence that removes `useForCGActivationFallback` from the failed target projection while preserving display/preview actions. It is not an activation success and keeps committed Search reads degraded/stale until a new generation is committed. | Proven by source audit plus activation behavior tests |
| Non-registry verified-focus fallback AX readback is observable when it happens | `testRuntimeProjectionServiceSeedsVerifiedFocusRecordWhenFocusedAXWindowIsNotInRegistry` now proves the non-registry fallback AX id writes exact WindowRecord evidence, parses back to the focused `CGWindowID`, and emits a production `binding-confidence-change ... verifiedFocusFallbackAX=1` marker under debug+verbose logs. The exit audit also requires `AXWindowInspector.verifiedFocusFallbackCGWindowID(...)` and the WindowRecord `verifiedFocusFallbackAX` marker so the runtime-log oracle cannot silently disappear from production. This protects the marker that future real UI proof must use, but it does not close the real UI occurrence gap by itself. | Proven by source audit and behavior test; real UI occurrence still gap |
| Full snapshot/full repair is repair, fallback, cold-start, diagnostic, or migration compatibility only | The exit audit rejects provider-facing full-repair projection payload APIs in production. `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md` records full repair as low-priority repair/fallback with backoff and fact-splitting: app-directory evidence may cross the service boundary, while WindowRecord refresh is only a separate summary. | Proven by source audit plus behavior tests |
| Normal projection rows come from runtime main tables/read model, not repair/full-repair/session/staging/direct fallback payloads | `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md` and `TEST_COVERAGE_MATRIX.md` record main-table builders for app-switcher/Home/current-app/Search, production removal of direct app-switcher/Home/Search projection-cache commit bridges, and evidence-only current/full repair boundaries. | Proven by source audit plus behavior tests |
| Representative real topology, Search, activation, and pressure proof exists | `TEST_COVERAGE_MATRIX.md` records the noisy fullscreen/off-space Option+Tab round trip, committed-index Window Search real UI re-entry and activation proof, runtime-topology pressure, and external committed-index Search CPU/RSS sampling. Historical fixed-path proof exists for the representative set below. The current slice fixes a RuntimeReadModelStore preservation leak exposed after the UI runner repair: app-switcher migration source rows with inferred/sticky CG fallback can no longer be promoted into current-app window-cycle siblings unless they also carry `useForAXActivation`; prior current-app projection preservation can still keep AX or CG fallback siblings already admitted by the current-app boundary. Behavior coverage first reproduced the leak with an inferred `Chrome Fixture` artifact and then passed after the source-gated fix. The targeted Noisy Option+Tab UI run now enters the real fixture and gets past the exact-four-user-window/noisy-preview assertion, but still fails later on the `fullscreen1` exact activation oracle (`Chrome Fullscreen Tab` selected CG `764952`, frontmost readback remained normal CG `764886`). The current noisy UI proof is therefore not refreshed to green; it is a projection/noise-exposure advance plus an activation proof gap. The pure space-backed CG-only fullscreen fixture still proves projection/selection/CG-route submission plus readback rejection (`targetCGNotVisible`) rather than exact activation success. | Historically proven for representative paths; current preservation leak behavior-fixed and noisy preview assertion advanced; current Noisy Option+Tab fullscreen activation readback still fails; pure CG-only fullscreen activation success remains a gap |

## Validation Commands

Required for this audit slice:

```bash
./scripts/audit/runtime-projection-exit-contract.sh
```

The audit now includes production checks for the non-registry verified-focus
fallback parser, grep-able `verifiedFocusFallbackAX` WindowRecord log marker,
and current-app sibling preservation ownership in `RuntimeReadModelStore`
instead of Switcher surface state.

Representative neighboring behavior proof already used by the current audit:

```bash
./scripts/testing/run-flowtabtests-local.sh \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testSwitcherPanelControllerAppSwitcherProjectionCommitRefreshesOpenSession \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testSwitcherPanelControllerCurrentAppProjectionCommitAppliesPendingManualWindowLayerEntry \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testSwitcherPanelControllerCurrentAppProjectionCommitRefreshesFrozenWindowLayerPreview \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testSwitcherPanelControllerCurrentAppProjectionCommitKeepsWindowLayerWhenSelectedWindowIsRemoved \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testSwitcherPanelPresentationReadsRuntimeSpaceTopologyProjectionForFullscreenLevel \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testSwitcherPanelPresentationSignalsRuntimeWhenSpaceTopologyProjectionIsMissing \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testSwitcherPanelPresentationFailsClosedForIncompleteSpaceTopologyProjection \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeActivatorDoesNotVerifyCGFallbackWhenTargetIsVisibleButNotFrontmost \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeActivatorVerifiesFocusWhenFocusedAXCGMatchesOffscreenTargetCG \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeProjectionServiceSeedsVerifiedFocusRecordWhenFocusedAXWindowIsNotInRegistry \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeWindowRecordStoreSuppressesCGActivationFallbackAfterReadbackMismatch \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeProjectionServiceTreatsActivationReadbackMismatchAsDirtyStaleCommittedState
```

Current noisy Option+Tab ordering behavior proof for this slice:

```bash
./scripts/testing/run-flowtabtests-local.sh \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeWindowRecencyTrackerMatchesRecordedCGWindowAcrossProjectionOrder \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeWindowRecencyTrackerOrdersRecordedWindowsBeforeFallbackInRecencyOrder \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testLiveSwitcherModelFocusedRuntimeProjectionUsesCommittedRecencyBeforeOrdering \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testSwitcherPanelControllerCurrentAppProjectionCommitAppliesPendingManualWindowLayerEntry \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testLiveSwitcherModelAppliesCommittedRuntimeWindowRecencyWhenProjectionOrderChanges
```

This targeted behavior run passed 5 selected tests with 0 failures. It proves
that selected projection windows and committed sticky/fullscreen selections
update runtime recency before fallback windows, without treating that selected
recency as activation success.

Current-app sibling preservation behavior proof for the current audit:

```bash
./scripts/testing/run-flowtabtests-local.sh \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeReadModelStorePreservesCommittedCurrentAppSiblingRowsUntilDirtyCGInvalidatesThem \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeReadModelStorePreservesCurrentAppSiblingsFromCommittedAppSwitcherProjection \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testLiveSwitcherModelAppliesCommittedRuntimeWindowRecencyWhenProjectionOrderChanges
```

The pre-fix reproduction failed after the app-switcher source artifact was given
`WindowBindingConfidence.inferred.allowedActions`, proving that the old
activation-capable gate carried a CG-fallback artifact into current-app
projection. The post-fix targeted behavior run passed the selected tests with 0
failures. It proves that missing current-app siblings can be preserved from
committed projection state, dirty affected `CGWindowID`s invalidate preserved
siblings, prior current-app projection can keep already-admitted AX/CG fallback
siblings, app-switcher projection can serve only as a narrower migration source,
and inferred CG-fallback artifact rows are not carried into current-app
window-cycle projection.

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

After the first selected-recency slice, the app was reinstalled with Apple
Development signing and the targeted Noisy Option+Tab UI test reached the test
body, where it exposed a remaining product race: an app-switcher projection
update with a degraded zero-window app row could overwrite an already-open
current-app window layer before the next current-app projection apply. The
following preservation slice fixed the projection-read boundary further: the
runner now reaches the fixture and gets past the exact-four-user-window/noisy
preview assertion, but the same targeted run still fails later on the
`fullscreen1` exact activation oracle. It selected `Chrome Fullscreen Tab`
CG `764952`, while frontmost readback remained on normal window `764886`.
This does not refute the projection leak fix, but it keeps the current
representative Noisy Option+Tab UI proof unrefreshed to green.

Broader pressure proof was not re-run for this validation slice because
`scripts/perf/runtime-topology-pressure.sh 0.5` wraps the same representative
Noisy Option+Tab UI path that currently fails on fullscreen activation readback.
Current historical pressure proof remains recorded in `TEST_COVERAGE_MATRIX.md`,
but this slice does not refresh it.

## Remaining Gaps

These are breadth/hardening gaps and do not currently contradict the target
runtime shape:

- Real UI occurrence of non-registry focused AX readback is not separately
  forced; production logs can now identify natural fallback hits with
  `verifiedFocusFallbackAX=1`, and behavior coverage protects that marker, but
  no real occurrence has closed the gap yet. After the 2026-06-30 runner fix,
  the fixed-path Apple Development signed app reached the targeted Noisy
  Option+Tab test body and exposed product assertions for app-local window
  order. The first selected-recency slice fixed the selected sticky/fullscreen
  ordering behavior, and the current slice fixes the remaining degraded
  app-switcher projection update race by restoring open `windowCycle` state from
  the committed current-app projection. Post-fix targeted UI proof was
  reattempted after reinstalling the Apple Development signed app, but two
  consecutive reruns failed before the test body with `Timed out while enabling
  automation mode`; therefore the noisy UI proof remains unrefreshed, and no
  real `verifiedFocusFallbackAX=1` occurrence proof was produced.
- Public AX main/minimized tie-breaker variants still need real UI occurrence
  and broader state permutation proof; focused/main/minimized deterministic
  matcher coverage is now present.
- Broader multi-display/fullscreen topology and system-authoritative fullscreen
  owner proof remain partial. The production boundary now has a repeatable
  source audit and behavior proof for Switcher fullscreen presentation reading
  only runtime Space topology projection, including complete/missing/incomplete
  fail-closed cases, but those tests are not a replacement for real topology
  breadth proof.
- Pure space-backed CG-only fullscreen windows are projection/selection/CG-route
  covered, but the current real UI proof shows `targetCGNotVisible` readback and
  recovery exhaustion rather than exact activation success. The mismatch now
  enters runtime dirty/stale metadata, scoped repair ownership, and WindowRecord
  action downgrade ownership, but do not count this as successful activation
  until focused AX/CG or frontmost CG readback proves the selected `CGWindowID`.
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
