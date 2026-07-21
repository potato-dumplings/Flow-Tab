# FlowTab Stable Test Coverage Contract

Updated: 2026-07-21

## Purpose and authority

This document is the authoritative stable cross-layer contract for FlowTab product scenarios. It records product meaning and the evidence responsibilities selected before a change is validated. Current pass/fail observations, blockers, and run history belong in engineering handoffs or active `docs/test-audit/` artifacts.

Exhaustive executable inventory, target membership, runner, fixture, TestingSupport, dependency, consumer, and method-to-scenario mappings are owned by [TEST_ASSET_LEDGER.jsonl](test-audit/TEST_ASSET_LEDGER.jsonl). Representative anchors below make each stable contract reviewable; query ledger rows containing the scenario ID for the complete current mapping.

Companion references: [UNIT_AND_BEHAVIOR_TEST_COVERAGE.md](UNIT_AND_BEHAVIOR_TEST_COVERAGE.md), [UI_AUTOMATION_TEST_COVERAGE.md](UI_AUTOMATION_TEST_COVERAGE.md), [TEST_COVERAGE_CHECKLIST.md](TEST_COVERAGE_CHECKLIST.md), and [SPACE_FIXTURE_APP_WORKFLOW.md](SPACE_FIXTURE_APP_WORKFLOW.md).

## Field model

- `Requiredness`: `required` for an active product contract, or a named trigger for conditional infrastructure/gates.
- `Owner`: the lowest authoritative module or infrastructure boundary.
- `Oracle`: the product outcome that defines expected results independently of an implementation.
- `Required layers`: distinct evidence that must be current when the scenario changes.
- `Conditional layers`: evidence required only when the stated risk trigger applies.
- `Not relevant layers`: layers excluded from the stable scenario with a concrete reason.
- `Risk`: one or more of `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system`, `hot-path-scale-sensitive`, and `tooling-fixture`.

The six layer keys are `Unit`, `Behavior`, `Mock UI`, `Real-topology UI`, `Pressure`, and `Process/Tooling`. UI layers prove visible outcomes; real-topology UI additionally proves external apps, windows, Spaces, permissions, or system-owned lifecycle.

## Scenario index

| Stable ID | Product scenario | Requiredness | Owner | Risk |
| --- | --- | --- | --- | --- |
| `scenario:app-launch-lifecycle-status-item` | App launch, lifecycle, and status item | required | App | `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system`, `hot-path-scale-sensitive` |
| `scenario:command-tab-takeover` | Command-Tab takeover | required | App | `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system` |
| `scenario:core-grouping-switcher-session` | Core grouping and switcher session state | required | FlowTabCore | `deterministic-rule`, `app-orchestration` |
| `scenario:global-hotkey-monitor-lifecycle` | Global hotkey monitor lifecycle | required | App | `app-orchestration`, `real-topology-external-system` |
| `scenario:home-app-window-list` | Home app and window list | required | Home | `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system`, `hot-path-scale-sensitive` |
| `scenario:hotkey-configuration-normalization` | Hotkey configuration normalization | required | Preferences | `deterministic-rule`, `app-orchestration`, `visible-workflow` |
| `scenario:in-app-window-hotkey` | In-app window hotkey | required | Switcher | `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system`, `hot-path-scale-sensitive` |
| `scenario:logs-diagnostics` | Logs and diagnostics | required | Logs | `deterministic-rule`, `app-orchestration`, `visible-workflow` |
| `scenario:performance-pressure-gates` | Performance and pressure gates | conditional: required whenever hot-path or scale-sensitive risk applies | Performance | `hot-path-scale-sensitive`, `tooling-fixture` |
| `scenario:release-artifact-integrity` | Public release artifact integrity | required | Release Tooling | `deterministic-rule`, `tooling-fixture` |
| `scenario:runtime-activation-recovery` | Runtime activation and recovery | required | Runtime | `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system`, `hot-path-scale-sensitive` |
| `scenario:runtime-snapshot-window-records` | Runtime snapshot, AX/CG mapping, and window records | required | Runtime | `deterministic-rule`, `app-orchestration`, `real-topology-external-system`, `hot-path-scale-sensitive` |
| `scenario:search-result-activation` | Search panel and result activation | required | Switcher | `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system`, `hot-path-scale-sensitive` |
| `scenario:settings-app-visibility` | Settings: app visibility exclusions | required | Settings | `deterministic-rule`, `app-orchestration`, `visible-workflow`, `hot-path-scale-sensitive` |
| `scenario:settings-appearance` | Settings: appearance | required | Settings | `deterministic-rule`, `app-orchestration`, `visible-workflow` |
| `scenario:settings-layout-control-chrome` | Settings: page layout and control chrome | required | Settings | `deterministic-rule`, `app-orchestration`, `visible-workflow` |
| `scenario:settings-permission-controls` | Settings: permission controls | required | Settings | `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system` |
| `scenario:settings-search` | Settings: search | required | Settings | `deterministic-rule`, `app-orchestration`, `visible-workflow`, `hot-path-scale-sensitive` |
| `scenario:settings-window-behavior` | Settings: window behavior | required | Settings | `deterministic-rule`, `app-orchestration`, `visible-workflow`, `hot-path-scale-sensitive` |
| `scenario:space-fixture-infrastructure` | Space fixture workflow infrastructure | conditional: required whenever real-topology UI evidence is selected | Testing Infrastructure | `deterministic-rule`, `real-topology-external-system`, `tooling-fixture` |
| `scenario:switcher-standard-panel` | Switcher standard panel flow | required | Switcher | `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system`, `hot-path-scale-sensitive` |
| `scenario:terminate-selected-app` | Terminate selected app | required | Switcher | `app-orchestration`, `visible-workflow`, `real-topology-external-system` |
| `scenario:window-previews-icons` | Window previews and icons | required | Runtime | `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system`, `hot-path-scale-sensitive` |

