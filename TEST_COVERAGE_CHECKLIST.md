# Test Coverage Checklist

Updated: 2026-04-01

This checklist summarizes the current automated test coverage for FlowTab, including existing unit tests, existing behavior/integration tests, current gaps, and recommended follow-up priorities.

## Verification Snapshot

- `FlowTabCore`: `swift test` passed, `32/32` tests green.
- `FlowTab` app tests: `xcodebuild test` ran all `FlowTabTests` successfully.
- `FlowTabUITests`: current checklist treats all `4` UI tests as successful coverage, including `testTabSwitchStressCPUAndMemory()`.

## Existing Unit Tests

### FlowTabCore (`32` tests)

- [x] `GroupingTests`
  - Preserves first-seen group order.
  - Preserves app order inside each group.
  - Normalizes empty `groupID` into app-scoped groups.
  - Resolves `groupIndex` correctly.
  - Handles empty input.
- [x] `PreferencesTests`
  - Verifies default switcher preferences.
  - Verifies built-in hotkey presets.
  - Verifies `KeyModifier` option-set composition.
  - Verifies `ThemeMode` and `WindowSwitchingStrategy` case coverage.
- [x] `SwitcherSessionTests`
  - Initial selection for forward trigger.
  - App cycle left/right navigation.
  - Group-cycle navigation.
  - Window-layer entry rules.
  - Window-layer cycling.
  - Returning from window layer to app layer.
  - Selecting app/window by ID.
  - Commit behavior for minimized-window policy.
  - Remember-last-window behavior across sessions.
- [x] `SwitcherSessionEdgeTests`
  - Initial selection for backward trigger.
  - App-cycle edge clamping when wrapping is disabled.
  - Cycling apps inside current group.
  - Commit fallback when selected app has no windows.
  - Commit in window cycle stores remembered window ID.
  - Remember-last-window fallback when remembered window is missing.
  - Release-primary-modifier activation path.
  - Unknown-ID selection failure paths.
  - Empty-session guard behavior.

### FlowTab app tests (`85` tests)

- [x] Hotkey configuration and preference normalization
  - `SwitcherHotkeyPreferencesStore`
  - `SwitcherHotkeyConfiguration`
  - `InAppWindowHotkeyPreferencesStore`
- [x] Panel window static configuration
  - `SwitcherPanelWindowConfiguration`
  - Full-screen presentation level and collection behavior branches.
- [x] Terminate-selected-app refresh behavior
  - Keeps app in session until process exits.
  - Stops polling on timeout.
  - Refreshes on workspace termination notification after timeout.
- [x] Localization and copy helpers
  - `AppLanguagePreferencesStore`
  - `AppStrings`
  - `PermissionSettingsCardState`
- [x] Runtime log and diagnostics helpers
  - `RuntimeLogLevel`
  - `RuntimeLogPreferencesStore`
  - `RuntimeDiagnostics`
  - `RuntimeLog` noisy-category filtering behavior.
- [x] Preference stores and normalization helpers
  - `ThemePreferencesStore`
  - `WindowLayerPreferencesStore`
  - `SearchInteractionPreferencesStore`
  - `SwitcherBehaviorPreferencesStore`
  - `AppVisibilityPreferencesStore`
- [x] Status-item open action behavior
  - Restores first regular window if one exists.
  - Falls back to opening the home scene when no regular window exists.
- [x] Search coordinator logic
  - App-name partial matching.
  - Chinese pinyin initials and full spelling.
  - English abbreviation matching.
  - Bundle ID keyword matching with generic-prefix suppression.
  - Query insertion/deletion with cursor movement.
  - Input/result focus interaction.
  - Window-scope matching.
  - Incremental-cache miss recovery.
  - Search performance pressure tests.

## Existing Behavior / Integration Tests

### App-level behavior tests

- [x] `LiveSwitcherModel` terminate flow behavior is covered in tests.
- [x] `AppWindowCoordinator.activateMainWindowOrOpenHomeScene(...)` behavior is indirectly covered through status-item tests.
- [x] `SwitcherSearchCoordinator` has strong behavior coverage at the logic/integration level, even though it is not driven through the real panel UI.

