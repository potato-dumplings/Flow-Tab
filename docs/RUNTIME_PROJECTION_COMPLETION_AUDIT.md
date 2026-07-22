# Runtime Projection Completion Audit

Updated: 2026-07-02

This audit is the Phase 7 closure ledger for `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md`.
It records current evidence for the projection-driven runtime exit contract without
reclassifying breadth proof as core completion work.

## Current Phase 7 Slice

- P0: make the final completion decision for the projection-driven runtime
  migration by rerunning the repeatable source-boundary audit and classifying
  the remaining topology items as breadth/hardening gaps rather than core Exit
  Contract blockers.
- P1: keep `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md`, the executable exit audit,
  and this audit aligned with the final completion decision. They continue to
  require `missingCommittedIndex` or degraded/stale committed wording until a
  bounded freshness barrier commits a new generation.
- P2: keep pure CG-only activation success, broader multi-display/system-owner
  topology, real non-registry focused AX occurrence, and public AX main-state
  real UI occurrence explicit. They are not marked complete from mock-only or
  indirect evidence, but they no longer block the core projection-driven runtime
  goal because the normal paths and representative UI/pressure proofs below
  satisfy the Exit Contract.

The committed Search index invariant is now guarded in three places: production
Search freshness commits still come only from main-table payloads; Search result
states still use `missingCommittedIndex`, `degradedStaleCommittedResult`, and
`committedGenerationResult`; and Switcher/Search surface code is now audited so
it cannot rebuild normal results by constructing runtime Search projections or
entries from session/staging/repair state. Search result display metadata is
also guarded to come from `committedSearchAppsByID`, not from current
app-switcher session rows. The panel-backed attempt still remains the latest
real public AX main-state evidence, and it did not produce
`binding-assignment public-state-tiebreak state=main`; therefore main-state
occurrence remains a real UI gap. Search remains missing committed index or
degraded/stale committed until a bounded freshness barrier commits a new
main-table generation. If a previously active Search session sees the committed
index disappear, the surface must leave Search inactive with no visible results
and record `missingCommittedIndex`; it may request the freshness barrier, but it
must not present old committed rows as fresh, complete, latest, or normal
current-generation results.

Current Search pressure proof:

```bash
./scripts/perf/search-committed-index-pressure.sh 0.5
```

The sandboxed first attempt failed during SwiftPM manifest compilation with
`unable to make temporary file: Operation not permitted`, so the wrapper was
rerun outside the sandbox as required by the FlowTabTests workflow. The fixed
wrapper passed 2 batches of 3 selected FlowTabTests with 0 failures, collected
80 samples at 0.5s cadence with `minSampleSeconds=30`, and recorded
`cpuAvg=4.22`, `cpuP95=15.00`, `cpuMax=103.60`, `rssAvgMB=160.80`,
`rssP95MB=174.53`, and `rssMaxMB=233.44`. The dataset stayed at
400 apps / 10,000 windows. The committed runtime index pressure metric reported
`resultState=committedGenerationResult` and `freshnessBarrierRequests=0` only
because the test fixture installs a validated committed generation before the
hot Search read; this is not a pre-barrier fresh/complete/latest result.

Current app-hosted mock dataset proof:

```bash
./scripts/testing/run-flowtabtests-local.sh \
  -only-testing:FlowTabTests/FlowTabTests/testUITestMockDatasetBuildsExplicitFullRepairProjectionPayloadWhenLaunchFlagEnabled \
  -only-testing:FlowTabTests/FlowTabTests/testAppInventoryServiceReadsUITestRuntimeProjectionDataset \
  -only-testing:FlowTabTests/FlowTabTests/testRuntimeProjectionRepairProviderMockRuntimeKeepsCurrentAppPayloadsScopedPerApp \
  -only-testing:FlowTabTests/FlowTabTests/testRuntimeProjectionRepairProviderMockSingleAppFiveWindowsProjectionPayloadKeepsAllWindowsInHomeLayer \
  -only-testing:FlowTabTests/FlowTabTests/testRuntimeProjectionRepairProviderMockSingleAppFiveWindowsCGOffSpaceProjectionPayloadKeepsAllWindowsInHomeLayer \
  -only-testing:FlowTabTests/FlowTabTests/testRuntimeProjectionRepairProviderMockSingleAppFiveWindowsCGOffSpaceProjectionPayloadUsesExplicitTitles \
  -only-testing:FlowTabTests/FlowTabTests/testRuntimeWindowRecencyTrackerAppliesToRuntimeProjectionRepairProviderCurrentAppPayload
```