## Stable scenario contracts

### `scenario:app-launch-lifecycle-status-item` — App launch, lifecycle, and status item

- Requiredness: required
- Owner: `App`
- Oracle: Launch, preference reload, root-window, status-item, and termination orchestration produce the expected app lifecycle state.
- Risk: `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system`, `hot-path-scale-sensitive`
- Required layers:
  - Unit: Own launch-option and launch-identity/configuration parsing rules.
  - Behavior: Prove AppDelegate launch, reload, observer cleanup, close-window persistence, status-item, and termination orchestration.
  - Mock UI: Prove launch, close/reopen, selected-tab restoration, and status-item quit user paths.
  - Real-topology UI: Prove workspace launch and termination signals update FlowTab against a real fixture process.
- Conditional layers:
  - Pressure: Required when startup time, repeated lifecycle observers, or stress-runner startup changes.
- Not relevant layers:
  - Process/Tooling: Shared launch/UI wrappers are governed by performance-pressure-gates.
- Current representative test anchors:
  - Unit: `FlowTabTests.testFlowTabTestLaunchOptionsParsesBooleanAndValueOverrides`, `FlowTabTests.testFlowTabTestLaunchOptionsSuppressesHomeWindowForUnitTestHost`
  - Behavior: `FlowTabPriorityCoverageTests.testAppDelegateLaunchInstallsObserversPromptsAccessibilityAndStartsStressRunner`, `FlowTabPriorityCoverageTests.testAppDelegateKeepsAppRunningAfterLastWindowCloses`
  - Mock UI: `FlowTabUITests.testStatusItemReopensLastSelectedTabAfterWindowClose`
  - Real-topology UI: `FlowTabUITests.testRuntimeLifecycleRefreshesRealFixtureAppLaunchAndTermination`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:app-launch-lifecycle-status-item`.

### `scenario:release-artifact-integrity` — Public release artifact integrity

- Requiredness: required
- Owner: `Release Tooling`
- Oracle: A public Release executable contains production launch behavior and no testing bootstrap, destructive test control, Darwin test-notification, or stress-exit command surface.
- Risk: `deterministic-rule`, `tooling-fixture`
- Required layers:
  - Process/Tooling: Build the Release app and reject the artifact when its executable contains a reserved test-control marker.
- Not relevant layers:
  - Unit: The contract concerns the linked artifact after compiler-condition evaluation.
  - Behavior: In-process tests run through the dedicated Testing configuration and cannot prove Release linkage.
  - Mock UI: The Release executable inspection is the direct oracle.
  - Real-topology UI: External window topology does not affect compiled control-surface membership.
  - Pressure: Artifact membership is independent of sustained runtime load.
- Current representative test anchors:
  - Process/Tooling: `scripts/release/verify-release-binary.sh`, invoked by both public Release packaging scripts.

### `scenario:command-tab-takeover` — Command-Tab takeover

- Requiredness: required
- Owner: `App`
- Oracle: Takeover follows the configured state, routes the real shortcut to FlowTab, and restores the system shortcut on exit.
- Risk: `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system`
- Required layers:
  - Unit: Own Command-Tab configuration resolution without losing the Command modifier.
  - Behavior: Own takeover activation, rollback, abnormal-exit recovery, and restore.
  - Real-topology UI: Prove the real system shortcut routes to FlowTab and is restored on exit.
- Not relevant layers:
  - Mock UI: A mocked shortcut does not prove takeover of the system-owned Command-Tab route.
  - Pressure: Takeover reconciliation is lifecycle work, not a sustained hot path.
  - Process/Tooling: No scenario-specific runner contract is required beyond the canonical UI wrapper.
- Current representative test anchors:
  - Unit: `FlowTabTests.testResolveKeepsCommandWhenMainShortcutIsCommandTab`
  - Behavior: `FlowTabPriorityCoverageTests.testCommandTabTakeoverControllerReconcileActivatesAndRestoreReenablesSystemShortcuts`
  - Real-topology UI: `FlowTabUITests.testSettingsCommandTabTakeoverTriggersSwitcherAndRestoresSystemShortcut`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:command-tab-takeover`.

### `scenario:core-grouping-switcher-session` — Core grouping and switcher session state

- Requiredness: required
- Owner: `FlowTabCore`
- Oracle: Deterministic grouping, navigation, selection, commit, and remembered-window state match the explicit input model.
- Risk: `deterministic-rule`, `app-orchestration`
- Required layers:
  - Unit: Own grouping, navigation, selection, commit, edge, and remembered-window rules.
  - Behavior: Prove app hotkey and panel orchestration consume the session rule.
- Conditional layers:
  - Pressure: Required when the change affects repeated navigation, selection, or session-refresh cost.
- Not relevant layers:
  - Mock UI: Visible panel outcomes are owned by the switcher-standard-panel scenario.
  - Real-topology UI: The deterministic session model does not depend on external window topology.
  - Process/Tooling: No dedicated runner or fixture contract belongs to this product rule.
