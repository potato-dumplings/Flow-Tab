import AppKit
import Carbon
import XCTest
@testable import FlowTab
import FlowTabCore

final class FlowTabPriorityCoverageTests: XCTestCase {
    @MainActor
    func testLiveSwitcherModelStartSessionLoadsSnapshotAndCommitActivatesPreferredTarget() {
        let model = LiveSwitcherModel()
        model.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.commitScenarioApps(), contextsByID: [:])
        }

        var activatedTarget: ActivationTarget?
        var activatedContexts: [String: RuntimeAppContext] = [:]
        model.activationOverride = { target, contextsByID in
            activatedTarget = target
            activatedContexts = contextsByID
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertEqual(model.appCount, 3)
        XCTAssertEqual(model.selectedApp?.id, "com.example.code")
        XCTAssertEqual(model.overlayStyle, .appAndWindow)

        model.commitSelection()

        XCTAssertNil(model.session)
        XCTAssertEqual(model.appCount, 0)
        XCTAssertFalse(model.isSearchActive)
        XCTAssertEqual(
            activatedTarget,
            .window(appID: "com.example.code", windowID: "code-1", restoreIfMinimized: false)
        )
        XCTAssertTrue(activatedContexts.isEmpty)
    }

    @MainActor
    func testLiveSwitcherModelCancelSelectionResetsSessionAndSearchState() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let model = LiveSwitcherModel()
            model.snapshotProviderOverride = {
                RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
            }

            XCTAssertTrue(model.startSession(triggerDirection: .forward))
            XCTAssertTrue(model.enterSearchMode())
            XCTAssertTrue(model.isSearchActive)
            XCTAssertEqual(model.searchScope, .app)

            model.cancelSelection()

            XCTAssertNil(model.session)
            XCTAssertEqual(model.appCount, 0)
            XCTAssertFalse(model.isSearchActive)
            XCTAssertEqual(model.searchViewState, .inactive)
            XCTAssertEqual(model.overlayStyle, .appAndWindow)
        }
    }

    @MainActor
    func testLiveSwitcherModelEnterSearchModeAndApplySelectedAppResult() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let model = LiveSwitcherModel()
            model.snapshotProviderOverride = {
                RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
            }

            XCTAssertTrue(model.startSession(triggerDirection: .forward))
            XCTAssertTrue(model.enterSearchMode())
            XCTAssertTrue(model.isSearchActive)
            XCTAssertEqual(model.searchScope, .app)
            XCTAssertGreaterThanOrEqual(model.searchResultCount, 3)

            XCTAssertTrue(model.moveSearchSelection(by: 1))
            XCTAssertEqual(
                model.searchViewState.selectedResult?.kind,
                .app(appID: "com.example.code")
            )

            XCTAssertTrue(model.applySelectedSearchResultToSession())

            XCTAssertFalse(model.isSearchActive)
            XCTAssertEqual(model.selectedApp?.id, "com.example.code")
            XCTAssertEqual(model.session?.mode, .appCycle)
        }
    }

    @MainActor
    func testLiveSwitcherModelApplySelectedWindowSearchResultEntersWindowCycle() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .window) {
            let model = LiveSwitcherModel()
            model.snapshotProviderOverride = {
                RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
            }

            XCTAssertTrue(model.startSession(triggerDirection: .forward))
            XCTAssertTrue(model.enterSearchMode())
            XCTAssertEqual(model.searchScope, .window)
            XCTAssertGreaterThanOrEqual(model.searchResultCount, 4)

            XCTAssertTrue(model.moveSearchSelection(by: 2))
            XCTAssertEqual(
                model.searchViewState.selectedResult?.kind,
                .window(appID: "com.example.code", windowID: "code-1")
            )

            XCTAssertTrue(model.applySelectedSearchResultToSession())

            XCTAssertFalse(model.isSearchActive)
            XCTAssertEqual(model.selectedApp?.id, "com.example.code")
            XCTAssertEqual(model.session?.mode, .windowCycle(appID: "com.example.code"))
            XCTAssertEqual(model.session?.selectedWindow?.id, "code-1")
        }
    }

    func testCommandTabTakeoverControllerReconcileActivatesAndRestoreReenablesSystemShortcuts() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        var calls: [(id: Int32, enabled: Bool)] = []
        let controller = CommandTabTakeoverController(
            userDefaults: userDefaults,
            symbolicHotKeySetterOverride: { id, enabled in
                calls.append((id: id, enabled: enabled))
                return noErr
            }
        )

        XCTAssertTrue(controller.reconcileIfNeeded(shouldTakeOver: true))
        XCTAssertEqual(calls.map(\.id), [1, 2])
        XCTAssertEqual(calls.map(\.enabled), [false, false])
        XCTAssertTrue(userDefaults.bool(forKey: CommandTabTakeoverController.takeoverMarkerKey))

        calls.removeAll()
        controller.restoreSystemShortcutsIfNeeded()

        XCTAssertEqual(calls.map(\.id), [1, 2])
        XCTAssertEqual(calls.map(\.enabled), [true, true])
        XCTAssertFalse(userDefaults.bool(forKey: CommandTabTakeoverController.takeoverMarkerKey))
    }

    func testCommandTabTakeoverControllerReconcileRecoversFromAbnormalExitOnlyOnce() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }
        userDefaults.set(true, forKey: CommandTabTakeoverController.takeoverMarkerKey)

        var calls: [(id: Int32, enabled: Bool)] = []
        let controller = CommandTabTakeoverController(
            userDefaults: userDefaults,
            symbolicHotKeySetterOverride: { id, enabled in
                calls.append((id: id, enabled: enabled))
                return noErr
            }
        )

        XCTAssertTrue(controller.reconcileIfNeeded(shouldTakeOver: false))
        XCTAssertEqual(calls.map(\.id), [1, 2])
        XCTAssertEqual(calls.map(\.enabled), [true, true])
        XCTAssertFalse(userDefaults.bool(forKey: CommandTabTakeoverController.takeoverMarkerKey))

        calls.removeAll()
        XCTAssertTrue(controller.reconcileIfNeeded(shouldTakeOver: false))
        XCTAssertTrue(calls.isEmpty)
    }

    func testCommandTabTakeoverControllerReconcileFailureRollsBackAndClearsMarker() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        var calls: [(id: Int32, enabled: Bool)] = []
        let controller = CommandTabTakeoverController(
            userDefaults: userDefaults,
            symbolicHotKeySetterOverride: { id, enabled in
                calls.append((id: id, enabled: enabled))
                if !enabled && id == 1 {
                    return OSStatus(paramErr)
                }
                return noErr
            }
        )

        XCTAssertFalse(controller.reconcileIfNeeded(shouldTakeOver: true))
        XCTAssertEqual(
            calls.map { "\($0.id):\($0.enabled)" },
            ["1:false", "2:false", "1:true", "2:true"]
        )
        XCTAssertFalse(userDefaults.bool(forKey: CommandTabTakeoverController.takeoverMarkerKey))
    }

    @MainActor
    func testAppWindowCoordinatorOpenMethodsSelectRequestedTabBeforeActivation() async {
        let previousSelectedTab = HomeTabState.shared.selectedTab
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        defer {
            HomeTabState.shared.selectedTab = previousSelectedTab
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
        }

        let cases: [(name: String, initial: HomeTab, expected: HomeTab, open: () -> Void)] = [
            ("home", .settings, .home, { AppWindowCoordinator.openHome() }),
            ("logs", .home, .logs, { AppWindowCoordinator.openLogs() }),
            ("settings", .logs, .settings, { AppWindowCoordinator.openSettings() })
        ]

        for item in cases {
            let activated = expectation(description: "activation-\(item.name)")
            var observedTabAtActivation: HomeTab?
            HomeTabState.shared.selectedTab = item.initial
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {
                observedTabAtActivation = HomeTabState.shared.selectedTab
                activated.fulfill()
            }

            item.open()

            await fulfillment(of: [activated], timeout: 1.0)
            XCTAssertEqual(HomeTabState.shared.selectedTab, item.expected)
            XCTAssertEqual(observedTabAtActivation, item.expected)
        }
    }

    @MainActor
    func testSwitcherPanelControllerSearchTabTogglesScope() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let controller = SwitcherPanelController()
            controller.modelForTesting.snapshotProviderOverride = {
                RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
            }

            XCTAssertTrue(controller.modelForTesting.startSession(triggerDirection: .forward))
            XCTAssertTrue(controller.modelForTesting.enterSearchMode())
            XCTAssertEqual(controller.modelForTesting.searchScope, .app)

            let handled = controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 48))

            XCTAssertTrue(handled)
            XCTAssertEqual(controller.modelForTesting.searchScope, .window)
        }
    }

    @MainActor
    func testSwitcherPanelControllerSearchArrowKeysMoveFocusAndSelection() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let controller = SwitcherPanelController()
            controller.modelForTesting.snapshotProviderOverride = {
                RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
            }

            XCTAssertTrue(controller.modelForTesting.startSession(triggerDirection: .forward))
            XCTAssertTrue(controller.modelForTesting.enterSearchMode())
            XCTAssertTrue(controller.modelForTesting.isSearchInputFocused)

            XCTAssertTrue(controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 125)))
            XCTAssertFalse(controller.modelForTesting.isSearchInputFocused)
            XCTAssertEqual(controller.modelForTesting.searchViewState.selectedResultIndex, 0)

            XCTAssertTrue(controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 125)))
            XCTAssertEqual(controller.modelForTesting.searchViewState.selectedResultIndex, 1)

            XCTAssertTrue(controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 126)))
            XCTAssertTrue(controller.modelForTesting.isSearchInputFocused)
        }
    }

    @MainActor
    func testSwitcherPanelControllerSearchEnterAppliesSelectionAndEscapeExitsSearch() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let controller = SwitcherPanelController()
            controller.modelForTesting.snapshotProviderOverride = {
                RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
            }

            XCTAssertTrue(controller.modelForTesting.startSession(triggerDirection: .forward))
            XCTAssertTrue(controller.modelForTesting.enterSearchMode())
            XCTAssertTrue(controller.modelForTesting.moveSearchSelection(by: 1))

            XCTAssertTrue(controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 36)))
            XCTAssertFalse(controller.modelForTesting.isSearchActive)
            XCTAssertEqual(controller.modelForTesting.selectedApp?.id, "com.example.code")

            XCTAssertTrue(controller.modelForTesting.enterSearchMode())
            XCTAssertTrue(controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 125)))
            XCTAssertFalse(controller.modelForTesting.isSearchInputFocused)

            XCTAssertTrue(controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 53)))
            XCTAssertTrue(controller.modelForTesting.isSearchActive)
            XCTAssertTrue(controller.modelForTesting.isSearchInputFocused)

            XCTAssertTrue(controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 53)))
            XCTAssertFalse(controller.modelForTesting.isSearchActive)
        }
    }

    @MainActor
    func testLiveSwitcherModelStartFocusedAppWindowSessionUsesFrontmostAppSnapshot() {
        let model = LiveSwitcherModel()
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "front-1", title: "Inbox", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "front-2", title: "Draft", isMinimized: false, lastActiveAt: 20)
        ]
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )

        model.frontmostApplicationOverride = { currentApp }
        model.snapshotProviderOverride = {
            RuntimeSnapshot(
                apps: [
                    AppSwitchCandidate(
                        id: appID,
                        displayName: currentApp.localizedName ?? "Current App",
                        groupID: "current",
                        lastActiveAt: 100,
                        windows: windows
                    ),
                    AppSwitchCandidate(
                        id: "com.example.other",
                        displayName: "Other",
                        groupID: "other",
                        lastActiveAt: 50,
                        windows: [
                            WindowCandidate(
                                id: "other-1",
                                title: "Other",
                                isMinimized: false,
                                lastActiveAt: 50
                            )
                        ]
                    )
                ],
                contextsByID: [appID: context]
            )
        }

        XCTAssertTrue(model.startFocusedAppWindowSession(triggerDirection: .forward))
        XCTAssertEqual(model.overlayStyle, .windowOnly)
        XCTAssertTrue(model.isPreviewLayerMode)
        XCTAssertEqual(model.previewWindowCount, 2)
        XCTAssertEqual(model.selectedApp?.id, appID)
        XCTAssertEqual(model.session?.mode, .windowCycle(appID: appID))
    }

    @MainActor
    func testLiveSwitcherModelAutoEnterWindowLayerSuppressesImmediateReentryAfterManualExit() {
        let model = LiveSwitcherModel()
        model.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertEqual(model.session?.mode, .appCycle)
        XCTAssertTrue(model.canAutoEnterWindowLayer)
        XCTAssertTrue(model.autoEnterWindowLayerIfPossible())
        XCTAssertEqual(model.session?.mode, .windowCycle(appID: model.selectedApp?.id ?? ""))

        model.handle(.upArrow)

        XCTAssertEqual(model.session?.mode, .appCycle)
        XCTAssertFalse(model.canAutoEnterWindowLayer)
        XCTAssertFalse(model.autoEnterWindowLayerIfPossible())
    }

    @MainActor
    func testSwitcherPanelControllerEnterStartsSearchFromMainSwitcher() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let controller = SwitcherPanelController()
            controller.modelForTesting.snapshotProviderOverride = {
                RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
            }

            XCTAssertTrue(controller.modelForTesting.startSession(triggerDirection: .forward))

            let handled = controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 36))

            XCTAssertTrue(handled)
            XCTAssertTrue(controller.modelForTesting.isSearchActive)
            XCTAssertNotNil(controller.modelForTesting.session)
            XCTAssertTrue(controller.modelForTesting.isSearchInputFocused)
        }
    }

    @MainActor
    func testSwitcherPanelControllerMarkedTextPassesSearchShortcutKeysThrough() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let controller = SwitcherPanelController()
            controller.modelForTesting.snapshotProviderOverride = {
                RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
            }

            XCTAssertTrue(controller.modelForTesting.startSession(triggerDirection: .forward))
            XCTAssertTrue(controller.modelForTesting.enterSearchMode())
            controller.modelForTesting.updateSearchInputMarkedTextState(true)

            XCTAssertFalse(controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 48)))
            XCTAssertEqual(controller.modelForTesting.searchScope, .app)

            XCTAssertFalse(controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 36)))
            XCTAssertTrue(controller.modelForTesting.isSearchActive)

            XCTAssertFalse(controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 53)))
            XCTAssertTrue(controller.modelForTesting.isSearchActive)
        }
    }

    @MainActor
    func testSwitcherPanelControllerQuitShortcutTriggersTerminateSelectedAppFlow() async {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.terminateScenarioApps(), contextsByID: [:])
        }
        controller.modelForTesting.terminateRequestOverride = { _ in
            (sent: true, pid: 42_100)
        }
        controller.modelForTesting.isProcessRunningOverride = { _ in true }

        XCTAssertTrue(controller.modelForTesting.startSession(triggerDirection: .forward))
        let selectedAppID = controller.modelForTesting.selectedApp?.id
        let hotkeyConfiguration = SwitcherHotkeyPreferencesStore.load()

        let handled = controller.handleKeyDownForTesting(
            Self.makeKeyDownEvent(
                keyCode: hotkeyConfiguration.quitKeyCode,
                modifierFlags: hotkeyConfiguration.primaryModifier.eventModifierFlag
            )
        )

        XCTAssertTrue(handled)
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(controller.modelForTesting.terminatingAppID, selectedAppID)
        XCTAssertNotNil(controller.modelForTesting.session)
        controller.modelForTesting.cancelSelection()
    }

    func testOptionTabHotkeyMonitorRoutesForwardAndBackwardPressReleaseCallbacks() {
        let monitor = OptionTabHotkeyMonitor(
            configuration: SwitcherHotkeyPreferencesStore.resolve(
                primaryModifierRaw: SwitcherPrimaryModifier.option.rawValue,
                mainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
                quitKeyRaw: SwitcherHotkeyKey.q.rawValue
            ),
            signature: 0x54455354,
            forwardHotkeyID: 11,
            backwardHotkeyID: 22,
            startsMonitoring: false
        )

        var events: [String] = []
        monitor.onHotkeyPressed = { isBackward in
            events.append(isBackward ? "press-backward" : "press-forward")
        }
        monitor.onHotkeyReleased = { isBackward in
            events.append(isBackward ? "release-backward" : "release-forward")
        }

        XCTAssertEqual(
            monitor.dispatchHotkeyEventForTesting(id: 11, phase: .pressed),
            noErr
        )
        XCTAssertEqual(
            monitor.dispatchHotkeyEventForTesting(id: 11, phase: .released),
            noErr
        )
        XCTAssertEqual(
            monitor.dispatchHotkeyEventForTesting(id: 22, phase: .pressed),
            noErr
        )
        XCTAssertEqual(
            monitor.dispatchHotkeyEventForTesting(id: 22, phase: .released),
            noErr
        )

        XCTAssertEqual(
            events,
            ["press-forward", "release-forward", "press-backward", "release-backward"]
        )
    }

    func testOptionTabHotkeyMonitorPassesThroughUnrelatedEvents() {
        let monitor = OptionTabHotkeyMonitor(signature: 0x54455354, startsMonitoring: false)
        var callbackCount = 0
        monitor.onHotkeyPressed = { _ in callbackCount += 1 }
        monitor.onHotkeyReleased = { _ in callbackCount += 1 }

        XCTAssertEqual(
            monitor.dispatchHotkeyEventForTesting(signature: 0x42414421, id: 1, phase: .pressed),
            OSStatus(eventNotHandledErr)
        )
        XCTAssertEqual(
            monitor.dispatchHotkeyEventForTesting(id: 999, phase: .released),
            OSStatus(eventNotHandledErr)
        )
        XCTAssertEqual(callbackCount, 0)
    }

    func testRuntimeSnapshotProviderVisibilityHelpersCoverCurrentProcessAndMinimizedApps() {
        XCTAssertFalse(
            RuntimeSnapshotProvider.shouldIncludeRunningApplication(
                activationPolicy: .accessory,
                isTerminated: false,
                pid: 10,
                currentPID: 99,
                includeCurrentProcessInAppLayer: false
            )
        )
        XCTAssertFalse(
            RuntimeSnapshotProvider.shouldIncludeRunningApplication(
                activationPolicy: .regular,
                isTerminated: true,
                pid: 10,
                currentPID: 99,
                includeCurrentProcessInAppLayer: false
            )
        )
        XCTAssertFalse(
            RuntimeSnapshotProvider.shouldIncludeRunningApplication(
                activationPolicy: .regular,
                isTerminated: false,
                pid: 99,
                currentPID: 99,
                includeCurrentProcessInAppLayer: false
            )
        )
        XCTAssertTrue(
            RuntimeSnapshotProvider.shouldIncludeRunningApplication(
                activationPolicy: .regular,
                isTerminated: false,
                pid: 99,
                currentPID: 99,
                includeCurrentProcessInAppLayer: true
            )
        )

        XCTAssertTrue(
            RuntimeSnapshotProvider.shouldIncludeAppInAppLayer(
                hasWindows: false,
                hasVisibleWindow: false,
                hideMinimizedAppsFromAppLayer: true
            )
        )
        XCTAssertFalse(
            RuntimeSnapshotProvider.shouldIncludeAppInAppLayer(
                hasWindows: true,
                hasVisibleWindow: false,
                hideMinimizedAppsFromAppLayer: true
            )
        )
        XCTAssertTrue(
            RuntimeSnapshotProvider.shouldIncludeAppInAppLayer(
                hasWindows: true,
                hasVisibleWindow: true,
                hideMinimizedAppsFromAppLayer: true
            )
        )
    }

    func testSystemAppMRUTrackerRankingPrefersTrackedOrderThenFallbackAndCurrentAppLaunchRank() {
        let rankByPID = SystemAppMRUTracker.rankByPID(
            runningPIDs: [10, 20, 30, 40],
            trackedOrder: [20, 77],
            currentPID: 10,
            launchRankByPID: [10: 5, 20: 0, 30: 2, 40: 1],
            fallbackRankByPID: [30: 0, 40: 1, 10: 2]
        )

        XCTAssertEqual(rankByPID[20], 0)
        XCTAssertEqual(rankByPID[30], 1)
        XCTAssertEqual(rankByPID[40], 2)
        XCTAssertEqual(rankByPID[10], 3)
    }

    @MainActor
    func testRuntimeActivatorShortCircuitsActivationForCurrentProcessTarget() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        var observedPID: pid_t?
        var requestActivationCallCount = 0
        activator.activateCurrentAppIfNeededOverride = { app in
            observedPID = app.processIdentifier
            return true
        }
        activator.requestActivationOverride = { _, _ in
            requestActivationCallCount += 1
        }

        activator.activate(
            target: .app(appID: appID),
            contextsByID: [
                appID: makeRuntimeAppContext(appID: appID, runningApp: currentApp, windows: [])
            ]
        )

        XCTAssertEqual(observedPID, currentApp.processIdentifier)
        XCTAssertEqual(requestActivationCallCount, 0)
    }

    @MainActor
    func testRuntimeActivatorWindowActivationRestoresMinimizedWindowAndFallsBackWhenMissing() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }

        var requestedActivationPIDs: [pid_t] = []
        activator.requestActivationOverride = { app, completion in
            requestedActivationPIDs.append(app.processIdentifier)
            completion?(app)
        }

        var focusedWindowCalls: [(id: String, title: String, restore: Bool)] = []
        activator.focusWindowOverride = { windowID, title, restoreIfMinimized, _ in
            focusedWindowCalls.append((windowID, title, restoreIfMinimized))
        }

        let minimizedContext = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: [
                WindowCandidate(id: "mail-1", title: "Inbox", isMinimized: true, lastActiveAt: 10)
            ]
        )
        activator.activate(
            target: .window(appID: appID, windowID: "mail-1", restoreIfMinimized: false),
            contextsByID: [appID: minimizedContext]
        )

        XCTAssertEqual(requestedActivationPIDs, [currentApp.processIdentifier])
        XCTAssertEqual(focusedWindowCalls.count, 1)
        XCTAssertEqual(focusedWindowCalls.first?.id, "mail-1")
        XCTAssertEqual(focusedWindowCalls.first?.title, "Inbox")
        XCTAssertEqual(focusedWindowCalls.first?.restore, true)

        requestedActivationPIDs.removeAll()
        focusedWindowCalls.removeAll()

        let missingWindowContext = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: []
        )
        activator.activate(
            target: .window(appID: appID, windowID: "missing", restoreIfMinimized: true),
            contextsByID: [appID: missingWindowContext]
        )

        XCTAssertEqual(requestedActivationPIDs, [currentApp.processIdentifier])
        XCTAssertTrue(focusedWindowCalls.isEmpty)
    }

    private func commitScenarioApps() -> [AppSwitchCandidate] {
        [
            AppSwitchCandidate(
                id: "com.example.mail",
                displayName: "Mail",
                groupID: "office",
                lastActiveAt: 300,
                windows: [
                    WindowCandidate(id: "mail-old", title: "Inbox", isMinimized: false, lastActiveAt: 200),
                    WindowCandidate(id: "mail-new", title: "Draft", isMinimized: false, lastActiveAt: 350)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.code",
                displayName: "Code",
                groupID: "dev",
                lastActiveAt: 290,
                windows: [
                    WindowCandidate(id: "code-1", title: "FlowTab", isMinimized: false, lastActiveAt: 290)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.browser",
                displayName: "Browser",
                groupID: "web",
                lastActiveAt: 280,
                windows: [
                    WindowCandidate(id: "browser-1", title: "Docs", isMinimized: false, lastActiveAt: 280)
                ]
            )
        ]
    }

    private func searchScenarioApps() -> [AppSwitchCandidate] {
        [
            AppSwitchCandidate(
                id: "com.example.mail",
                displayName: "Mail",
                groupID: "office",
                lastActiveAt: 300,
                windows: [
                    WindowCandidate(id: "mail-1", title: "Inbox", isMinimized: false, lastActiveAt: 300),
                    WindowCandidate(id: "mail-2", title: "Draft", isMinimized: false, lastActiveAt: 280)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.code",
                displayName: "Code",
                groupID: "dev",
                lastActiveAt: 290,
                windows: [
                    WindowCandidate(id: "code-1", title: "FlowTab", isMinimized: false, lastActiveAt: 290),
                    WindowCandidate(id: "code-2", title: "README", isMinimized: false, lastActiveAt: 270)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.browser",
                displayName: "Browser",
                groupID: "web",
                lastActiveAt: 280,
                windows: [
                    WindowCandidate(id: "browser-1", title: "Docs", isMinimized: false, lastActiveAt: 280)
                ]
            )
        ]
    }

    private func terminateScenarioApps() -> [AppSwitchCandidate] {
        [
            AppSwitchCandidate(
                id: "com.example.mail",
                displayName: "Mail",
                groupID: "office",
                lastActiveAt: 300,
                windows: [
                    WindowCandidate(id: "mail-1", title: "Inbox", isMinimized: false, lastActiveAt: 300)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.code",
                displayName: "Code",
                groupID: "dev",
                lastActiveAt: 290,
                windows: [
                    WindowCandidate(id: "code-1", title: "FlowTab", isMinimized: false, lastActiveAt: 290)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.browser",
                displayName: "Browser",
                groupID: "web",
                lastActiveAt: 280,
                windows: [
                    WindowCandidate(id: "browser-1", title: "Docs", isMinimized: false, lastActiveAt: 280)
                ]
            )
        ]
    }

    private func makeRuntimeAppContext(
        appID: String,
        runningApp: NSRunningApplication,
        windows: [WindowCandidate]
    ) -> RuntimeAppContext {
        let windowsByID = Dictionary(
            uniqueKeysWithValues: windows.map { window in
                (
                    window.id,
                    RuntimeWindowContext(
                        id: window.id,
                        title: window.title,
                        isMinimized: window.isMinimized,
                        cgWindowID: nil,
                        inferredTitleBarStyle: nil
                    )
                )
            }
        )
        return RuntimeAppContext(
            appID: appID,
            runningApp: runningApp,
            windowsByID: windowsByID
        )
    }

    private func makeIsolatedUserDefaults() -> UserDefaults? {
        let suiteName = "FlowTabPriorityCoverageTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated user defaults suite")
            return nil
        }
        userDefaults.set(suiteName, forKey: "FlowTabPriorityCoverageTestsSuiteName")
        return userDefaults
    }

    private func clearIsolatedUserDefaults(_ userDefaults: UserDefaults) {
        guard let suiteName = userDefaults.string(forKey: "FlowTabPriorityCoverageTestsSuiteName") else {
            return
        }
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    private func restoreUserDefaultsValue(
        _ value: Any?,
        forKey key: String,
        userDefaults: UserDefaults
    ) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    private func withTemporarySearchPreferences(
        enabled: Bool,
        defaultScope: SwitcherSearchScope,
        perform body: () async throws -> Void
    ) async rethrows {
        let defaults = UserDefaults.standard
        let previousEnabled = defaults.object(forKey: AppPreferenceKeys.searchEnabled)
        let previousScope = defaults.object(forKey: AppPreferenceKeys.searchDefaultScope)
        defaults.set(enabled, forKey: AppPreferenceKeys.searchEnabled)
        defaults.set(defaultScope.rawValue, forKey: AppPreferenceKeys.searchDefaultScope)
        defer {
            restoreUserDefaultsValue(
                previousEnabled,
                forKey: AppPreferenceKeys.searchEnabled,
                userDefaults: defaults
            )
            restoreUserDefaultsValue(
                previousScope,
                forKey: AppPreferenceKeys.searchDefaultScope,
                userDefaults: defaults
            )
        }
        try await body()
    }

    private static func makeKeyDownEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ) else {
            fatalError("Failed to create key event for tests")
        }
        return event
    }
}