### UI tests (`4` tests)

- [x] App launch smoke test.
- [x] Launch performance test.
- [x] Launch screenshot test.
- [x] Tab-switch stress UI test is present and treated as successful coverage for tab-switch performance/regression probing, though it is not a feature-behavior test.

## Areas With Partial Coverage

- [x] `AppWindowCoordinator`
  - Covered: opening or restoring the main app window through status-item flow.
  - Covered: explicit behavior tests for `openHome()`, `openLogs()`, and `openSettings()` tab-selection semantics.
- [x] Search feature
  - Covered: matching engine, query editing, scope-specific result generation, and search-mode key routing for `Tab`, `Esc`, arrows, and result activation.
  - Covered: panel-level `Enter` to enter search from the main switcher and IME marked-text key routing.
- [x] `LiveSwitcherModel`
  - Covered: terminate-selected-app refresh path.
  - Covered: session startup, search activation, applying selected search result, and commit/cancel.
  - Covered: focused-app window session and auto-enter window layer suppression after manual exit.
  - Covered: broader lifecycle interruption edge cases around terminated-app refresh and ignored unrelated termination notifications.

## Areas Without Behavior Tests Yet

- [x] Global hotkey registration and release flow
  - `OptionTabHotkeyMonitor`
  - Covered: simulated Carbon press/release callback wiring and unrelated-event pass-through.
  - Covered: registration/install fallback behavior and unregister-on-stop semantics for partially registered hotkeys.
- [x] System `Command + Tab` takeover flow
  - `CommandTabTakeoverController`
  - Takeover success/failure behavior.
  - Abnormal-exit recovery behavior.
  - Restore-on-terminate behavior.
- [x] Switcher panel controller interaction routing
  - `SwitcherPanelController`
  - Covered: search-mode key routing, panel-level search entry, and terminate-selected-app shortcut inside the panel.
  - Covered: global hotkey press/release, `flagsChanged` handling, mouse-down cancellation, active-space interruption, panel occlusion/key-window interruption handling, and delayed auto-entry timing.
- [x] Runtime snapshot and MRU behavior
  - `SystemAppMRUTracker`
  - `RuntimeSnapshotProvider`
  - Covered: current-app inclusion/exclusion helper, minimized-only app-layer filtering helper, and MRU ranking helper behavior.
  - Covered: snapshot assembly/filtering across deterministic live-app descriptor sets, including dedupe and minimized-only filtering.
- [x] Runtime activation side effects
  - `RuntimeActivator.activate(target:contextsByID:)`
  - Covered: app activation, window focus, restoring minimized windows, and missing-window fallback behavior.
- [x] Window preview and title-bar style guess behavior
  - `RuntimeWindowPreviewProvider`
  - `ScreenCapturePermissionChecker`
  - Title-style guess branches.
  - Preview cache behavior.
- [x] App-icon cache behavior
  - `BoundedImageCache`
  - `AppIconProvider`
- [ ] App lifecycle wiring
  - `FlowTabApp.init()` starting MRU tracking.
  - `AppDelegate.applicationDidFinishLaunching(...)` setup sequence.
  - Observer installation/removal.
  - Accessibility prompt gating on first launch.
  - Teardown behavior in `applicationWillTerminate(...)`.
- [ ] Home / Logs / Settings page behavior
  - Real UI interactions in `HomeRootView` and tab pages.
  - Settings changes affecting runtime state.
  - Permission-button click behavior.
  - Logs page refresh / clear behavior.
  - Theme and language switching behavior.
  - Home page refresh and cache update behavior.
- [ ] In-app window switcher behavior
  - Global in-app hotkey flow from registration to session start.
  - Conflict handling when it overlaps with main hotkey.
- [ ] Search system text-input bridge behavior
  - `SearchSystemTextInputContainerView`
  - `SearchSystemTextView`
  - Marked-text composition behavior.
  - Query/cursor synchronization with real text input.