- Current representative test anchors:
  - Unit: `SwitcherSessionEdgeTests.testCommitInWindowCycleReturnsWindowAndStoresRememberedWindowID`
  - Behavior: `FlowTabPriorityCoverageTests.testAppDelegateReloadedHotkeyMonitorRoutesCallbacksToSwitcherSession`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:core-grouping-switcher-session`.

### `scenario:global-hotkey-monitor-lifecycle` — Global hotkey monitor lifecycle

- Requiredness: required
- Owner: `App`
- Oracle: Configured global monitors register, route press/release callbacks, recover registration failures, and unregister on stop.
- Risk: `app-orchestration`, `real-topology-external-system`
- Required layers:
  - Behavior: Own Carbon registration, event routing, failure recovery, and unregister-on-stop lifecycle.
- Conditional layers:
  - Real-topology UI: Required when system event delivery or a user-visible global-shortcut route changes.
- Not relevant layers:
  - Unit: Shortcut normalization is owned by the hotkey-configuration scenario; monitor lifecycle is adapter orchestration.
  - Mock UI: Settings control persistence does not prove Carbon monitor lifecycle.
  - Pressure: Registration and teardown are bounded lifecycle events rather than sustained work.
  - Process/Tooling: No dedicated runner or fixture contract belongs to monitor lifecycle.
- Current representative test anchors:
  - Behavior: `FlowTabPriorityCoverageTests.testOptionTabHotkeyMonitorStopUnregistersOnlySuccessfullyRegisteredHotkeys`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:global-hotkey-monitor-lifecycle`.

### `scenario:home-app-window-list` — Home app and window list

- Requiredness: required
- Owner: `Home`
- Oracle: The current runtime projection drives exact Home counts, per-app windows, ordering, and exact-window activation. Each FlowTab process starts with an empty application MRU and rebuilds it from the current Dock/Command-Tab front-to-back order, normalized by canonical app identity. During that process lifetime, Home and every freshly opened app switcher expose the same application order while the external application order is unchanged.
- Risk: `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system`, `hot-path-scale-sensitive`
- Required layers:
  - Unit: Own counts, filtering, recency, hidden-last presentation, exact activation target rules, system-order bridge availability, process-session initialization, legacy-state cleanup, canonical app-MRU bootstrap, reconciliation, and lifecycle transitions.
  - Behavior: Prove Home reads runtime projections and requests repair without a surface snapshot bridge, each tracker starts fresh, system order replaces the current session's bootstrap fallback, unchanged fallback samples preserve canonical app order, and focused current-app window repair preserves the existing global application rank.
  - Mock UI: Prove visible counts, app selection, filtering, window rows, and cross-surface app order with deterministic runtime data.
  - Real-topology UI: Prove per-app real windows, recency, exact-window activation, and process-scoped MRU rebuilding with eight controlled applications that already exist before FlowTab starts; establish a different external order before the second FlowTab process and verify ten repeated fresh switcher sessions remain stable.
- Conditional layers:
  - Pressure: Required when Home projection refresh, app-rank sampling, inventory, or window-list cost changes with scale or cadence.
- Not relevant layers:
  - Process/Tooling: Real-topology fixture mechanics are owned by the space-fixture-infrastructure scenario.
- Current representative test anchors:
  - Unit: `FlowTabPriorityCoverageTests.testRuntimeWindowRecencyTrackerAppliesSameOrderingToCurrentAppPayload`, `FlowTabPriorityCoverageTests.testRuntimeSystemAppOrderProviderResolvesRegularRunningApplications`, `FlowTabPriorityCoverageTests.testSystemAppMRUStateNewSessionUsesSystemOrderAsItsInitialOrder`, `FlowTabPriorityCoverageTests.testSystemAppMRULegacyPersistenceRemovesPreviousProcessState`, `FlowTabPriorityCoverageTests.testRuntimeProjectionRepairFactSourceBuildsFocusedCurrentAppWindowFactsFromWindowRecordStore`
  - Behavior: `FlowTabTests.testHomeRuntimeProjectionReaderUsesRuntimeProjectionsWithoutSnapshotBridge`, `FlowTabTests.testHomeRuntimeRefreshReaderAdoptsLatestRuntimeProjectionOrder`, `FlowTabPriorityCoverageTests.testSystemAppMRUTrackerStartsFreshForEachProcessSession`, `FlowTabPriorityCoverageTests.testSystemAppMRUStateSystemOrderReplacesSessionBootstrapFallbackOrder`, `FlowTabPriorityCoverageTests.testSystemAppMRUTrackerKeepsKnownOrderWhenFallbackSampleChanges`, `FlowTabPriorityCoverageTests.testRuntimeReadModelStoreCurrentAppRepairEvidencePreservesExistingActivationRank`
  - Mock UI: `FlowTabUITests.testHomeAppLayerMarksHiddenAppsAndSortsThemLast`, `FlowTabUITests.testHomeAndFreshOptionTabUseSameRuntimeAppOrder`
  - Real-topology UI: `FlowTabUITests.testHomePageClickingRealWorkflowWindowActivatesExactFixtureWindow`, `FlowTabUITests.testSystemAppMRURebuildsForEveryFlowTabProcessSession`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:home-app-window-list`.

### `scenario:hotkey-configuration-normalization` — Hotkey configuration normalization

- Requiredness: required
- Owner: `Preferences`
- Oracle: Stored and requested shortcuts normalize to supported, conflict-free Carbon bindings and deterministic fallbacks.
- Risk: `deterministic-rule`, `app-orchestration`, `visible-workflow`
- Required layers:
  - Unit: Own stored-value normalization, supported keys, conflicts, Carbon fields, and fallbacks.
  - Behavior: Prove normalized configurations reload into the active monitor graph.
  - Mock UI: Prove representative Settings choices trigger the configured user path.
- Not relevant layers:
  - Real-topology UI: Shortcut normalization does not require external app-window topology.
  - Pressure: Configuration changes do not add repeated hot-path work.
  - Process/Tooling: No dedicated runner or fixture contract belongs to shortcut normalization.
- Current representative test anchors:
  - Unit: `FlowTabTests.testHotkeyConfigurationDerivedFieldsAreConsistent`
  - Behavior: `FlowTabPriorityCoverageTests.testAppDelegateHotkeyObserverUsesPostedConfigurationsImmediately`
  - Mock UI: `FlowTabUITests.testSettingsMainHotkeyRepresentativeMatrixTriggersSwitcher`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:hotkey-configuration-normalization`.