The selected run passed 7 tests with 0 failures after the approved clean rebuild.
It proves the app-hosted mock runtime projection seed can still build explicit
full-repair fixture payloads, AppInventory mock app records, appID-scoped
current-app payloads, single-app/five-window variants including CG-off-Space
IDs and explicit titles, and recency-applied current-app payloads. This closes
the runner segv validation gap only; mock projection seeds remain TestingSupport
fixture/evidence boundaries and do not become normal runtime read sources.

## Required Evidence

| Exit contract item | Current evidence | Status |
| --- | --- | --- |
| Switcher normal paths read projection/Search APIs or send dirty signals | `scripts/audit/runtime-projection-exit-contract.sh` verifies Switcher references `readAppSwitcherProjection`, `readCurrentAppWindowProjection`, `readCommittedSearchIndexForSearch`, and `requestSearchIndexFreshnessBarrier`, while rejecting legacy snapshot, repair-provider, CG, and AX sampling APIs in Switcher hot paths. | Proven by source audit |
| Switcher fullscreen presentation reads runtime Space topology projection, not frontmost/AX fullscreen probes | The exit audit now separately rejects `NSWorkspace.shared.frontmostApplication`, focused-window attributes, AX fullscreen probes, CG window-list sampling, and AX app creation inside `SwitcherPanelController+Presentation`, while requiring `readSpaceTopologyProjection()` / `signalSpaceTopologyChanged()` evidence. `testSwitcherPanelPresentationReadsRuntimeSpaceTopologyProjectionForFullscreenLevel`, `testSwitcherPanelPresentationSignalsRuntimeWhenSpaceTopologyProjectionIsMissing`, and `testSwitcherPanelPresentationFailsClosedForIncompleteSpaceTopologyProjection` prove the panel elevates only from a complete/current runtime Space topology projection, sends the dirty signal when projection is missing, and keeps the normal level without extra dirty signaling when projection freshness is incomplete/pending. | Proven by source audit and behavior tests |
| Open Switcher sessions refresh from runtime projection commits | `RuntimeProjectionService` posts app-switcher and current-app window projection commit notifications after `RuntimeReadModelStore` commits. `SwitcherPanelController` observes those notifications and only re-reads committed projections; it does not create surface-local scheduler/retry state or call snapshot/CG/AX sampling. `testSwitcherPanelControllerAppSwitcherProjectionCommitRefreshesOpenSession`, `testSwitcherPanelControllerCurrentAppProjectionCommitAppliesPendingManualWindowLayerEntry`, `testSwitcherPanelControllerCurrentAppProjectionCommitRefreshesFrozenWindowLayerPreview`, and `testSwitcherPanelControllerCurrentAppProjectionCommitKeepsWindowLayerWhenSelectedWindowIsRemoved` prove app-cycle, pending manual window-layer, already-open window-layer preview refresh, and selected-window-removed fallback behavior. `testSwitcherPanelRefreshesOpenWindowLayerAfterRealFixtureWindowSetMutation`, `testSwitcherPanelKeepsWindowLayerWhenSelectedFixtureWindowCloses`, and `testSwitcherPanelRefreshesOpenWorkflowAppWindowLayerAfterMultiAppWindowSetMutation` prove real fixture close-window mutations route through shared runtime `runtimeAXDestroyed ... affectedCGWindowID=...` evidence, keep the open Switcher window layer on the remaining committed window while the fixture process remains running, and preserve selected-app isolation in a multi-app workflow with a neighboring fullscreen fixture app. | Proven by behavior and real UI tests |
| Current-app sibling preservation is runtime-owned and activation/dirty gated | `scripts/audit/runtime-projection-exit-contract.sh` now rejects Switcher-owned current-app sibling preservation helpers and rejects app-switcher projection as a current-app sibling fact source. The positive contract requires `RuntimeReadModelStore` to own `currentAppWindowPayloadByPreservingPriorCommittedWindowsLocked(...)`, use only prior committed current-app projection state for sibling preservation, keep activation-action gating through `useForAXActivation` / `useForCGActivationFallback`, and reject dirty `CGWindowID`s. `testRuntimeReadModelStorePreservesCommittedCurrentAppSiblingRowsUntilDirtyCGInvalidatesThem`, `testRuntimeReadModelStoreDoesNotPreserveCurrentAppSiblingsFromCommittedAppSwitcherProjection`, and `testLiveSwitcherModelAppliesCommittedRuntimeWindowRecencyWhenProjectionOrderChanges` prove committed current-app sibling preservation, dirty affected-CG invalidation, prior current-app AX/CG preservation, app-switcher projection contamination rejection, activation-capable inferred CG-fallback artifact rejection, and restored window-cycle ordering. | Proven by source audit and behavior tests |
| Control+Tab focused-current-app path does not synchronously sample frontmost/focused app state | The exit audit now separately rejects `NSWorkspace.shared.frontmostApplication`, `kAXFocusedWindowAttribute`, old focused snapshot/frontmost resolver seams, and the removed frontmost bundle launch override in the Switcher/TestingSupport hot path. It also requires `readFocusedCurrentAppWindowProjection()` and `signalFocusedCurrentAppWindowsChanged()` evidence, proving the focused path either reads runtime projection or sends a dirty signal. | Proven by source audit |
| Home normal paths read projection APIs or send dirty signals | The exit audit verifies Home references `readHomeSummaryProjection`, `readHomeAppDetailProjection`, `readCurrentAppWindowProjection`, and `signalAppWindowsChanged`, while rejecting legacy snapshot, repair-provider, CG, and AX sampling APIs in Home hot paths. | Proven by source audit |
| Search reads only committed index and cannot expose staging/repair/partial/session completeness as latest | The exit audit verifies production Search freshness commits only through `RuntimeMainTableProjectionBuilding.searchIndexPayloadFromMainTables(...)` and `RuntimeReadModelStore.commitSearchFreshnessBarrierFromMainTablePayload(...)`. It also requires the runtime/Search read-model labels `missingCommittedIndex`, `degradedStaleCommittedResult`, and `committedGenerationResult`, while rejecting the old `latestCommittedResult`, `freshResult`, and `completeResult` names in production Search paths. The audit now separately requires Search surface rebuilds to call `readCommittedSearchIndexForSearch()` / `rebuildSearchIndexFromCommittedProjection(...)`, rejects Switcher/Search construction of `RuntimeSearchIndexProjection`, `RuntimeSearchIndexPayload`, `RuntimeSearchAppIndexEntry`, or `RuntimeSearchWindowIndexEntry`, requires Search result display metadata to come from `committedSearchAppsByID`, and guards the missing committed-index branch so it clears active Search state before requesting the freshness barrier. `testSwitcherPanelControllerSearchHotkeyStartsFromCommittedIndexWhenAppSwitcherProjectionMissing` proves direct Search trigger falls back from missing app-switcher projection to committed Search index without snapshot/session fallback and preserves degraded/stale metadata. `testSwitcherPanelControllerClearsActiveSearchWhenCommittedIndexBecomesMissing` proves an already-active Search clears old results, clears status, records `missingCommittedIndex`, and requests `.searchFreshnessBarrier` when the committed index read disappears. Repository-owned behavior and UI tests plus `search-committed-index-pressure.sh` provide the pre-commit, async re-entry, direct-trigger, active-missing-index and CPU/RSS evidence. | Proven by source audit plus behavior/UI/pressure evidence |
| Search freshness barrier success requires a committed new generation | Production source and retained behavior/UI tests establish `committedGenerationResult` only after bounded barrier commit from main-table payload, while pre-commit real UI state remains `missingCommittedIndex` or degraded/stale committed result. The exit audit makes this naming contract repeatable by rejecting production Search result-state labels that would call pre-barrier reads fresh, complete, or latest. | Proven by source audit, behavior tests and UI proof |
| Activation may use cached target route, but success must be verified by focused AX/CG or CG frontmost readback | The exit audit rejects direct Space setting and Window-menu shortcuts, requires `RuntimeActivator` focused AX/CG or frontmost CG readback verification plus mismatch diagnostics, and requires verified readback to flow through `RuntimeProjectionService.signalWindowFocusVerified(...)`, `RuntimeWindowRecordStore.recordWindowFocusVerification(...)`, and `readActivationTargetProjection()`. Readback mismatch now flows through `RuntimeProjectionService.signalWindowFocusReadbackMismatch(...)`, runtime dirty/freshness metadata, high-priority scoped reconciliation, and WindowRecord-owned route failure evidence that removes `useForCGActivationFallback` from the failed target projection while preserving display/preview actions. It is not an activation success and keeps committed Search reads degraded/stale until a new generation is committed. | Proven by source audit plus activation behavior tests |
| Non-registry verified-focus fallback AX readback is observable when it happens | `testRuntimeProjectionServiceSeedsVerifiedFocusRecordWhenFocusedAXWindowIsNotInRegistry` now proves the non-registry fallback AX id writes exact WindowRecord evidence, parses back to the focused `CGWindowID`, and emits a production `binding-confidence-change ... verifiedFocusFallbackAX=1` marker under debug+verbose logs. The exit audit also requires `AXWindowInspector.verifiedFocusFallbackCGWindowID(...)` and the WindowRecord `verifiedFocusFallbackAX` marker so the runtime-log oracle cannot silently disappear from production. This protects the marker that future real UI proof must use, but it does not close the real UI occurrence gap by itself. | Proven by source audit and behavior test; real UI occurrence still gap |
| Full snapshot/full repair is repair, fallback, cold-start, diagnostic, or migration compatibility only | The exit audit rejects provider-facing full-repair projection payload APIs in production. `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md` records full repair as low-priority repair/fallback with backoff and fact-splitting: app-directory evidence may cross the service boundary, while WindowRecord refresh is only a separate summary. | Proven by source audit plus behavior tests |
| Normal projection rows come from runtime main tables/read model, not repair/full-repair/session/staging/direct fallback payloads | `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md`, production builders and retained behavior tests establish the app-switcher/Home/current-app/Search main-table path, removal of direct projection-cache commit bridges, and evidence-only current/full repair boundaries. | Proven by source audit plus behavior tests |
| CG-only window-layer exposure is owned by runtime topology classification at the main-table projection boundary | `RuntimeWindowRecordStore.projectedWindowEntries(...)` now applies `RuntimeWindowTopologyClassifier.canExposeWithoutCurrentAXHandle(...)` to no-AX main-table rows, using the same desktop-wrapper/fullscreen-topology evidence as the repair assembler. `testRuntimeWindowRecordStoreDoesNotProjectDesktopProvisionalCGOnlyRecordWithoutAXHandle` proves a desktop Space 1 provisional CG-only WindowRecord with a prior activation route does not produce a normal window entry. `testSwitcherPanelOptionTabHidesDesktopProvisionalCGOnlyWorkflowWindow` first exposed the old main-table leak (`hidden-provisional-cg windows=1` but Chrome Fixture counted as `:2`), then passed after the store fix with the app strip at one AX-backed user window and no `windowCycle`/preview. The exit audit now guards the source ownership for CG-only exposure and hidden-provisional evidence. | Proven by source audit, behavior test, and real UI test |
| Representative real topology, Search, activation, and pressure proof exists | The retained tests and canonical pressure runners establish the noisy fullscreen/off-space Option+Tab round trip, committed-index Window Search real UI re-entry and activation proof, runtime-topology pressure, and external committed-index Search CPU/RSS sampling. The latest Search trigger slice passes `testSwitcherPanelWindowSearchKeepsDuplicateRealWorkflowTitlesDistinct` and `testSwitcherPanelWindowSearchMatchesAndActivatesRealWorkflowEdgeTitle`, proving trigger-driven Window Search waits for runtime committed index, shows duplicate same-title committed rows, and activates the edge-title fixture window. The latest Noisy Option+Tab slice moved noisy fullscreen row normalization into `RuntimeReadModelStore` commit ownership, preserves active `windowCycle` order across app-switcher/current-app projection refresh, removes surface-entry recency writes, and requires activation readback instead of visible-only CG fallback. The fixed-path UI runner now passes `testSwitcherPanelOptionTabWindowStateRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows`, proving the representative normal/fullscreen/incognito/second-fullscreen round trip on the updated projection/readback path. The runtime-topology pressure wrapper also passes the same UI path with 72 samples at 0.5s cadence. The pure space-backed CG-only fullscreen fixture still proves projection/selection/CG-route submission plus readback rejection (`targetCGNotVisible`) rather than exact activation success. | Proven for representative noisy topology, committed Search, activation readback rejection, and pressure paths; pure CG-only fullscreen activation success remains a gap |

