# Runtime Projection Completion Audit

Updated: 2026-06-30

This audit is the Phase 7 closure ledger for `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md`.
It records current evidence for the projection-driven runtime exit contract without
reclassifying breadth proof as core completion work.

## Phase 7 Slice

- P0: make the current exit-contract evidence reviewable in one place.
- P1: keep `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md` and `TEST_COVERAGE_MATRIX.md`
  aligned with this audit.
- P2: keep remaining topology and public-AX breadth gaps explicit.

This is not a new runtime behavior slice. It is an evidence audit over the
current production boundaries, tests, UI proof, pressure proof, and documented
remaining gaps.

## Required Evidence

| Exit contract item | Current evidence | Status |
| --- | --- | --- |
| Switcher normal paths read projection/Search APIs or send dirty signals | `scripts/audit/runtime-projection-exit-contract.sh` verifies Switcher references `readAppSwitcherProjection`, `readCurrentAppWindowProjection`, `readCommittedSearchIndexForSearch`, and `requestSearchIndexFreshnessBarrier`, while rejecting legacy snapshot, repair-provider, CG, and AX sampling APIs in Switcher hot paths. | Proven by source audit |
| Control+Tab focused-current-app path does not synchronously sample frontmost/focused app state | The exit audit now separately rejects `NSWorkspace.shared.frontmostApplication`, `kAXFocusedWindowAttribute`, old focused snapshot/frontmost resolver seams, and the removed frontmost bundle launch override in the Switcher/TestingSupport hot path. It also requires `readFocusedCurrentAppWindowProjection()` and `signalFocusedCurrentAppWindowsChanged()` evidence, proving the focused path either reads runtime projection or sends a dirty signal. | Proven by source audit |
| Home normal paths read projection APIs or send dirty signals | The exit audit verifies Home references `readHomeSummaryProjection`, `readHomeAppDetailProjection`, `readCurrentAppWindowProjection`, and `signalAppWindowsChanged`, while rejecting legacy snapshot, repair-provider, CG, and AX sampling APIs in Home hot paths. | Proven by source audit |
| Search reads only committed index and cannot expose staging/repair/partial/session completeness as latest | The exit audit verifies production Search freshness commits only through `RuntimeMainTableProjectionBuilding.searchIndexPayloadFromMainTables(...)` and `RuntimeReadModelStore.commitSearchFreshnessBarrierFromMainTablePayload(...)`. `TEST_COVERAGE_MATRIX.md` records behavior/UI/pressure proof for pre-commit reads that are `missingCommittedIndex` or degraded/stale committed result, committed-generation async re-entry, and external committed-index Search CPU/RSS sampling. | Proven by source audit plus behavior/UI/pressure evidence |
| Search freshness barrier success requires a committed new generation | `TEST_COVERAGE_MATRIX.md` records `committedGenerationResult` only after bounded barrier commit from main-table payload, and records pre-commit real UI state as `missingCommittedIndex` or degraded/stale committed result rather than fresh/complete/latest. | Proven by matrix-backed tests and UI proof |
| Activation may use cached target route, but success must be verified by focused AX/CG or CG frontmost readback | The exit audit rejects direct Space setting and Window-menu shortcuts, requires `RuntimeActivator` focused AX/CG or frontmost CG readback verification plus mismatch diagnostics, and requires verified readback to flow through `RuntimeProjectionService.signalWindowFocusVerified(...)`, `RuntimeWindowRecordStore.recordWindowFocusVerification(...)`, and `readActivationTargetProjection()`. | Proven by source audit plus activation behavior tests |
| Full snapshot/full repair is repair, fallback, cold-start, diagnostic, or migration compatibility only | The exit audit rejects provider-facing full-repair projection payload APIs in production. `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md` records full repair as low-priority repair/fallback with backoff and fact-splitting: app-directory evidence may cross the service boundary, while WindowRecord refresh is only a separate summary. | Proven by source audit plus behavior tests |
| Normal projection rows come from runtime main tables/read model, not repair/full-repair/session/staging/direct fallback payloads | `RUNTIME_AX_CG_SPACE_WINDOW_MAPPING.md` and `TEST_COVERAGE_MATRIX.md` record main-table builders for app-switcher/Home/current-app/Search, production removal of direct app-switcher/Home/Search projection-cache commit bridges, and evidence-only current/full repair boundaries. | Proven by source audit plus behavior tests |
| Representative real topology, Search, activation, and pressure proof exists | `TEST_COVERAGE_MATRIX.md` records the noisy fullscreen/off-space Option+Tab round trip, committed-index Window Search real UI re-entry and activation proof, runtime-topology pressure, and external committed-index Search CPU/RSS sampling. The fixed-path runner was refreshed on 2026-06-30 and the representative UI proof set below passed again. | Proven for representative paths |

## Validation Commands

Required for this audit slice:

```bash
./scripts/audit/runtime-projection-exit-contract.sh
```

Representative neighboring behavior proof already used by the current audit:

```bash
./scripts/testing/run-flowtabtests-local.sh \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeActivatorDoesNotVerifyCGFallbackWhenTargetIsVisibleButNotFrontmost \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeActivatorVerifiesFocusWhenFocusedAXCGMatchesOffscreenTargetCG \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeProjectionServiceCommitsVerifiedFocusProjectionFromMainTablesAsStale
```

Post-runner-fix representative UI proof refreshed for this audit:

```bash
./scripts/testing/install-ui-test-app.sh

./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelOptionTabWindowStateRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelWindowSearchRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithoutAppAXWindows \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelPreviewKeepsIdenticalRealWorkflowWindowsDistinct \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelPreviewCapturesRealMinimizedPublicAXState
```

The install step built and signed `{user-home}/Applications/Flow Tab UITest.app`
with Apple Development signing. The UI wrapper used that fixed app path and
passed 4 selected tests with 0 failures in 125.302 seconds. This refresh proves
the representative noisy fullscreen/off-space topology round trip, committed
Search-index real UI re-entry and activation, target-app focused public AX
tie-breaker, and minimized public AX state capture on the repaired runner.

Broader pressure proof was not re-run for this validation slice because no
production behavior, hot path, activation route, Search barrier, scheduler, or
sampling cadence changes here. Current pressure proof remains recorded in
`TEST_COVERAGE_MATRIX.md`.

## Remaining Gaps

These are breadth/hardening gaps and do not currently contradict the target
runtime shape:

- Real UI occurrence of non-registry focused AX readback is not separately forced.
- Main/minimized public AX tie-breaker variants still need broader state
  permutation proof.
- Broader multi-display/fullscreen topology and system-authoritative fullscreen
  owner proof remain partial.
- Broader lifecycle refresh while an open Switcher session mutates continues to
  be tracked under runtime snapshot/window-record coverage.

Do not mark these as completed from mock-only evidence. They need representative
UI/E2E, runtime log, or pressure evidence before moving from breadth gap to
closed proof.

## Current Conclusion

The current production boundary is projection-driven for the named normal paths:
Switcher, Home, Search, and activation either read runtime projections/committed
Search index, send dirty signals, or commit activation readback. Full repair and
snapshot-shaped data are constrained to repair/fallback/cold-start/diagnostic or
test compatibility boundaries. Search must remain `missingCommittedIndex` or a
degraded/stale committed result until a bounded freshness barrier commits a new
main-table generation.

The goal should stay open until the final handoff chooses whether the remaining
breadth gaps are accepted as non-blocking or one of them is promoted to required
completion proof.