### `scenario:in-app-window-hotkey` — In-app window hotkey

- Requiredness: required
- Owner: `Switcher`
- Oracle: One physical focused-app shortcut gesture opens a window-only session, advances exactly once to the next eligible sibling, presents its preview, and commits that exact window on modifier release.
- Risk: `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system`, `hot-path-scale-sensitive`
- Required layers:
  - Unit: Own focused-window shortcut normalization and conflict fallback.
  - Behavior: Prove focused-app projection startup, navigation, and release-to-commit orchestration.
  - Mock UI: Prove explicit and fallback Settings choices open a focused-window session.
  - Real-topology UI: Prove the focused app's fullscreen and off-Space sibling windows round-trip through the visible panel.
  - Pressure: Protect focused-projection startup from synchronous snapshot work.
- Not relevant layers:
  - Process/Tooling: The canonical UI and pressure runners are shared infrastructure rather than scenario-owned tooling.
- Current representative test anchors:
  - Unit: `FlowTabTests.testInAppWindowHotkeyResolveAvoidingMainConflictFallsBackToNonConflictingModifier`
  - Behavior: `FlowTabPriorityCoverageTests.testInAppHotkeyFirstPhysicalPressAdvancesToNextWindow`, `FlowTabPriorityCoverageTests.testLiveSwitcherModelFocusedWindowSessionUsesRuntimeProjectionWithoutFocusedSampling`
  - Mock UI: `FlowTabUITests.testControlTabFirstPhysicalGestureSelectsNextWindowWithVisiblePreview`, `FlowTabUITests.testSettingsInAppHotkeyExplicitAndFallbackMatrixStartsFocusedWindowSession`
  - Real-topology UI: `FlowTabUITests.testInAppWindowSwitcherControlTabRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows`
  - Pressure: `FlowTabTests.testControlTabFocusedProjectionFastStartPressureIgnoresFocusedSnapshotBridge`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:in-app-window-hotkey`.

### `scenario:logs-diagnostics` — Logs and diagnostics

- Requiredness: required
- Owner: `Logs`
- Oracle: Runtime log writes, level filtering, incremental reads, seeded presentation, and clear operations match the diagnostics contract.
- Risk: `deterministic-rule`, `app-orchestration`, `visible-workflow`
- Required layers:
  - Unit: Own deterministic diagnostic field selection and formatting.
  - Behavior: Prove runtime writes, incremental reads, filtering, and clear behavior.
  - Mock UI: Prove seeded logs, level selection, visibility, and clear actions.
- Not relevant layers:
  - Real-topology UI: Diagnostics presentation does not require external window topology.
  - Pressure: Logging pressure is required only when log volume, cadence, or retention cost changes; it is not a standing scenario layer.
  - Process/Tooling: No dedicated runner or fixture contract belongs to diagnostics presentation.
- Current representative test anchors:
  - Unit: `FlowTabPriorityCoverageTests.testRuntimeProjectionDiagnosticsTimingLineUsesProjectionBoundaryFields`
  - Behavior: `FlowTabPriorityCoverageTests.testRuntimeLogIntegrationFiltersDeltasAndClearsEntries`
  - Mock UI: `FlowTabUITests.testLogsPageShowsSeededLogsAndClearRemovesOutput`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:logs-diagnostics`.

### `scenario:performance-pressure-gates` — Performance and pressure gates

- Requiredness: conditional: required whenever hot-path or scale-sensitive risk applies
- Owner: `Performance`
- Oracle: Required runners complete with intact samples and status, pass scenario assertions, and show no unexplained sustained CPU or warm-state RSS regression.
- Risk: `hot-path-scale-sensitive`, `tooling-fixture`
- Required layers:
  - Pressure: Prove the selected workload completes with intact samples/status and no unexplained sustained CPU or warm-state RSS regression.
  - Process/Tooling: Prove pressure entry-point syntax, arguments, identities, clocks, artifacts, and summaries.
- Conditional layers:
  - Behavior: Required when the selected pressure workload is an in-process orchestration scenario.
  - Mock UI: Required when the selected hot path is visible UI without external topology.
  - Real-topology UI: Required when the selected risk depends on real apps, Spaces, permissions, or cross-process lifecycle.
- Not relevant layers:
  - Unit: Deterministic rule correctness remains owned by the product scenario that triggered pressure validation.
- Current representative test anchors:
  - Pressure: `FlowTabTests.testOptionTabFastStartPressureStaysUnderHundredMilliseconds`, `FlowTabTests.testSearchPerformanceWindowScope`, `FlowTabPriorityCoverageTests.testRuntimeAXAppCollectionCoordinatorPressureUsesBoundedConcurrencyAndKeepsOrder`