## Validation Commands

Required for this audit slice:

```bash
./scripts/testing/run-flowtabtests-local.sh \
  -only-testing:FlowTabTests/FlowTabTests/testSpaceFixtureLaunchConfigurationLoadsWorkflowWindowsAndTabs \
  -only-testing:FlowTabTests/FlowTabTests/testSpaceFixtureWindowPlannerCarriesWorkflowWindowKind \
  -only-testing:FlowTabTests/FlowTabTests/testSpaceFixtureWindowCoordinatorLaunchesPanelAfterMainDocumentWindow \
  -only-testing:FlowTabTests/FlowTabTests/testSpaceFixtureWindowCoordinatorLaunchesWindowsAndSchedulesFullscreenTarget \
  -only-testing:FlowTabTests/FlowTabTests/testSpaceFixtureWindowCoordinatorSkipsFullscreenSchedulingWhenNoTargetConfigured
```

The targeted `FlowTabTests` run passed 5 selected tests with 0 failures,
proving workflow `kind` decoding, plan propagation, panel launch order
(`document -> activate -> panel`), and unchanged no-panel launch behavior.

Attempted real UI evidence:

```bash
./scripts/testing/install-ui-test-app.sh
./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelPreviewUsesRealMainPublicAXStateForPanelBackedDuplicateWindows
```