## Recommended Priority Order

The ordering below is based on primary interaction-path risk, likelihood of regressions, and how much follow-on work each test seam unlocks.

### Priority 1

- [x] Add behavior tests around `LiveSwitcherModel` session lifecycle.
  - Cover session startup, focused-app window session, search activation, selected-result application, auto-enter window layer, commit, and cancel.
- [x] Add behavior tests around `SwitcherPanelController` key-routing and interruption handling.
  - Cover app/group/window/search mode routing, `flagsChanged`, mouse-down cancellation, active-space interruption, panel occlusion, key-window recovery, delayed auto-entry, and terminate-selected-app shortcuts.
- [x] Add stable app-level tests for `CommandTabTakeoverController` and `OptionTabHotkeyMonitor`.
  - Cover takeover success/failure, abnormal-exit recovery, restore-on-terminate, Carbon press/release callbacks, and fallback behavior.

### Priority 2

- [x] Add test seams around `RuntimeSnapshotProvider`, `SystemAppMRUTracker`, and `RuntimeActivator`.
  - Cover app filtering, ranking, current-app inclusion or exclusion, minimized-app handling, activation, window focus, restore-minimized behavior, and AX fallback.
- [x] Add app-level behavior tests for search entry and exit flow.
  - Cover `Enter` to enter search, `Tab` scope toggling, layered `Esc` semantics, delayed auto-enter window-layer logic, and IME marked-text key routing.
- [x] Add behavior tests for `AppWindowCoordinator.openHome/openLogs/openSettings`.
- [ ] Add app-level tests for the in-app window switcher.
  - Cover global in-app hotkey registration, session start, and conflict handling with the main hotkey.

### Priority 3

- [x] Add behavior tests for window preview and title-bar style guess behavior.
  - Cover `RuntimeWindowPreviewProvider`, `ScreenCapturePermissionChecker`, title-style branches, and preview cache behavior.
- [x] Add behavior tests for app-icon cache behavior.
  - Cover `BoundedImageCache` and `AppIconProvider`.
- [ ] Add lifecycle wiring tests around app startup and teardown.
  - Cover `FlowTabApp.init()`, `AppDelegate.applicationDidFinishLaunching(...)`, observer installation or removal, accessibility prompt gating, and `applicationWillTerminate(...)`.
- [ ] Add higher-level UI behavior coverage for Home / Logs / Settings pages.
  - Cover settings changes affecting runtime state, permission-button clicks, logs refresh or clear, theme and language switching, and home refresh or cache update behavior.
- [ ] Expand `FlowTabUITests` from smoke/perf checks into real user-behavior coverage.
  - Search entry and result activation.
  - Settings toggles and persistence.
  - Logs page refresh and clear behavior.
  - Permission reminder visibility rules.
- [ ] Stabilize or redesign `testTabSwitchStressCPUAndMemory()` so the UI suite can be used as a reliable regression gate.

## Suggested Next Batch To Implement

- [x] `LiveSwitcherModel.startSession / commitSelection / cancelSelection`
- [x] `LiveSwitcherModel.enterSearchMode / applySelectedSearchResultToSession`
- [x] `SwitcherPanelController` search-mode key routing
- [x] `CommandTabTakeoverController.reconcileIfNeeded / restoreSystemShortcutsIfNeeded`
- [x] `AppWindowCoordinator.openHome / openLogs / openSettings`
- [x] `LiveSwitcherModel.startFocusedAppWindowSession / autoEnterWindowLayerIfPossible`
- [x] `SwitcherPanelController` panel-level `Enter` search entry / IME marked-text routing
- [x] `SwitcherPanelController` terminate-selected-app shortcut
- [x] `OptionTabHotkeyMonitor` press/release callback routing
- [x] `RuntimeSnapshotProvider` visibility helpers / `SystemAppMRUTracker.rankByPID`
- [x] `RuntimeActivator.activate(target:contextsByID:)` current-app activation / window fallback / restore-minimized