- Current Process/Tooling entry points: `scripts/perf/tab-switch-stress.sh`, `scripts/perf/search-committed-index-pressure.sh`, `scripts/perf/runtime-topology-pressure.sh`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:performance-pressure-gates`.

### `scenario:runtime-activation-recovery` — Runtime activation and recovery

- Requiredness: required
- Owner: `Runtime`
- Oracle: Activation preserves exact target identity, verifies the post-attempt result, and applies bounded recovery when evidence disagrees.
- Risk: `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system`, `hot-path-scale-sensitive`
- Required layers:
  - Unit: Own target-route classification, fallback eligibility, and readback-verification rules.
  - Behavior: Prove exact target activation, minimized restore, fallback, retry, and mismatch handling.
  - Mock UI: Prove the visible panel commits selected app and window targets.
  - Real-topology UI: Prove real exact-window activation or an explicit unverified readback rejection.
- Conditional layers:
  - Pressure: Required when retry cadence, activation polling, or recovery task lifetime changes.
- Not relevant layers:
  - Process/Tooling: Shared real-topology runner validity is owned by performance-pressure-gates.
- Current representative test anchors:
  - Unit: `FlowTabPriorityCoverageTests.testRuntimeWindowTopologyClassifierClassifiesActivationSurfaces`
  - Behavior: `FlowTabPriorityCoverageTests.testRuntimeActivatorDoesNotVerifyCGRouteWhileTargetRemainsOffscreen`
  - Mock UI: `FlowTabUITests.testSearchPanelEntryAndResultActivation`
  - Real-topology UI: `FlowTabUITests.testSwitcherPanelOptionTabReportsUnverifiedSpaceBackedCGOnlyWorkflowActivation`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:runtime-activation-recovery`.

### `scenario:runtime-snapshot-window-records` — Runtime snapshot, AX/CG mapping, and window records

- Requiredness: required
- Owner: `Runtime`
- Oracle: AX, CG, app-directory, and topology evidence reconcile into stable window identities and complete current projections.
- Risk: `deterministic-rule`, `app-orchestration`, `real-topology-external-system`, `hot-path-scale-sensitive`
- Required layers:
  - Unit: Own WindowRecord identity, AX/CG matching, topology classification, and projection assembly rules.
  - Behavior: Prove runtime fact collection, repair, main-table commit, notification publication, and consumer reads.
  - Real-topology UI: Prove real fullscreen/off-Space AX/CG evidence produces the intended visible window identities.
  - Pressure: Protect bounded AX collection and scale-sensitive projection work.
- Not relevant layers:
  - Mock UI: Mock UI can consume projections but cannot prove AX/CG/Space truth.
  - Process/Tooling: Runtime source-audit guards supplement validation but do not replace runtime-layer evidence.
- Current representative test anchors:
  - Unit: `FlowTabPriorityCoverageTests.testRuntimeWindowRecordKnownCGWindowsCombinesLiveFactsWithSynthesizedRecordEvidence`
  - Behavior: `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceCommitsAppDirectoryProviderProjectionFromMainTablesAsStaleWithFullRepairFallback`, `FlowTabPriorityCoverageTests.testSwitcherRuntimeProjectionNotificationsPublishWhileMainActorIsUnavailable`
  - Real-topology UI: `FlowTabUITests.testSwitcherPanelOptionTabWindowStateRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows`
  - Pressure: `FlowTabPriorityCoverageTests.testRuntimeAXAppCollectionCoordinatorPressureUsesBoundedConcurrencyAndKeepsOrder`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:runtime-snapshot-window-records`.

### `scenario:search-result-activation` — Search panel and result activation

- Requiredness: required
- Owner: `Switcher`
- Oracle: The committed search index applies query semantics and ranking, and commit activates the exact selected app or window.
- Risk: `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system`, `hot-path-scale-sensitive`
- Required layers:
  - Unit: Own normalization, tokenization, matching, ranking, cursor editing, and target mapping.
  - Behavior: Prove committed-index readiness, search state, selection, and exact activation request orchestration.
  - Mock UI: Prove users can enter Search, select a result, and commit it through the panel.
  - Real-topology UI: Prove committed Search finds and activates real normal and fullscreen fixture windows.
  - Pressure: Protect committed-index query throughput, workload breadth, CPU, and RSS.
- Not relevant layers:
  - Process/Tooling: Search pressure runner contracts are owned by performance-pressure-gates.
- Current representative test anchors:
  - Unit: `SearchTextMatcherTests.testSearchTextMatcherMatchesChinesePinyinSpellingAndInitials`
  - Behavior: `FlowTabPriorityCoverageTests.testRuntimeProjectionServiceCommitsSearchIndexFromMainTableProjectionOnlyAfterBarrier`, `FlowTabPriorityCoverageTests.testLiveSwitcherModelStartSessionLoadsProjectionAndCommitActivatesPreferredTarget`
  - Mock UI: `FlowTabUITests.testSearchPanelEntryAndResultActivation`
  - Real-topology UI: `FlowTabUITests.testSwitcherPanelWindowSearchActivatesFullscreenWorkflowWindowAcrossSpaces`
  - Pressure: `FlowTabTests.testSearchPressureWindowScopeQueryWorkloadMatrix`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:search-result-activation`.

### `scenario:settings-app-visibility` — Settings: app visibility exclusions

- Requiredness: required
- Owner: `Settings`
- Oracle: Normalized hidden app identities remain manageable and are excluded from Home, switcher, and search output.
- Risk: `deterministic-rule`, `app-orchestration`, `visible-workflow`, `hot-path-scale-sensitive`
- Required layers:
  - Unit: Own hidden-ID normalization, search, stored-missing IDs, filtering, and presentation rank.
  - Behavior: Prove hidden IDs are removed from switcher and Search orchestration.
  - Mock UI: Prove users can hide an app and observe its absence in switcher and Search.