The temporary targeted UI assertion was not kept because it failed honestly:
runtime logs for the panel-backed Chrome fixture showed three public AX windows
and three CG cards, but AX topology still reported `ax:<pid>:0` as both
`focused=1` and `main=1`; no `state=main` assignment marker was present in any
runtime log. The general edge-input workflow was not expanded because doing so
also disturbed the existing Window Search edge proof. This is a real topology
gap, not an environment blocker and not completion evidence.

```bash
./scripts/audit/runtime-projection-exit-contract.sh
```

The audit now includes production checks for the non-registry verified-focus
fallback parser, grep-able `verifiedFocusFallbackAX` WindowRecord log marker,
current-app sibling preservation ownership in `RuntimeReadModelStore` instead
of Switcher surface state, and Search freshness result-state naming that keeps
pre-barrier reads missing or degraded/stale committed. It also guards the UI
runner's automation-initialization blocker classification so a test-body-before
failure cannot be confused with product/runtime evidence. The 2026-07-02 rerun
passed with all checks green, including the Switcher/Home hot-path no-snapshot
checks, Search main-table committed barrier checks, Search naming checks, Space
topology projection checks, activation focused AX/CG/frontmost CG readback
checks, and UI runner classification guard.

Current Search committed-index surface guard proof:

```bash
./scripts/testing/run-flowtabtests-local.sh \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testSwitcherPanelControllerClearsActiveSearchWhenCommittedIndexBecomesMissing \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testSwitcherPanelControllerSearchHotkeyStartsFromCommittedIndexWhenAppSwitcherProjectionMissing \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testSwitcherPanelControllerEntersSearchAfterCommittedIndexUpdateNotification
```

