# Runtime Projection Completion Audit

Updated: 2026-07-02

This audit is the Phase 7 closure ledger for `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md`.
It records current evidence for the projection-driven runtime exit contract without
reclassifying breadth proof as core completion work.

## Current Phase 7 Slice

- P0: harden the UI validation runner boundary after repeated
  `Timed out while enabling automation mode` failures. `run-ui-tests-local.sh`
  now captures each xcodebuild action log under `.build-local/ui-tests/logs/`
  and classifies automation-mode initialization timeouts as a UI automation
  initialization blocker before any test body can produce product/runtime
  evidence. The repeatable exit-contract audit now requires that log capture,
  timeout detection, blocker classification, and "not a FlowTab runtime
  assertion failure" wording remain present in the UI wrapper.
- P1: keep `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md`, `TEST_COVERAGE_MATRIX.md`,
  and this audit aligned with the new validation-runner evidence, then rerun
  the repeatable source exit-contract audit.
- P2: keep pure CG-only activation success, broader multi-display/system-owner
  topology, real non-registry focused AX occurrence, and public AX main-state
  real UI occurrence gaps explicit.

This slice does not add a new runtime state owner, alter UI test semantics, or
change Search behavior. It makes a required Phase 7 validation failure mode
machine-readable in the runner output: when XCTest never enters a UI test body,
the result is an environment/runner blocker, not evidence for or against the
projection runtime. Search remains missing committed index or degraded/stale
committed until a bounded freshness barrier commits a new main-table generation.

## Required Evidence