- Conditional layers:
  - Pressure: Required when inventory filtering or hidden-app matching changes repeated app/search work.
- Not relevant layers:
  - Real-topology UI: The hidden-ID contract is independent of real Space topology.
  - Process/Tooling: No dedicated runner or fixture contract belongs to app visibility.
- Current representative test anchors:
  - Unit: `FlowTabTests.testAppVisibilityManagerShowsStoredHiddenAppIDsMissingFromInventory`
  - Behavior: `FlowTabTests.testHiddenAppIDsFilterSwitcherAppLayerAndSearchIndex`
  - Mock UI: `FlowTabUITests.testSettingsAppVisibilityHidesMockAppFromSwitcherAndSearch`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:settings-app-visibility`.

### `scenario:settings-appearance` — Settings: appearance

- Requiredness: required
- Owner: `Settings`
- Oracle: Persisted theme and language resolve to the expected localized, visible presentation under explicit and follow-system modes.
- Risk: `deterministic-rule`, `app-orchestration`, `visible-workflow`
- Required layers:
  - Unit: Own theme, language, follow-system, localization, and control-presentation rules.
  - Behavior: Prove presentation state propagates follow-system theme changes without writing theme or language preferences.
  - Mock UI: Prove theme and language changes update the visible Settings surface.
- Not relevant layers:
  - Real-topology UI: Appearance does not depend on external app-window topology.
  - Pressure: Theme and language changes are bounded preference events.
  - Process/Tooling: No dedicated runner or fixture contract belongs to appearance.
- Current representative test anchors:
  - Unit: `FlowTabTests.testSystemThemeStateMatchesCurrentSystemAppearanceWhenAppDefaultsContainAppleInterfaceStyle`
  - Behavior: `FlowTabTests.testFlowPresentationStateFollowSystemRespondsToSystemThemeWithoutWritingRawThemeOrLanguageNotification`
  - Mock UI: `FlowTabUITests.testSettingsAppearanceThemeAndLanguageUpdateVisibleUI`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:settings-appearance`.

### `scenario:settings-layout-control-chrome` — Settings: page layout and control chrome

- Requiredness: required
- Owner: `Settings`
- Oracle: Settings controls and cards obey their documented geometry, intrinsic sizing, placement, theme, and localization contracts.
- Risk: `deterministic-rule`, `app-orchestration`, `visible-workflow`
- Required layers:
  - Unit: Own geometry, intrinsic sizing, dropdown placement, theme, and localization layout rules.
  - Behavior: Prove shared Settings controls wire user selections into their bindings.
  - Mock UI: Prove representative controls remain visible and usable through XCUI.
- Conditional layers:
  - Pressure: Required when a change adds repeated layout work or scales with rows, cards, or menu items.
- Not relevant layers:
  - Real-topology UI: Settings geometry does not depend on external window topology.
  - Process/Tooling: No scenario-specific runner or fixture contract belongs to Settings layout.
- Current representative test anchors:
  - Unit: `FlowTabTests.testSettingsPageNarrowLayoutUsesSingleColumnAndFlexibleControlWidths`
  - Behavior: `FlowTabTests.testRuntimeLogsDropdownUpdatesRuntimeLogLevelBinding`
  - Mock UI: `FlowTabUITests.testSettingsHotkeyKeyDropdownOpensAsRightSideMenuWhenSpaceAllows`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:settings-layout-control-chrome`.

### `scenario:settings-permission-controls` — Settings: permission controls

- Requiredness: required
- Owner: `Settings`
- Oracle: Permission and launch-at-login UI reflects the injected or system-owned state and exposes the app-owned recovery entry point.
- Risk: `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system`
- Required layers:
  - Unit: Own permission copy, injected-state resolution, launch overrides, and launch-at-login state.
  - Behavior: Prove launch prompt gating and permission-dependent app orchestration.
  - Mock UI: Prove permission banners, routing, control enablement, and recovery entry points.
- Conditional layers:
  - Real-topology UI: Required when app-owned behavior depends on a real permission grant, denial, or system prompt transition.
- Not relevant layers:
  - Pressure: Permission state transitions are lifecycle events rather than sustained repeated work.
  - Process/Tooling: Signing and permission setup are shared UI-runner prerequisites, not this product scenario's stable outcome.
- Current representative test anchors:
  - Unit: `FlowTabTests.testPermissionSettingsCardStateUsesDeniedCopyWhenPermissionsMissing`
  - Behavior: `FlowTabPriorityCoverageTests.testAppDelegateLaunchSkipsAccessibilityPromptWhenAlreadyPromptedOrReminderDisabled`, `FlowTabPriorityCoverageTests.testAppDelegateLaunchEnablesLoginItemWhenPreferenceAllowsIt`
  - Mock UI: `FlowTabUITests.testHomePermissionBannerHiddenWhenPermissionsGranted`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:settings-permission-controls`.

### `scenario:settings-search` — Settings: search

- Requiredness: required
- Owner: `Settings`
- Oracle: Search enablement and default scope persist, respect Accessibility availability, and route the next visible search session.
- Risk: `deterministic-rule`, `app-orchestration`, `visible-workflow`, `hot-path-scale-sensitive`
- Required layers:
  - Unit: Own enablement, scope normalization, and Accessibility-dependent effective defaults.
  - Behavior: Prove panel orchestration routes scope changes against the committed-index flow.
  - Mock UI: Prove default scope persists and changes visible app/window results.
  - Pressure: Protect committed-index Search from synchronous runtime sampling and scale regression.