The targeted behavior run passed 3 selected tests with 0 failures. Before the
production fix, `testSwitcherPanelControllerClearsActiveSearchWhenCommittedIndexBecomesMissing`
failed because active Search stayed visible with old committed rows and a
`committedGenerationResult` status after the committed-index read became
`missingCommittedIndex`. After the fix, the same test proves old results are
cleared, Search is inactive, status is nil, diagnostics record
`missingCommittedIndex`, and `.searchFreshnessBarrier` is requested. The adjacent
tests prove Search can still start from a degraded/stale committed index when
app-switcher projection is missing and that only a later committed-index update
moves the session to `committedGenerationResult`.

Runner-fixed Search launch-argument UI smoke proof:

```bash
./scripts/testing/run-ui-tests-local.sh --skip-space-fixtures \
  -only-testing:FlowTabUITests/FlowTabUITests/testSearchPanelEntryAndResultActivation

./scripts/testing/install-ui-test-app.sh

./scripts/testing/run-ui-tests-local.sh --skip-space-fixtures \
  -only-testing:FlowTabUITests/FlowTabUITests/testSearchPanelEntryAndResultActivation
```

After the fixed-path app was rebuilt and Apple Development signed, the targeted
UI rerun passed 1 selected test with 0 failures in 28.786s (`59.677s` XCTest
operation elapsed). The test entered the real fixture path, found
`flowtab.switcher.search.input`, typed the fixture query, found the fixture app
Search result, and closed the panel after Return activation. This supersedes the
older optional Search launch-argument smoke failure. It does not change the
Search committed-index freshness contract: pre-barrier reads are still
`missingCommittedIndex` or degraded/stale committed, not fresh, complete,
latest, or current-generation committed.

Current UI runner fixed-path proof:

```bash
./scripts/testing/run-ui-tests-local.sh --skip-space-fixtures \
  -only-testing:FlowTabUITests/FlowTabUITests/testFlowTabUITestAppIdentityUsesEnvironmentOverridePath
```