| Exit contract item | Current evidence | Status |
| --- | --- | --- |
| Switcher normal paths read projection/Search APIs or send dirty signals | `scripts/audit/runtime-projection-exit-contract.sh` verifies Switcher references `readAppSwitcherProjection`, `readCurrentAppWindowProjection`, `readCommittedSearchIndexForSearch`, and `requestSearchIndexFreshnessBarrier`, while rejecting legacy snapshot, repair-provider, CG, and AX sampling APIs in Switcher hot paths. | Proven by source audit |
| Switcher fullscreen presentation reads runtime Space topology projection, not frontmost/AX fullscreen probes | The exit audit now separately rejects `NSWorkspace.shared.frontmostApplication`, focused-window attributes, AX fullscreen probes, CG window-list sampling, and AX app creation inside `SwitcherPanelController+Presentation`, while requiring `readSpaceTopologyProjection()` / `signalSpaceTopologyChanged()` evidence. `testSwitcherPanelPresentationReadsRuntimeSpaceTopologyProjectionForFullscreenLevel`, `testSwitcherPanelPresentationSignalsRuntimeWhenSpaceTopologyProjectionIsMissing`, and `testSwitcherPanelPresentationFailsClosedForIncompleteSpaceTopologyProjection` prove the panel elevates only from a complete/current runtime Space topology projection, sends the dirty signal when projection is missing, and keeps the normal level without extra dirty signaling when projection freshness is incomplete/pending. | Proven by source audit and behavior tests |
| Open Switcher sessions refresh from runtime projection commits | `RuntimeProjectionService` posts app-switcher and current-app window projection commit notifications after `RuntimeReadModelStore` commits. `SwitcherPanelController` observes those notifications and only re-reads committed projections; it does not create surface-local scheduler/retry state or call snapshot/CG/AX sampling. `testSwitcherPanelControllerAppSwitcherProjectionCommitRefreshesOpenSession`, `testSwitcherPanelControllerCurrentAppProjectionCommitAppliesPendingManualWindowLayerEntry`, `testSwitcherPanelControllerCurrentAppProjectionCommitRefreshesFrozenWindowLayerPreview`, and `testSwitcherPanelControllerCurrentAppProjectionCommitKeepsWindowLayerWhenSelectedWindowIsRemoved` prove app-cycle, pending manual window-layer, already-open window-layer preview refresh, and selected-window-removed fallback behavior. `testSwitcherPanelRefreshesOpenWindowLayerAfterRealFixtureWindowSetMutation`, `testSwitcherPanelKeepsWindowLayerWhenSelectedFixtureWindowCloses`, and `testSwitcherPanelRefreshesOpenWorkflowAppWindowLayerAfterMultiAppWindowSetMutation` prove real fixture close-window mutations route through shared runtime `runtimeAXDestroyed ... affectedCGWindowID=...` evidence, keep the open Switcher window layer on the remaining committed window while the fixture process remains running, and preserve selected-app isolation in a multi-app workflow with a neighboring fullscreen fixture app. | Proven by behavior and real UI tests |
| Current-app sibling preservation is runtime-owned and activation/dirty gated | `scripts/audit/runtime-projection-exit-contract.sh` now rejects Switcher-owned current-app sibling preservation helpers and rejects app-switcher projection as a current-app sibling fact source. The positive contract requires `RuntimeReadModelStore` to own `currentAppWindowPayloadByPreservingPriorCommittedWindowsLocked(...)`, use only prior committed current-app projection state for sibling preservation, keep activation-action gating through `useForAXActivation` / `useForCGActivationFallback`, and reject dirty `CGWindowID`s. `testRuntimeReadModelStorePreservesCommittedCurrentAppSiblingRowsUntilDirtyCGInvalidatesThem`, `testRuntimeReadModelStoreDoesNotPreserveCurrentAppSiblingsFromCommittedAppSwitcherProjection`, and `testLiveSwitcherModelAppliesCommittedRuntimeWindowRecencyWhenProjectionOrderChanges` prove committed current-app sibling preservation, dirty affected-CG invalidation, prior current-app AX/CG preservation, app-switcher projection contamination rejection, activation-capable inferred CG-fallback artifact rejection, and restored window-cycle ordering. | Proven by source audit and behavior tests |
| Control+Tab focused-current-app path does not synchronously sample frontmost/focused app state | The exit audit now separately rejects `NSWorkspace.shared.frontmostApplication`, `kAXFocusedWindowAttribute`, old focused snapshot/frontmost resolver seams, and the removed frontmost bundle launch override in the Switcher/TestingSupport hot path. It also requires `readFocusedCurrentAppWindowProjection()` and `signalFocusedCurrentAppWindowsChanged()` evidence, proving the focused path either reads runtime projection or sends a dirty signal. | Proven by source audit |
| Home normal paths read projection APIs or send dirty signals | The exit audit verifies Home references `readHomeSummaryProjection`, `readHomeAppDetailProjection`, `readCurrentAppWindowProjection`, and `signalAppWindowsChanged`, while rejecting legacy snapshot, repair-provider, CG, and AX sampling APIs in Home hot paths. | Proven by source audit |
| Search reads only committed index and cannot expose staging/repair/partial/session completeness as latest | The exit audit verifies production Search freshness commits only through `RuntimeMainTableProjectionBuilding.searchIndexPayloadFromMainTables(...)` and `RuntimeReadModelStore.commitSearchFreshnessBarrierFromMainTablePayload(...)`. It also requires the runtime/Search read-model labels `missingCommittedIndex`, `degradedStaleCommittedResult`, and `committedGenerationResult`, while rejecting the old `latestCommittedResult`, `freshResult`, and `completeResult` names in production Search paths. `TEST_COVERAGE_MATRIX.md` records behavior/UI/pressure proof for pre-commit reads that are `missingCommittedIndex` or degraded/stale committed result, committed-generation async re-entry, and external committed-index Search CPU/RSS sampling. | Proven by source audit plus behavior/UI/pressure evidence |
| Search freshness barrier success requires a committed new generation | `TEST_COVERAGE_MATRIX.md` records `committedGenerationResult` only after bounded barrier commit from main-table payload, and records pre-commit real UI state as `missingCommittedIndex` or degraded/stale committed result rather than fresh/complete/latest. The exit audit now makes this naming contract repeatable by rejecting production Search result-state labels that would call pre-barrier reads fresh, complete, or latest. | Proven by matrix-backed tests and UI proof |
| Activation may use cached target route, but success must be verified by focused AX/CG or CG frontmost readback | The exit audit rejects direct Space setting and Window-menu shortcuts, requires `RuntimeActivator` focused AX/CG or frontmost CG readback verification plus mismatch diagnostics, and requires verified readback to flow through `RuntimeProjectionService.signalWindowFocusVerified(...)`, `RuntimeWindowRecordStore.recordWindowFocusVerification(...)`, and `readActivationTargetProjection()`. Readback mismatch now flows through `RuntimeProjectionService.signalWindowFocusReadbackMismatch(...)`, runtime dirty/freshness metadata, high-priority scoped reconciliation, and WindowRecord-owned route failure evidence that removes `useForCGActivationFallback` from the failed target projection while preserving display/preview actions. It is not an activation success and keeps committed Search reads degraded/stale until a new generation is committed. | Proven by source audit plus activation behavior tests |
| Non-registry verified-focus fallback AX readback is observable when it happens | `testRuntimeProjectionServiceSeedsVerifiedFocusRecordWhenFocusedAXWindowIsNotInRegistry` now proves the non-registry fallback AX id writes exact WindowRecord evidence, parses back to the focused `CGWindowID`, and emits a production `binding-confidence-change ... verifiedFocusFallbackAX=1` marker under debug+verbose logs. The exit audit also requires `AXWindowInspector.verifiedFocusFallbackCGWindowID(...)` and the WindowRecord `verifiedFocusFallbackAX` marker so the runtime-log oracle cannot silently disappear from production. This protects the marker that future real UI proof must use, but it does not close the real UI occurrence gap by itself. | Proven by source audit and behavior test; real UI occurrence still gap |
| Full snapshot/full repair is repair, fallback, cold-start, diagnostic, or migration compatibility only | The exit audit rejects provider-facing full-repair projection payload APIs in production. `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md` records full repair as low-priority repair/fallback with backoff and fact-splitting: app-directory evidence may cross the service boundary, while WindowRecord refresh is only a separate summary. | Proven by source audit plus behavior tests |
| Normal projection rows come from runtime main tables/read model, not repair/full-repair/session/staging/direct fallback payloads | `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md` and `TEST_COVERAGE_MATRIX.md` record main-table builders for app-switcher/Home/current-app/Search, production removal of direct app-switcher/Home/Search projection-cache commit bridges, and evidence-only current/full repair boundaries. | Proven by source audit plus behavior tests |
| Representative real topology, Search, activation, and pressure proof exists | `TEST_COVERAGE_MATRIX.md` records the noisy fullscreen/off-space Option+Tab round trip, committed-index Window Search real UI re-entry and activation proof, runtime-topology pressure, and external committed-index Search CPU/RSS sampling. The latest Noisy Option+Tab slice moved noisy fullscreen row normalization into `RuntimeReadModelStore` commit ownership, preserves active `windowCycle` order across app-switcher/current-app projection refresh, removes surface-entry recency writes, and requires activation readback instead of visible-only CG fallback. The fixed-path UI runner now passes `testSwitcherPanelOptionTabWindowStateRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows`, proving the representative normal/fullscreen/incognito/second-fullscreen round trip on the updated projection/readback path. The runtime-topology pressure wrapper also passes the same UI path with 72 samples at 0.5s cadence. The pure space-backed CG-only fullscreen fixture still proves projection/selection/CG-route submission plus readback rejection (`targetCGNotVisible`) rather than exact activation success. | Proven for representative noisy topology, committed Search, activation readback rejection, and pressure paths; pure CG-only fullscreen activation success remains a gap |