- Not relevant layers:
  - Real-topology UI: Real-window Search activation is owned by the search-result-activation scenario.
  - Process/Tooling: Search runner contracts are owned by the performance-pressure-gates scenario.
- Current representative test anchors:
  - Unit: `FlowTabTests.testSearchInteractionEffectiveDefaultScopeRequiresAccessibilityForWindowScope`
  - Behavior: `FlowTabPriorityCoverageTests.testSwitcherPanelControllerSearchTabTogglesScope`, `FlowTabTests.testLiveSwitcherModelSearchReadsCommittedRuntimeIndexInsteadOfSessionApps`
  - Mock UI: `FlowTabUITests.testSettingsSearchDefaultScopePersistsAndShowsWindowThenAppResults`
  - Pressure: `FlowTabTests.testLiveSwitcherModelSearchPressureReadsCommittedGenerationValidatedIndexWithoutSampling`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:settings-search`.

### `scenario:settings-window-behavior` — Settings: window behavior

- Requiredness: required
- Owner: `Settings`
- Oracle: Persisted window-behavior choices deterministically alter switcher delay, filtering, restoration, preview readiness, and visible output; each delayed transition applies only its current timer generation.
- Risk: `deterministic-rule`, `app-orchestration`, `visible-workflow`, `hot-path-scale-sensitive`
- Required layers:
  - Unit: Own delay normalization, filtering, restoration, and preference defaults.
  - Behavior: Prove panel orchestration applies persisted delay and window-behavior choices.
  - Mock UI: Prove persisted settings alter the visible switcher output.
- Conditional layers:
  - Pressure: Required when switcher timing, filtering cost, or repeated projection work changes.
- Not relevant layers:
  - Real-topology UI: The representative preference effect is deterministic with the UI runtime dataset.
  - Process/Tooling: No scenario-specific runner or fixture contract belongs to these preferences.
- Current representative test anchors:
  - Unit: `FlowTabTests.testWindowLayerNormalizedAutoEnterDelayClampsAndRounds`
  - Behavior: `FlowTabPriorityCoverageTests.testSwitcherPanelControllerDelayedAutoEnterWindowLayerUsesPreferenceDelay`, `FlowTabPriorityCoverageTests.testDelayedWindowLayerEntryPrewarmsBoundedVisiblePage`, `FlowTabPriorityCoverageTests.testDelayedWindowLayerEntryIgnoresStaleTimerGeneration`
  - Mock UI: `FlowTabUITests.testOptionTabDelayedWindowLayerEntryShowsPrewarmedPreviewAtTransition`, `FlowTabUITests.testSettingsWindowBehaviorHideMinimizedAppsAffectsSwitcherAppLayer`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:settings-window-behavior`.

### `scenario:space-fixture-infrastructure` — Space fixture workflow infrastructure

- Requiredness: conditional: required whenever real-topology UI evidence is selected
- Owner: `Testing Infrastructure`
- Oracle: Workflow configuration builds the declared app/window topology and exposes stable launch, mutation, and cleanup identities.
- Risk: `deterministic-rule`, `real-topology-external-system`, `tooling-fixture`
- Required layers:
  - Unit: Own workflow configuration parsing, deterministic IDs, window plans, and mutation timing.
  - Real-topology UI: Prove the built fixture exposes declared app, window, fullscreen, mutation, and cleanup identities.
  - Process/Tooling: Prove fixture build/install/workflow paths and resolved configuration remain valid.
- Not relevant layers:
  - Behavior: Fixture planning is deterministic below process launch; cross-process truth is proven by real-topology UI.
  - Mock UI: Mock UI cannot prove the external fixture topology.
  - Pressure: Fixture construction is evidence infrastructure, not a sustained product workload.
- Current representative test anchors:
  - Unit: `FlowTabTests.testSpaceFixtureLaunchConfigurationParsesTerminationAndWindowCloseDelays`
  - Real-topology UI: `FlowTabUITests.testSpaceFixtureAppLoadsWorkflowConfiguredTabbedWindows`
- Current Process/Tooling entry points: `scripts/testing/build-space-fixture-app.sh`, `scripts/testing/build-space-fixture-workflow.sh`, `scripts/testing/run-ui-tests-local.sh`, `docs/fixtures/space-fixture-home-multi-app-workflow.json`, `docs/fixtures/space-fixture-system-app-mru-workflow.json`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:space-fixture-infrastructure`.

### `scenario:switcher-standard-panel` — Switcher standard panel flow

- Requiredness: required
- Owner: `Switcher`
- Oracle: Opening, navigating, previewing, and committing the panel preserves session identity, uses responsive content bounds, and keeps the presented content visible through selected-target activation.
- Risk: `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system`, `hot-path-scale-sensitive`
- Required layers:
  - Unit: Own navigation, commit, paging, and pointer-selection rules.
  - Behavior: Prove projection publication, panel routing, refresh, interruption, and commit orchestration.
  - Mock UI: Prove opening, navigation, pointer selection, click commit, and close behavior.
  - Real-topology UI: Prove fullscreen/off-Space app-window ordering and activation through real fixture topology, plus process-scoped app-MRU rebuilding and stable repeated switcher sessions with eight applications that already exist before FlowTab starts.
  - Pressure: Protect fast start, large window sets, preview capture, repeated switching, and cancellation.
- Not relevant layers:
  - Process/Tooling: Shared UI and pressure runners are governed by performance-pressure-gates.
- Current representative test anchors:
  - Unit: `SwitcherSessionEdgeTests.testCommitInWindowCycleReturnsWindowAndStoresRememberedWindowID`
  - Behavior: `FlowTabPriorityCoverageTests.testSwitcherPanelControllerGlobalHotkeyStartsFromAppSwitcherProjection`, `FlowTabPriorityCoverageTests.testSwitcherPanelRemainsPresentedDuringCommittedWindowActivation`, `FlowTabPriorityCoverageTests.testWindowOnlyPanelUsesResponsiveContentBounds`
  - Mock UI: `FlowTabUITests.testOptionTabDelayedWindowLayerEntryShowsPrewarmedPreviewAtTransition`, `FlowTabUITests.testOptionTabSwitcherClickCommitsAppAndClosesPanel`, `FlowTabUITests.testHomeAndFreshOptionTabUseSameRuntimeAppOrder`
  - Real-topology UI: `FlowTabUITests.testSwitcherPanelOptionTabWindowStateRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows`, `FlowTabUITests.testSystemAppMRURebuildsForEveryFlowTabProcessSession`
  - Pressure: `FlowTabPriorityCoverageTests.testSwitcherInitialVisibilityRecoveryRapidOpenClosePressureDoesNotReplayStaleTasks`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:switcher-standard-panel`.