The earlier wrapper run built and signed the UI runner, then failed before the
test body with `Timed out while enabling automation mode`. After the runner fix,
`./scripts/testing/install-ui-test-app.sh` rebuilt and signed
the user-Applications fixed app (`Flow Tab UITest.app`) with Apple Development signing,
and the same targeted UI wrapper run passed 1 selected test with 0 failures in
0.351 seconds (`1.148` seconds XCTest operation elapsed). This proves the
fixed-path runner can now enter the test body for targeted UI validation. The
blocker classifier remains guarded by the exit audit for future pre-test-body
automation failures, but the current validation state is no longer blocked.

Current CG-only exposure gate proof added by this slice:

```bash
./scripts/testing/run-flowtabtests-local.sh \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeWindowRecordStoreDoesNotProjectDesktopProvisionalCGOnlyRecordWithoutAXHandle \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeSystemRepairFactProviderWindowLayerExposesInGraceSpaceBackedRecordWithoutStickyBinding \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeWindowRecordStoreSuppressesCGActivationFallbackAfterReadbackMismatch
```

This targeted behavior run passed 3 selected tests with 0 failures. It proves
the new main-table projection gate for desktop provisional CG-only records,
keeps the existing space-backed in-grace exposure contract, and preserves the
activation-readback mismatch action downgrade.

```bash
./scripts/testing/install-ui-test-app.sh
./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelOptionTabReportsUnverifiedSpaceBackedCGOnlyWorkflowActivation \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelOptionTabHidesDesktopProvisionalCGOnlyWorkflowWindow
```

The first runner-fixed attempt for the desktop provisional case exposed the
pre-fix product signal: runtime logged `hidden-provisional-cg windows=1`, but
the app strip still showed the Chrome fixture with two windows because the
main-table projection read path reintroduced the hidden CG-only row. After the
`RuntimeWindowRecordStore` fix and reinstalling the Apple Development signed
fixed-path app, the two selected UI tests passed with 0 failures in 45.409
seconds (`46.267` seconds XCTest elapsed). This proves the representative
desktop provisional CG-only row stays out of app-switcher/window-layer UI, and
the representative space-backed CG-only route remains unverified until readback
instead of being counted as activation success.

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

Current Noisy Option+Tab projection/readback behavior proof for this slice:

```bash
./scripts/testing/run-flowtabtests-local.sh \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testLiveSwitcherModelKeepsActiveWindowCycleOrderWhenCurrentAppProjectionRefreshes \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testLiveSwitcherModelKeepsActiveWindowCycleOrderWhenAppSwitcherProjectionRefreshes \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeReadModelStoreNormalizesNoisyFullscreenRowsAtProjectionCommitBoundary \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimePresentationFilterDropsRepeatedFullscreenGeometryRowsWithoutSpaceTopology \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimePresentationFilterCollapsesFallbackNoiseWithoutGeometryEvidence \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimePresentationFilterUsesAssemblerFullscreenEvidenceForRepeatedTitles \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeActivatorContinuesRecoveryWhenCGFallbackIsVisibleWithoutActivationReadback
```

This targeted behavior run passed 7 selected tests with 0 failures. It proves
that noisy fullscreen presentation rows are normalized at the
`RuntimeReadModelStore` projection-commit boundary, active `windowCycle` order
is preserved across current-app and app-switcher projection refresh, surface
entry/selection no longer writes recency, and visible-only CG fallback in AX
recovery remains unverified until focused AX/CG or frontmost CG readback proves
the target.

Current-app sibling preservation behavior proof for the current audit:

```bash
./scripts/testing/run-flowtabtests-local.sh \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeReadModelStorePreservesCommittedCurrentAppSiblingRowsUntilDirtyCGInvalidatesThem \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeReadModelStoreDoesNotPreserveCurrentAppSiblingsFromCommittedAppSwitcherProjection \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testLiveSwitcherModelAppliesCommittedRuntimeWindowRecencyWhenProjectionOrderChanges
```

The pre-fix reproduction showed that app-switcher projection rows could leak
into current-app sibling preservation when they looked activation-capable. The
current targeted behavior run passed the selected tests with 0 failures. It
proves that missing current-app siblings can be preserved from prior committed
current-app projection state, dirty affected `CGWindowID`s invalidate preserved
siblings, and committed app-switcher projection is no longer accepted as a
current-app sibling source even when its rows carry AX or CG fallback activation
actions.

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

The install step built and signed the user-Applications fixed app (`Flow Tab UITest.app`)
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

After the projection-commit normalization and active-order preservation slice,
the app was reinstalled with Apple Development signing and the targeted Noisy
Option+Tab UI proof was refreshed to green:

```bash
./scripts/testing/install-ui-test-app.sh

./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelOptionTabWindowStateRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows
```

The fixed-path UI runner passed 1 selected test with 0 failures in 42.165
seconds (`63.925` seconds XCTest elapsed), proving the updated
normal/fullscreen/incognito/second-fullscreen round trip through committed
projection rows and activation readback. Runtime-topology pressure was then
refreshed on the same representative path. The sandbox attempt collected no
samples because `pgrep` / `sysmond` could not read the process list; the
non-sandbox rerun passed:

```bash
./scripts/perf/runtime-topology-pressure.sh 0.5
```

The pressure run passed the same UI test in 41.559 seconds with 72 samples at
0.5s cadence (`cpuAvg=30.11`, `cpuP95=60.00`, `cpuMax=76.40`,
`rssAvgMB=113.05`, `rssP95MB=168.59`, `rssMaxMB=177.86`), comparable to the
2026-06-30 70-sample baseline.

Current runner-fixed representative UI proof for this slice:

```bash
./scripts/testing/install-ui-test-app.sh

./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelOptionTabWindowStateRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelWindowSearchKeepsDuplicateRealWorkflowTitlesDistinct \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelWindowSearchMatchesAndActivatesRealWorkflowEdgeTitle \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelOptionTabReportsUnverifiedSpaceBackedCGOnlyWorkflowActivation \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelOptionTabHidesDesktopProvisionalCGOnlyWorkflowWindow
```

The install step rebuilt the user-Applications fixed app (`Flow Tab UITest.app`) and signed
it with Apple Development signing. The UI wrapper used the fixed app path and
passed 5 selected tests with 0 failures in 141.582 seconds (`147.291` seconds
XCTest operation elapsed). This refreshes the representative proof that Noisy
Option+Tab reads committed projection rows and requires activation readback,
Window Search waits for committed-index results and activates the edge-title
fixture row, duplicate same-title Search rows stay distinct, desktop provisional
CG-only rows stay out of `windowCycle`/preview, and space-backed CG-only routes
remain degraded/unverified until readback. It does not close the public AX
main-state occurrence, non-registry focused AX occurrence, pure CG-only exact
activation success, or broader multi-display/system-owner topology gaps.

### 2026-07-02 Search Mock UI Freshness Proof

The fixed-path UI runner now also proves the mock-runtime Search path that
previously stalled before the committed-index barrier could be observed. The
slice wires the panel's `LiveSwitcherModel` to the resolved runtime projection
service, installs the mock runtime app-directory provider only through the
runtime maintenance boundary, and preserves app-directory PID ownership through
`RuntimeAppContext.ownerPID` so mock selected-app dirty signals do not use the
FlowTab process PID as the target app PID.

Validation:

```bash
./scripts/testing/run-flowtabtests-local.sh \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeMainTableProjectionBuilderBuildsAppSwitcherPayloadFromMainTables

./scripts/testing/install-ui-test-app.sh

./scripts/testing/run-ui-tests-local.sh --skip-space-fixtures \
  -only-testing:FlowTabUITests/FlowTabUITests/testSearchHeaderHighlightedAppChipStaysContentSizedForShortTitle

./scripts/testing/run-ui-tests-local.sh --skip-space-fixtures \
  -only-testing:FlowTabUITests/FlowTabUITests/testSearchPanelChineseQueryShowsChineseMockResult

./scripts/audit/runtime-projection-exit-contract.sh
```

The targeted builder test passed 1 selected test with 0 failures. The UI app was
rebuilt and Apple Development signed, then both Search UI tests passed with 0
failures. Runtime log `Flow_Tab_20260702_210230.log` shows the required
freshness progression: initial Search read is `missingCommittedIndex`; the first
committed-index notification is still `degradedStaleCommittedResult` with
`committedIndexCoversCurrentGeneration=0`; only after the bounded barrier commits
again with dirty metadata cleared does Search report `committedGenerationResult`
with `committedIndexCoversCurrentGeneration=1`. This is degraded/stale committed
behavior until barrier success, not a fresh/complete/latest result.

The previous app-hosted mock dataset segv is now superseded by the 7-test
FlowTabTests run above. No production runtime behavior or TestingSupport
semantics changed to obtain that proof.

## Phase 7 Control+Tab Degraded Current-App Read