## Validation Commands

Required for this audit slice:

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

Current UI runner classification proof:

```bash
./scripts/testing/run-ui-tests-local.sh --skip-space-fixtures \
  -only-testing:FlowTabUITests/FlowTabUITests/testFlowTabUITestAppIdentityUsesEnvironmentOverridePath
```

The wrapper built and signed the UI runner, then failed before the test body
with `Timed out while enabling automation mode`. The wrapper now emits
`Classification: UI automation initialization blocker` plus the fixed-path app,
runner app, result bundle, and xcodebuild log paths. This proves the validation
boundary classifies the blocker instead of leaving later handoffs to infer
whether the failure is a product/runtime assertion.

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

## Remaining Gaps

These are breadth/hardening gaps and do not currently contradict the target
runtime shape:

- Real UI occurrence of non-registry focused AX readback is not separately
  forced; production logs can now identify natural fallback hits with
  `verifiedFocusFallbackAX=1`, and behavior coverage protects that marker, but
  no real occurrence has closed the gap yet. The refreshed Noisy Option+Tab UI
  and pressure proofs close the representative noisy topology/order/readback
  path, but they did not naturally emit a `verifiedFocusFallbackAX=1`
  non-registry focused AX occurrence.
- Public AX main/minimized tie-breaker variants still need real UI occurrence
  and broader state permutation proof; focused/main/minimized deterministic
  matcher coverage is now present. On 2026-07-02 the fixed-path app was
  reinstalled with Apple Development signing and the existing edge-input UI
  tests were attempted twice to look for real `state=main` evidence, but both
  runs failed before the test body with `Timed out while enabling automation
  mode`; no main-state UI proof was produced.
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