### `scenario:terminate-selected-app` — Terminate selected app

- Requiredness: required
- Owner: `Switcher`
- Oracle: Termination targets the selected application and refreshes the open session without corrupting selection state.
- Risk: `app-orchestration`, `visible-workflow`, `real-topology-external-system`
- Required layers:
  - Behavior: Prove quit requests retain selection until workspace termination evidence refreshes the session.
  - Mock UI: Prove explicit and fallback quit shortcuts invoke the selected-app flow.
  - Real-topology UI: Prove a real fixture app remains visible until its process actually terminates.
- Not relevant layers:
  - Unit: Selected-target termination is app orchestration without a standalone deterministic product rule.
  - Pressure: Termination is a bounded lifecycle event without sustained workload cost.
  - Process/Tooling: Fixture lifecycle mechanics are owned by space-fixture-infrastructure.
- Current representative test anchors:
  - Behavior: `FlowTabPriorityCoverageTests.testSwitcherPanelControllerQuitFrontmostAppInAppLayerKeepsSessionAfterWorkspaceTerminationRefresh`
  - Mock UI: `FlowTabUITests.testSettingsQuitHotkeyExplicitAndFallbackMatrixTerminatesSelectedApp`
  - Real-topology UI: `FlowTabUITests.testSwitcherPanelQuitShortcutKeepsRealFixtureAppUntilProcessTerminates`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:terminate-selected-app`.

### `scenario:window-previews-icons` — Window previews and icons

- Requiredness: required
- Owner: `Runtime`
- Oracle: Preview and icon providers preserve target identity, cache lifecycle, paging, fallback, and cancellation semantics while visible cards remain continuous across capture and same-session projection refreshes.
- Risk: `deterministic-rule`, `app-orchestration`, `visible-workflow`, `real-topology-external-system`, `hot-path-scale-sensitive`
- Required layers:
  - Unit: Own sizing, paging, cache, renderer, icon, provider selection, and identity rules.
  - Behavior: Prove provider routing, batched publication, cache lifetime, fallback, and cancellation.
  - Mock UI: Prove visible pagination and screenshot presence for a large deterministic window set.
  - Real-topology UI: Prove real workflow cards preserve app/window identity and duplicate-window separation.
  - Pressure: Protect current-page-only preview capture and bounded provider work at scale.
- Not relevant layers:
  - Process/Tooling: Preview evidence uses shared app and UI runners without a scenario-specific command contract.
- Current representative test anchors:
  - Unit: `FlowTabPriorityCoverageTests.testWindowPreviewPagingUsesResolutionDependentPageSize`, `FlowTabPriorityCoverageTests.testWindowOnlyPanelSizingUsesResponsiveScreenBounds`
  - Behavior: `FlowTabPriorityCoverageTests.testLiveSwitcherModelRuntimeVisiblePreviewShowsFallbackWhileBatchIsInFlight`, `FlowTabPriorityCoverageTests.testProjectionRefreshKeepsVisiblePreviewImagesInCurrentSession`
  - Mock UI: `FlowTabUITests.testControlTabFirstPhysicalGestureSelectsNextWindowWithVisiblePreview`, `FlowTabUITests.testOptionTabDelayedWindowLayerEntryShowsPrewarmedPreviewAtTransition`, `FlowTabUITests.testSwitcherWindowLayerPaginatesLargeMockWindowSet`
  - Real-topology UI: `FlowTabUITests.testSwitcherPanelPreviewKeepsIdenticalRealWorkflowWindowsDistinct`
  - Pressure: `FlowTabTests.testOptionTabWindowScalePressureKeepsSelectedAppApplyAndPreviewCaptureBounded`
- Exhaustive mapping: query active ledger rows whose `product_scenario_ids` contains `scenario:window-previews-icons`.

## Update rules

Update this contract when a scenario is added, removed, renamed, merged, retired, or changes Oracle, requiredness, Owner, layer responsibility, or risk classification. Update representative anchors when a named method is retired or stops proving its declared layer. Refresh the exhaustive ledger whenever executable assets, membership, runners, fixtures, TestingSupport, dependencies, consumers, or source fingerprints change.

Publish current validation status through the owning engineering handoff. During a test-audit campaign, publish current scenario-layer evidence through the selected stage handoff and `docs/test-audit/COVERAGE_EVIDENCE_PROJECTION.jsonl` when that projection is required.