This slice closes the Control+Tab read-path gap exposed by the repaired UI
runner. `LiveSwitcherModel.startFocusedAppWindowSession(...)` still reads only
the focused current-app projection from `RuntimeReadModelStore`; when that
projection is stale but contains committed windows, it opens the window layer as
`degradedStaleCommitted` and sends `signalFocusedCurrentAppWindowsChanged()` for
background maintenance. It does not synchronously wait for CG/AX/Space sampling
and it does not describe the stale order as fresh, complete, latest, or
current-generation.

Validation:

```bash
./scripts/testing/run-flowtabtests-local.sh \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testLiveSwitcherModelFocusedWindowSessionUsesStaleCommittedProjectionAsDegradedRead

./scripts/testing/install-ui-test-app.sh

./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testInAppWindowSwitcherControlTabRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows
```

The behavior test passed 1 selected FlowTabTests test with 0 failures. The
fixed-path UI app was rebuilt and Apple Development signed; after one pre-test
automation-mode timeout and one stale-order oracle correction, the targeted
Noisy Control+Tab UI proof passed 1 selected test with 0 failures in 39.785s
(`40.657s` XCTest elapsed). Runtime logs show reopen using
`startFocusedWindowSession result=degradedStaleCommitted ... windows=4`, and the
UI proof verifies the four real workflow windows, filtered noisy CG/fullscreen
artifacts, sticky/runtime-owned window source logs, exact selected `CGWindowID`
activation, and verified focus readback.

Search is unchanged in this slice. Before a bounded freshness barrier
successfully commits a new generation, Search remains `missingCommittedIndex` or
a degraded/stale committed result with dirty/freshness metadata; it is not a
fresh, complete, latest, current-generation committed, or newest complete
result.

## Remaining Gaps

These are breadth/hardening gaps and do not currently contradict the target
runtime shape:

- Real UI occurrence of non-registry focused AX readback is not separately
  forced; production logs can now identify natural fallback hits with
  `verifiedFocusFallbackAX=1`, and behavior coverage protects that marker, but
  no real occurrence has closed the gap yet. The refreshed Noisy Option+Tab UI
  and pressure proofs close the representative noisy topology/order/readback
  path. A 2026-07-02 runner-fixed targeted UI rerun also passed Noisy
  Option+Tab plus the focused/minimized edge-input proof set, but the runtime
  log still did not naturally emit a `verifiedFocusFallbackAX=1` non-registry
  focused AX occurrence.
- Public AX main/minimized tie-breaker variants still need real UI occurrence
  proof. Focused/main/minimized deterministic matcher coverage is now present,
  including the combined priority order where focused claims the first onscreen
  candidate, main claims the next onscreen candidate, and minimized claims the
  offscreen candidate. On 2026-07-02 the fixed-path app was reinstalled with
  Apple Development signing and the runner-fixed existing edge-input UI tests
  passed, refreshing target-app `state=focused` and minimized-state capture
  proof. The same runtime log did not emit `public-state-tiebreak state=main`,
  so no main-state UI proof was produced. A later panel-backed fixture attempt
  added a standard document plus key-only panel capability and reached a real UI
  run with three Chrome fixture cards, but public AX still exposed the same
  window as `focused=1` and `main=1`; the attempted proof was not committed as a
  passing UI test and the gap remains open.
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

## Final Completion Decision

The current production boundary is projection-driven for the named normal paths:
Switcher, Home, Search, and activation either read runtime projections/committed
Search index, send dirty signals, or commit activation readback/mismatch
diagnostics. Full repair and snapshot-shaped data are constrained to
repair/fallback/cold-start/diagnostic or test compatibility boundaries. Search
must remain `missingCommittedIndex` or a degraded/stale committed result until a
bounded freshness barrier commits a new main-table generation.

The final Phase 7 completion audit accepts the remaining gaps above as
breadth/hardening gaps, not blockers for the requested target shape. They still
need future representative UI/E2E, runtime-log, or pressure evidence before they
can move from gap to closed proof, but they do not show a normal user path
falling back to shared snapshots, repair payload rows, Search staging/session
completeness, direct Space setting, Window-menu shortcuts, or unverified
activation success.

Final validation for this decision:

```bash
scripts/audit/runtime-projection-exit-contract.sh
```

The audit passed on 2026-07-02, including surface hot-path no-snapshot checks,
Switcher/Home projection and dirty-signal evidence, Control+Tab focused
projection evidence, Search committed-index/main-table barrier evidence,
pre-barrier Search naming guards, activation focused AX/CG or frontmost CG
readback guards, CG-only exposure policy ownership, and UI-runner blocker
classification. Existing behavior, UI, and pressure evidence recorded above
and retained by the named tests and canonical Runners remains the representative
validation set for the completed core goal.
