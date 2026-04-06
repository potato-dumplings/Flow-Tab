import AppKit
import Carbon
import CoreGraphics
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

    func testCommandTabTakeoverControllerSymbolicHotKeyResolverIsStableAcrossLookups() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        let controller = CommandTabTakeoverController(userDefaults: userDefaults)
        let firstLookup = controller.hasSymbolicHotKeySetterForTesting()
        let secondLookup = controller.hasSymbolicHotKeySetterForTesting()

        XCTAssertEqual(firstLookup, secondLookup)
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
    func testSwitcherPanelControllerSearchArrowKeysOnlyReturnToInputFromFirstResult() async {
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
            XCTAssertFalse(controller.modelForTesting.isSearchInputFocused)

            XCTAssertTrue(controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 126)))
            XCTAssertFalse(controller.modelForTesting.isSearchInputFocused)
            XCTAssertEqual(controller.modelForTesting.searchViewState.selectedResultIndex, 0)

            XCTAssertTrue(controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 126)))
            XCTAssertTrue(controller.modelForTesting.isSearchInputFocused)
        }
    }

    @MainActor
    func testSwitcherPanelControllerSearchWrapRequestsScrollBackToFirstResult() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let controller = SwitcherPanelController()
            controller.modelForTesting.snapshotProviderOverride = {
                RuntimeSnapshot(apps: self.searchWrapScenarioApps(), contextsByID: [:])
            }

            var scrollRequests: [String] = []
            controller.modelForTesting.onSearchResultScrollRequestForTesting = { resultID in
                scrollRequests.append(resultID)
            }

            XCTAssertTrue(controller.presentGlobalHotkeySessionForTesting())
            XCTAssertTrue(controller.modelForTesting.enterSearchMode())
            controller.updatePanelSizeForTesting(
                visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
            )
            try? await Task.sleep(nanoseconds: 200_000_000)

            guard let firstResultID = controller.modelForTesting.searchViewState.results.first?.id else {
                XCTFail("Expected search results after entering search mode")
                controller.cancelSelectionForTesting()
                return
            }

            XCTAssertTrue(controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 125)))
            try? await Task.sleep(nanoseconds: 50_000_000)

            let moveCountToLastResult = max(0, controller.modelForTesting.searchResultCount - 1)
            for _ in 0..<moveCountToLastResult {
                XCTAssertTrue(controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 125)))
                try? await Task.sleep(nanoseconds: 50_000_000)
            }

            XCTAssertEqual(
                controller.modelForTesting.searchViewState.selectedResultIndex,
                controller.modelForTesting.searchResultCount - 1
            )

            XCTAssertTrue(controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 125)))
            try? await Task.sleep(nanoseconds: 50_000_000)

            XCTAssertEqual(controller.modelForTesting.searchViewState.selectedResultIndex, 0)
            XCTAssertEqual(scrollRequests.last, firstResultID)
            controller.cancelSelectionForTesting()
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

    @MainActor
    func testSwitcherPanelControllerQuitFrontmostAppInAppLayerKeepsSessionAfterAutomaticTerminationRefresh() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let controller = SwitcherPanelController()
            let initialApps = self.terminateScenarioApps()
            let refreshedApps = initialApps.filter { $0.id != "com.example.code" }
            var snapshots = [
                RuntimeSnapshot(apps: initialApps, contextsByID: [:]),
                RuntimeSnapshot(apps: refreshedApps, contextsByID: [:])
            ]
            controller.modelForTesting.snapshotProviderOverride = {
                snapshots.removeFirst()
            }
            controller.modelForTesting.terminateRequestOverride = { _ in
                (sent: true, pid: 42_100)
            }
            // Use polling path to drive a fully automatic refresh after quit shortcut.
            controller.modelForTesting.isProcessRunningOverride = { _ in false }

            XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
            XCTAssertEqual(controller.modelForTesting.selectedApp?.id, "com.example.code")
            XCTAssertFalse(controller.modelForTesting.isSearchActive)

            let layoutRefreshed = expectation(
                description: "layout refreshed automatically after terminating frontmost app in app layer"
            )
            controller.modelForTesting.onSessionLayoutChanged = { layoutRefreshed.fulfill() }

            let hotkeyConfiguration = SwitcherHotkeyPreferencesStore.load()
            let handled = controller.handleKeyDownForTesting(
                Self.makeKeyDownEvent(
                    keyCode: hotkeyConfiguration.quitKeyCode,
                    modifierFlags: hotkeyConfiguration.primaryModifier.eventModifierFlag
                )
            )
            XCTAssertTrue(handled)

            await fulfillment(of: [layoutRefreshed], timeout: 1.0)
            try? await Task.sleep(nanoseconds: 120_000_000)

            XCTAssertNotNil(controller.modelForTesting.session)
            XCTAssertEqual(controller.modelForTesting.appCount, 2)
            XCTAssertEqual(controller.modelForTesting.selectedApp?.id, "com.example.browser")
            XCTAssertFalse(controller.modelForTesting.isSearchActive)
            controller.cancelSelectionForTesting()
        }
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

    func testOptionTabHotkeyMonitorParsesRawCarbonEvents() {
        let monitor = OptionTabHotkeyMonitor(
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

        let unsupportedKind = makeCarbonHotkeyEvent(
            kind: UInt32(kEventRawKeyDown),
            signature: 0x54455354,
            id: 11,
            includeHotkeyPayload: true
        )
        XCTAssertEqual(
            monitor.handleHotkeyEventForTesting(unsupportedKind),
            OSStatus(eventNotHandledErr)
        )

        let missingPayload = makeCarbonHotkeyEvent(
            kind: UInt32(kEventHotKeyPressed),
            signature: 0x54455354,
            id: 11,
            includeHotkeyPayload: false
        )
        XCTAssertEqual(
            monitor.handleHotkeyEventForTesting(missingPayload),
            OSStatus(eventNotHandledErr)
        )

        let wrongSignature = makeCarbonHotkeyEvent(
            kind: UInt32(kEventHotKeyPressed),
            signature: 0x42414421,
            id: 11,
            includeHotkeyPayload: true
        )
        XCTAssertEqual(
            monitor.handleHotkeyEventForTesting(wrongSignature),
            OSStatus(eventNotHandledErr)
        )

        let forwardPressed = makeCarbonHotkeyEvent(
            kind: UInt32(kEventHotKeyPressed),
            signature: 0x54455354,
            id: 11,
            includeHotkeyPayload: true
        )
        XCTAssertEqual(monitor.handleHotkeyEventForTesting(forwardPressed), noErr)

        let backwardReleased = makeCarbonHotkeyEvent(
            kind: UInt32(kEventHotKeyReleased),
            signature: 0x54455354,
            id: 22,
            includeHotkeyPayload: true
        )
        XCTAssertEqual(monitor.handleHotkeyEventForTesting(backwardReleased), noErr)

        XCTAssertEqual(events, ["press-forward", "release-backward"])
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

    func testSystemAppMRUTrackerHelpersCoverNotificationRemovalAndPruningPaths() {
        let tracker = SystemAppMRUTracker.shared
        tracker.resetStateForTesting()
        defer { tracker.resetStateForTesting() }

        tracker.recordActivationForTesting(pid: 4_001)
        tracker.recordActivationForTesting(pid: 4_002)
        tracker.recordActivationForTesting(pid: 4_001)
        XCTAssertEqual(tracker.trackedMRUOrderForTesting(runningPIDs: [4_001, 4_002]), [4_001, 4_002])

        tracker.removeForTesting(pid: 4_002)
        XCTAssertEqual(tracker.trackedMRUOrderForTesting(runningPIDs: [4_001, 4_002]), [4_001])

        tracker.handleApplicationNotificationForTesting(app: nil, removeOnly: true)
        XCTAssertEqual(tracker.trackedMRUOrderForTesting(runningPIDs: [4_001]), [4_001])

        tracker.handleApplicationNotificationForTesting(app: .current, removeOnly: false)
        XCTAssertEqual(
            tracker.trackedMRUOrderForTesting(
                runningPIDs: [4_001, ProcessInfo.processInfo.processIdentifier]
            ),
            [4_001]
        )

        tracker.recordActivationForTesting(pid: 4_999)
        XCTAssertEqual(tracker.trackedMRUOrderForTesting(runningPIDs: [4_001]), [4_001])
    }

    func testSystemAppMRUTrackerRankingFallsBackWhenCurrentPIDLaunchRankIsMissing() {
        let rankByPID = SystemAppMRUTracker.rankByPID(
            runningPIDs: [101, 202],
            trackedOrder: [],
            currentPID: 101,
            launchRankByPID: [:],
            fallbackRankByPID: [202: 0, 101: 5]
        )

        XCTAssertEqual(rankByPID[202], 0)
        XCTAssertEqual(rankByPID[101], 1)
    }

    @MainActor
    func testSystemAppMRUTrackerObserversProcessWorkspaceActivationAndTerminationNotifications() throws {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard
            let otherApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.processIdentifier != currentPID && !$0.isTerminated
            })
        else {
            throw XCTSkip("No secondary running app is available for observer notification coverage.")
        }

        let tracker = SystemAppMRUTracker.shared
        tracker.resetStateForTesting()
        defer { tracker.resetStateForTesting() }

        tracker.startIfNeeded()
        let notificationCenter = NSWorkspace.shared.notificationCenter

        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: otherApp]
        )
        XCTAssertEqual(
            tracker.trackedMRUOrderForTesting(runningPIDs: [otherApp.processIdentifier]),
            [otherApp.processIdentifier]
        )

        notificationCenter.post(
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: otherApp]
        )
        XCTAssertEqual(
            tracker.trackedMRUOrderForTesting(runningPIDs: [otherApp.processIdentifier]),
            []
        )
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

    @MainActor
    func testLiveSwitcherModelHandleApplicationTerminatedRefreshesSessionAndKeepsPreferredNextSelection() async {
        let model = LiveSwitcherModel()
        let initialApps = terminateScenarioApps()
        let refreshedApps = initialApps.filter { $0.id != "com.example.code" }
        var snapshots = [
            RuntimeSnapshot(apps: initialApps, contextsByID: [:]),
            RuntimeSnapshot(apps: refreshedApps, contextsByID: [:])
        ]
        var snapshotReadCount = 0
        model.snapshotProviderOverride = {
            snapshotReadCount += 1
            return snapshots.removeFirst()
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertEqual(model.selectedApp?.id, "com.example.code")

        let layoutRefreshed = expectation(description: "layout refreshed after app termination")
        model.onSessionLayoutChanged = { layoutRefreshed.fulfill() }

        model.handleApplicationTerminated(appID: "com.example.code", pid: 42_300)

        await fulfillment(of: [layoutRefreshed], timeout: 1.0)
        XCTAssertEqual(snapshotReadCount, 2)
        XCTAssertEqual(model.appCount, 2)
        XCTAssertEqual(model.selectedApp?.id, "com.example.browser")
    }

    @MainActor
    func testLiveSwitcherModelHandleApplicationTerminatedPreservesSearchStateDuringRefresh() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let model = LiveSwitcherModel()
            let initialApps = self.searchScenarioApps()
            let refreshedApps = initialApps.filter { $0.id != "com.example.code" }
            var snapshots = [
                RuntimeSnapshot(apps: initialApps, contextsByID: [:]),
                RuntimeSnapshot(apps: refreshedApps, contextsByID: [:])
            ]
            model.snapshotProviderOverride = {
                snapshots.removeFirst()
            }

            XCTAssertTrue(model.startSession(triggerDirection: .forward))
            XCTAssertTrue(model.enterSearchMode())
            model.synchronizeSearchInput(query: "bro", cursorPosition: 3)

            try? await Task.sleep(nanoseconds: 120_000_000)
            XCTAssertTrue(model.isSearchActive)
            XCTAssertEqual(model.searchViewState.query, "bro")

            let layoutRefreshed = expectation(description: "layout refreshed while preserving search state")
            model.onSessionLayoutChanged = { layoutRefreshed.fulfill() }

            model.handleApplicationTerminated(appID: "com.example.code", pid: 42_300)

            await fulfillment(of: [layoutRefreshed], timeout: 1.0)
            try? await Task.sleep(nanoseconds: 120_000_000)

            XCTAssertEqual(model.appCount, 2)
            XCTAssertTrue(model.isSearchActive)
            XCTAssertEqual(model.searchViewState.scope, .app)
            XCTAssertEqual(model.searchViewState.query, "bro")
            XCTAssertGreaterThanOrEqual(model.searchResultCount, 1)
        }
    }

    @MainActor
    func testLiveSwitcherModelHandleApplicationTerminatedIgnoresUntrackedApp() {
        let model = LiveSwitcherModel()
        let initialApps = terminateScenarioApps()
        var snapshotReadCount = 0
        model.snapshotProviderOverride = {
            snapshotReadCount += 1
            return RuntimeSnapshot(apps: initialApps, contextsByID: [:])
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        let selectedAppID = model.selectedApp?.id

        model.handleApplicationTerminated(appID: "com.example.unrelated", pid: 99_999)

        XCTAssertEqual(snapshotReadCount, 1)
        XCTAssertEqual(model.appCount, initialApps.count)
        XCTAssertEqual(model.selectedApp?.id, selectedAppID)
    }

    func testOptionTabHotkeyMonitorSkipsHotkeyRegistrationWhenHandlerInstallFails() {
        var registerCalls: [UInt32] = []
        let monitor = OptionTabHotkeyMonitor(
            signature: 0x54455354,
            forwardHotkeyID: 11,
            backwardHotkeyID: 22,
            startsMonitoring: true,
            handlerInstallerOverride: { false },
            hotkeyRegistrarOverride: { id, _, _ in
                registerCalls.append(id)
                return true
            }
        )

        XCTAssertFalse(monitor.isEventHandlerInstalledForTesting)
        XCTAssertTrue(registerCalls.isEmpty)
    }

    func testOptionTabHotkeyMonitorStopUnregistersOnlySuccessfullyRegisteredHotkeys() {
        var registerCalls: [UInt32] = []
        var unregisterCalls: [UInt32] = []
        var removeHandlerCallCount = 0
        let monitor = OptionTabHotkeyMonitor(
            signature: 0x54455354,
            forwardHotkeyID: 11,
            backwardHotkeyID: 22,
            startsMonitoring: true,
            handlerInstallerOverride: { true },
            hotkeyRegistrarOverride: { id, _, _ in
                registerCalls.append(id)
                return id == 11
            },
            hotkeyUnregisterOverride: { unregisterCalls.append($0) },
            eventHandlerRemoverOverride: { removeHandlerCallCount += 1 }
        )

        XCTAssertTrue(monitor.isEventHandlerInstalledForTesting)
        XCTAssertEqual(registerCalls, [11, 22])

        monitor.stop()

        XCTAssertEqual(unregisterCalls, [11])
        XCTAssertEqual(removeHandlerCallCount, 1)
        XCTAssertFalse(monitor.isEventHandlerInstalledForTesting)
    }

    @MainActor
    func testFlowTabAppInitStartsMRUTracking() {
        let previousTracker = FlowTabApp.mruTracker
        let tracker = SpyMRUTracker()
        defer {
            FlowTabApp.mruTracker = previousTracker
        }

        FlowTabApp.mruTracker = tracker

        _ = FlowTabApp()

        XCTAssertEqual(tracker.startCallCount, 1)
    }

    @MainActor
    func testAppDelegateLaunchInstallsObserversPromptsAccessibilityAndStartsStressRunner() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let takeoverController = SpyCommandTabTakeoverController()
        let stressRunner = SpyStressRunner()
        defer {
            AppDelegate.testHooks = previousHooks
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            clearIsolatedUserDefaults(userDefaults)
        }

        var accessibilityPromptCount = 0
        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { false }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = {
            accessibilityPromptCount += 1
            return false
        }

        let openHome = expectation(description: "open home after launch")
        HomeTabState.shared.selectedTab = .settings
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {
            openHome.fulfill()
        }
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: nil,
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: takeoverController,
            stressRunner: stressRunner
        )

        let delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        await fulfillment(of: [openHome], timeout: 1.0)
        XCTAssertEqual(HomeTabState.shared.selectedTab, .home)
        XCTAssertTrue(delegate.hasPanelControllerForTesting)
        XCTAssertTrue(delegate.hasMainHotkeyMonitorForTesting)
        XCTAssertTrue(delegate.hasInAppHotkeyMonitorForTesting)
        XCTAssertTrue(delegate.hasHotkeyObserverForTesting)
        XCTAssertTrue(delegate.hasAppVisibilityObserverForTesting)
        XCTAssertTrue(delegate.hasLanguageObserverForTesting)
        XCTAssertTrue(delegate.hasStatusItemForTesting)
        XCTAssertEqual(accessibilityPromptCount, 1)
        XCTAssertTrue(userDefaults.bool(forKey: AppPreferenceKeys.hasPromptedAccessibilityPermission))
        XCTAssertEqual(stressRunner.startCallCount, 1)
        XCTAssertEqual(takeoverController.reconcileCalls, [false])
        XCTAssertEqual(hotkeyFactory.records.map(\.signature), [0x46544142, 0x4654574E])
        XCTAssertEqual(hotkeyFactory.records.map(\.forwardHotkeyID), [1, 101])
        XCTAssertEqual(hotkeyFactory.records.map(\.backwardHotkeyID), [2, 102])
    }

    @MainActor
    func testAppDelegateLaunchSkipsAccessibilityPromptWhenAlreadyPromptedOrReminderDisabled() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        defer {
            AppDelegate.testHooks = previousHooks
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            clearIsolatedUserDefaults(userDefaults)
        }

        let cases: [(name: String, configure: (UserDefaults) -> Void)] = [
            ("alreadyPrompted", { defaults in
                defaults.set(true, forKey: AppPreferenceKeys.hasPromptedAccessibilityPermission)
            }),
            ("reminderDisabled", { defaults in
                defaults.set(false, forKey: AppPreferenceKeys.showPermissionReminder)
            })
        ]

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { false }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}

        for item in cases {
            userDefaults.removePersistentDomain(
                forName: userDefaults.string(forKey: "FlowTabPriorityCoverageTestsSuiteName") ?? ""
            )
            item.configure(userDefaults)

            let hotkeyFactory = SpyHotkeyMonitorFactory()
            var promptCount = 0
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = {
                promptCount += 1
                return false
            }
            AppDelegate.testHooks = AppDelegate.TestHooks(
                userDefaults: userDefaults,
                makePanelController: nil,
                makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                    hotkeyFactory.make(
                        configuration: configuration,
                        signature: signature,
                        forwardHotkeyID: forwardHotkeyID,
                        backwardHotkeyID: backwardHotkeyID
                    )
                },
                commandTabTakeoverController: SpyCommandTabTakeoverController(),
                stressRunner: SpyStressRunner()
            )

            let delegate = AppDelegate()
            delegate.applicationDidFinishLaunching(
                Notification(name: NSApplication.didFinishLaunchingNotification)
            )

            XCTAssertEqual(promptCount, 0, "Unexpected accessibility prompt for \(item.name)")
        }
    }

    @MainActor
    func testAppDelegateTerminationRemovesObserversStopsHotkeyMonitorsAndRestoresTakeover() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let takeoverController = SpyCommandTabTakeoverController()
        defer {
            AppDelegate.testHooks = previousHooks
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            clearIsolatedUserDefaults(userDefaults)
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: nil,
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: takeoverController,
            stressRunner: SpyStressRunner()
        )

        let delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        XCTAssertFalse(delegate.hasHotkeyObserverForTesting)
        XCTAssertFalse(delegate.hasAppVisibilityObserverForTesting)
        XCTAssertFalse(delegate.hasLanguageObserverForTesting)
        XCTAssertEqual(hotkeyFactory.records.count, 2)
        XCTAssertEqual(hotkeyFactory.records[0].monitor.stopCallCount, 1)
        XCTAssertEqual(hotkeyFactory.records[1].monitor.stopCallCount, 1)
        XCTAssertEqual(takeoverController.restoreCallCount, 1)
    }

    @MainActor
    func testAppDelegateHotkeyObserverUsesPostedConfigurationsImmediately() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let takeoverController = SpyCommandTabTakeoverController()
        var delegate: AppDelegate?
        defer {
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            clearIsolatedUserDefaults(userDefaults)
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: nil,
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: takeoverController,
            stressRunner: SpyStressRunner()
        )

        let appDelegate = AppDelegate()
        delegate = appDelegate
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        let baselineRecordCount = hotkeyFactory.records.count
        XCTAssertGreaterThanOrEqual(baselineRecordCount, 2)
        let previousMainMonitor = hotkeyFactory.records[baselineRecordCount - 2].monitor
        let previousInAppMonitor = hotkeyFactory.records[baselineRecordCount - 1].monitor

        let request = HotkeyRegistrationRequest(
            mainConfiguration: SwitcherHotkeyConfiguration(
                primaryModifier: .command,
                mainKey: .tab,
                quitKey: .q
            ),
            inAppWindowConfiguration: SwitcherHotkeyConfiguration(
                primaryModifier: .option,
                mainKey: .grave,
                quitKey: .q
            )
        )
        NotificationCenter.default.post(
            name: .flowTabReRegisterHotkeys,
            object: nil,
            userInfo: request.notificationUserInfo
        )

        try? await Task.sleep(nanoseconds: 120_000_000)

        let newRecords = Array(hotkeyFactory.records.dropFirst(baselineRecordCount))
        XCTAssertEqual(newRecords.count, 2)
        XCTAssertGreaterThanOrEqual(previousMainMonitor.stopCallCount, 1)
        XCTAssertGreaterThanOrEqual(previousInAppMonitor.stopCallCount, 1)
        XCTAssertTrue(
            newRecords.contains {
                $0.signature == 0x46544142
                    && $0.configuration.primaryModifier == .command
                    && $0.configuration.mainKey == .tab
                    && $0.configuration.quitKey == .q
            }
        )
        XCTAssertTrue(
            newRecords.contains {
                $0.signature == 0x4654574E
                    && $0.configuration.primaryModifier == .option
                    && $0.configuration.mainKey == .grave
                    && $0.configuration.quitKey == .q
            }
        )
        XCTAssertEqual(takeoverController.reconcileCalls.last, true)
    }

    @MainActor
    func testAppDelegateDirectHotkeyReloadRegistersImmediatelyWithoutNotificationEcho() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let takeoverController = SpyCommandTabTakeoverController()
        var delegate: AppDelegate?
        defer {
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            clearIsolatedUserDefaults(userDefaults)
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: nil,
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: takeoverController,
            stressRunner: SpyStressRunner()
        )

        let appDelegate = AppDelegate()
        delegate = appDelegate
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        let baselineRecordCount = hotkeyFactory.records.count
        XCTAssertGreaterThanOrEqual(baselineRecordCount, 2)
        let previousMainMonitor = hotkeyFactory.records[baselineRecordCount - 2].monitor
        let previousInAppMonitor = hotkeyFactory.records[baselineRecordCount - 1].monitor

        let request = HotkeyRegistrationRequest(
            mainConfiguration: SwitcherHotkeyConfiguration(
                primaryModifier: .command,
                mainKey: .tab,
                quitKey: .q
            ),
            inAppWindowConfiguration: SwitcherHotkeyConfiguration(
                primaryModifier: .option,
                mainKey: .grave,
                quitKey: .q
            )
        )
        appDelegate.requestHotkeyReload(using: request, source: "test_direct")

        try? await Task.sleep(nanoseconds: 120_000_000)

        let newRecords = Array(hotkeyFactory.records.dropFirst(baselineRecordCount))
        XCTAssertEqual(newRecords.count, 2)
        XCTAssertGreaterThanOrEqual(previousMainMonitor.stopCallCount, 1)
        XCTAssertGreaterThanOrEqual(previousInAppMonitor.stopCallCount, 1)
        XCTAssertTrue(
            newRecords.contains {
                $0.signature == 0x46544142
                    && $0.configuration.primaryModifier == .command
                    && $0.configuration.mainKey == .tab
                    && $0.configuration.quitKey == .q
            }
        )
        XCTAssertTrue(
            newRecords.contains {
                $0.signature == 0x4654574E
                    && $0.configuration.primaryModifier == .option
                    && $0.configuration.mainKey == .grave
                    && $0.configuration.quitKey == .q
            }
        )
        XCTAssertEqual(takeoverController.reconcileCalls.last, true)
    }

    @MainActor
    func testAppDelegateSkipsInAppHotkeyMonitorWhenShortcutConflictsWithMainHotkey() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        defer {
            AppDelegate.testHooks = previousHooks
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            clearIsolatedUserDefaults(userDefaults)
        }

        userDefaults.set(
            SwitcherPrimaryModifier.option.rawValue,
            forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier
        )
        userDefaults.set(
            SwitcherHotkeyKey.tab.rawValue,
            forKey: AppPreferenceKeys.inAppWindowHotkeyMainKey
        )
        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: nil,
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: SpyCommandTabTakeoverController(),
            stressRunner: SpyStressRunner()
        )

        let delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        XCTAssertTrue(delegate.hasMainHotkeyMonitorForTesting)
        XCTAssertFalse(delegate.hasInAppHotkeyMonitorForTesting)
        XCTAssertEqual(hotkeyFactory.records.count, 1)
        XCTAssertEqual(hotkeyFactory.records.first?.signature, 0x46544142)
    }

    @MainActor
    func testAppDelegateLaunchWithUITestBootstrapArgumentsSeedsLogsAndOpensSearch() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let previousLaunchArguments = FlowTabTestLaunchOptions.argumentsOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let takeoverController = SpyCommandTabTakeoverController()
        let stressRunner = SpyStressRunner()
        let panelController = SwitcherPanelController()
        var delegate: AppDelegate?
        defer {
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            FlowTabTestLaunchOptions.argumentsOverrideForTesting = previousLaunchArguments
            RuntimeDiagnostics.shared.clear()
            clearIsolatedUserDefaults(userDefaults)
        }

        panelController.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }

        userDefaults.set(false, forKey: AppPreferenceKeys.showShortcutHint)
        userDefaults.set(
            RuntimeLogLevel.error.rawValue,
            forKey: AppPreferenceKeys.runtimeLogLevel
        )
        userDefaults.set(true, forKey: CommandTabTakeoverController.takeoverMarkerKey)
        HomeTabState.shared.selectedTab = .logs

        RuntimeDiagnostics.shared.clear()
        RuntimeDiagnostics.shared.log(
            level: .info,
            category: "UnitTest",
            message: "before-seed-cleanup"
        )

        FlowTabTestLaunchOptions.argumentsOverrideForTesting = [
            "FlowTab",
            "--flowtab-ui-reset-defaults",
            "--flowtab-ui-runtime-log-level", "warn",
            "--flowtab-ui-seed-logs", "3",
            "--flowtab-ui-open-switcher-search"
        ]
        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: { panelController },
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: takeoverController,
            stressRunner: stressRunner
        )

        let appDelegate = AppDelegate()
        delegate = appDelegate
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        try? await Task.sleep(nanoseconds: 420_000_000)

        XCTAssertNil(userDefaults.object(forKey: AppPreferenceKeys.showShortcutHint))
        XCTAssertFalse(userDefaults.bool(forKey: CommandTabTakeoverController.takeoverMarkerKey))
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.runtimeLogLevel),
            RuntimeLogLevel.warning.rawValue
        )
        XCTAssertEqual(HomeTabState.shared.selectedTab, .home)
        XCTAssertEqual(stressRunner.startCallCount, 1)
        XCTAssertEqual(hotkeyFactory.records.map(\.signature), [0x46544142, 0x4654574E])
        XCTAssertTrue(panelController.modelForTesting.isSearchActive)
        XCTAssertNotNil(panelController.modelForTesting.session)

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 40, minimumLevel: .debug)
        XCTAssertFalse(lines.contains(where: { $0.contains("before-seed-cleanup") }))
        let seededLines = lines.filter { $0.contains("[UITest] seeded-") }
        XCTAssertEqual(seededLines.count, 3)
    }

    @MainActor
    func testAppDelegateLaunchOpenSwitcherWithoutResultsDoesNotEnterSearchAndSeedZeroSkipsSeededLogs() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let previousLaunchArguments = FlowTabTestLaunchOptions.argumentsOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let panelController = SwitcherPanelController()
        var delegate: AppDelegate?
        defer {
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            FlowTabTestLaunchOptions.argumentsOverrideForTesting = previousLaunchArguments
            RuntimeDiagnostics.shared.clear()
            clearIsolatedUserDefaults(userDefaults)
        }

        panelController.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: [], contextsByID: [:])
        }

        RuntimeDiagnostics.shared.clear()
        RuntimeDiagnostics.shared.log(
            level: .info,
            category: "UnitTest",
            message: "seed-zero-cleanup"
        )

        FlowTabTestLaunchOptions.argumentsOverrideForTesting = [
            "FlowTab",
            "--flowtab-ui-open-switcher",
            "--flowtab-ui-seed-logs", "0"
        ]
        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: { panelController },
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: SpyCommandTabTakeoverController(),
            stressRunner: SpyStressRunner()
        )

        let appDelegate = AppDelegate()
        delegate = appDelegate
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        try? await Task.sleep(nanoseconds: 420_000_000)

        XCTAssertNil(panelController.modelForTesting.session)
        XCTAssertFalse(panelController.modelForTesting.isSearchActive)
        XCTAssertEqual(hotkeyFactory.records.count, 2)

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 40, minimumLevel: .debug)
        XCTAssertFalse(lines.contains(where: { $0.contains("seed-zero-cleanup") }))
        XCTAssertFalse(lines.contains(where: { $0.contains("[UITest] seeded-") }))
    }

    @MainActor
    func testSwitcherPanelControllerInAppHotkeyReleaseCommitsFocusedWindowSession() async {
        let controller = SwitcherPanelController()
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "front-1", title: "Inbox", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "front-2", title: "Draft", isMinimized: false, lastActiveAt: 20)
        ]
        controller.modelForTesting.frontmostApplicationOverride = { currentApp }
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(
                apps: [
                    AppSwitchCandidate(
                        id: appID,
                        displayName: currentApp.localizedName ?? "Current App",
                        groupID: "current",
                        lastActiveAt: 100,
                        windows: windows
                    )
                ],
                contextsByID: [
                    appID: self.makeRuntimeAppContext(
                        appID: appID,
                        runningApp: currentApp,
                        windows: windows
                    )
                ]
            )
        }

        var activatedTarget: ActivationTarget?
        controller.modelForTesting.activationOverride = { target, _ in
            activatedTarget = target
        }

        XCTAssertTrue(controller.beginInAppWindowHotkeySessionForTesting())
        XCTAssertEqual(controller.modelForTesting.overlayStyle, .windowOnly)
        XCTAssertEqual(controller.modelForTesting.session?.mode, .windowCycle(appID: appID))
        let selectedWindowID = controller.modelForTesting.session?.selectedWindow?.id
        XCTAssertNotNil(selectedWindowID)

        controller.inAppPrimaryModifierPressedOverride = false
        controller.handleInAppWindowHotkeyReleased()

        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertEqual(
            activatedTarget,
            .window(
                appID: appID,
                windowID: selectedWindowID ?? "",
                restoreIfMinimized: false
            )
        )
    }

    @MainActor
    func testSwitcherPanelControllerGlobalHotkeyAdvanceAndReleaseCommitSession() async {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }

        var activatedTarget: ActivationTarget?
        controller.modelForTesting.activationOverride = { target, _ in
            activatedTarget = target
        }

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.globalPrimaryModifierPressedOverride = true
        let initialSelectedAppID = controller.modelForTesting.selectedApp?.id

        controller.handleGlobalHotkey(isBackward: false)

        XCTAssertNotEqual(controller.modelForTesting.selectedApp?.id, initialSelectedAppID)

        controller.globalPrimaryModifierPressedOverride = false
        controller.handleGlobalHotkeyReleased()

        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertNotNil(activatedTarget)
    }

    @MainActor
    func testSwitcherPanelControllerDownArrowInAppCycleEntersWindowLayer() {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        let selectedAppID = controller.modelForTesting.selectedApp?.id
        XCTAssertEqual(controller.modelForTesting.session?.mode, .appCycle)

        let handled = controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 125))

        XCTAssertTrue(handled)
        XCTAssertEqual(
            controller.modelForTesting.session?.mode,
            .windowCycle(appID: selectedAppID ?? "")
        )
        XCTAssertTrue(controller.modelForTesting.isPreviewLayerMode)
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerFlagsChangedReleaseConfirmationEndsSession() async {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.globalPrimaryModifierPressedOverride = false

        controller.handleFlagsChangedForTesting(
            Self.makeFlagsChangedEvent(keyCode: UInt16(kVK_Option))
        )

        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertNil(controller.modelForTesting.session)
    }

    @MainActor
    func testSwitcherPanelControllerMouseDownOutsideSearchCancelsSession() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let controller = SwitcherPanelController()
            controller.modelForTesting.snapshotProviderOverride = {
                RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
            }

            XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
            XCTAssertTrue(controller.modelForTesting.enterSearchMode())
            controller.panelContainsPointOverride = { _ in false }

            controller.handleGlobalMouseDownForTesting(location: .zero)

            XCTAssertNil(controller.modelForTesting.session)
        }
    }

    @MainActor
    func testSwitcherPanelControllerActiveSpaceChangeKeepsSessionVisibleWithoutReactivatingApp() async {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }
        controller.globalPrimaryModifierPressedOverride = true
        controller.appIsActiveOverride = false

        var activateCallCount = 0
        controller.activateApplicationIgnoringOtherAppsOverride = {
            activateCallCount += 1
        }

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.panelOcclusionStateOverride = []

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            controller.panelOcclusionStateOverride = .visible
        }

        controller.handleActiveSpaceDidChangeForTesting()

        try? await Task.sleep(nanoseconds: 220_000_000)
        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertEqual(activateCallCount, 0)
        XCTAssertFalse(controller.suppressHotkeyReplayUntilReleaseForTesting)
    }

    @MainActor
    func testSwitcherPanelControllerActiveSpaceNotificationKeepsSessionVisibleWithoutReactivatingApp() async {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }
        controller.globalPrimaryModifierPressedOverride = true
        controller.appIsActiveOverride = false

        var activateCallCount = 0
        controller.activateApplicationIgnoringOtherAppsOverride = {
            activateCallCount += 1
        }

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.panelOcclusionStateOverride = []

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            controller.panelOcclusionStateOverride = .visible
        }

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        try? await Task.sleep(nanoseconds: 260_000_000)
        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertEqual(activateCallCount, 0)
        XCTAssertFalse(controller.suppressHotkeyReplayUntilReleaseForTesting)
    }

    @MainActor
    func testSwitcherPanelControllerActiveSpaceNotificationCancelsSessionAfterModifierRelease() async {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }
        controller.globalPrimaryModifierPressedOverride = false
        controller.globalMainKeyPressedOverride = false

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        try? await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertTrue(controller.suppressHotkeyReplayUntilReleaseForTesting)

        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(controller.suppressHotkeyReplayUntilReleaseForTesting)
    }

    @MainActor
    func testSwitcherPanelControllerActiveSpaceChangeCancelsSessionAfterModifierRelease() async {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }
        controller.globalPrimaryModifierPressedOverride = false
        controller.globalMainKeyPressedOverride = false

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.handleActiveSpaceDidChangeForTesting()

        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertTrue(controller.suppressHotkeyReplayUntilReleaseForTesting)

        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(controller.suppressHotkeyReplayUntilReleaseForTesting)
    }

    @MainActor
    func testSwitcherPanelControllerRecoverableOcclusionKeepsSessionVisible() async {
        let occlusionController = SwitcherPanelController()
        occlusionController.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }
        occlusionController.globalPrimaryModifierPressedOverride = true

        XCTAssertTrue(occlusionController.beginGlobalHotkeySessionForTesting())
        occlusionController.panelOcclusionStateOverride = []

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            occlusionController.panelOcclusionStateOverride = .visible
        }

        occlusionController.handlePanelOcclusionStateDidChangeForTesting()

        try? await Task.sleep(nanoseconds: 220_000_000)
        XCTAssertNotNil(occlusionController.modelForTesting.session)
        XCTAssertFalse(occlusionController.suppressHotkeyReplayUntilReleaseForTesting)
    }

    @MainActor
    func testSwitcherPanelControllerSystemInterruptionsCancelSessionAndSuppressReplayUntilRelease() async {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }
        controller.globalPrimaryModifierPressedOverride = false
        controller.globalMainKeyPressedOverride = false

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.handleActiveSpaceDidChangeForTesting()

        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertTrue(controller.suppressHotkeyReplayUntilReleaseForTesting)

        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(controller.suppressHotkeyReplayUntilReleaseForTesting)

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.panelOcclusionStateOverride = []
        controller.handlePanelOcclusionStateDidChangeForTesting()

        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertTrue(controller.suppressHotkeyReplayUntilReleaseForTesting)

        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(controller.suppressHotkeyReplayUntilReleaseForTesting)

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.appIsActiveOverride = false
        controller.handlePanelDidResignKeyForTesting()

        XCTAssertNil(controller.modelForTesting.session)
    }

    @MainActor
    func testSwitcherPanelControllerDelayedAutoEnterWindowLayerTriggersAfterConfiguredDelay() async {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }
        controller.windowLayerPresentationDelayOverride = 0.01

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        XCTAssertEqual(controller.modelForTesting.session?.mode, .appCycle)

        controller.scheduleDelayedWindowLayerEntryForTesting()

        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(
            controller.modelForTesting.session?.mode,
            .windowCycle(appID: controller.modelForTesting.selectedApp?.id ?? "")
        )
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerDelayedAutoEnterWindowLayerUsesPreferenceDelay() async {
        await withTemporaryWindowLayerAutoEnterDelay(0.01) {
            let controller = SwitcherPanelController()
            controller.modelForTesting.snapshotProviderOverride = {
                RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
            }

            XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
            XCTAssertEqual(controller.modelForTesting.session?.mode, .appCycle)

            controller.scheduleDelayedWindowLayerEntryForTesting()

            try? await Task.sleep(nanoseconds: 80_000_000)
            XCTAssertEqual(
                controller.modelForTesting.session?.mode,
                .windowCycle(appID: controller.modelForTesting.selectedApp?.id ?? "")
            )
            controller.cancelSelectionForTesting()
        }
    }

    @MainActor
    func testSwitcherPanelControllerShowSkipsHidingRegularWindowsWhileAppIsActive() {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }
        controller.appIsActiveOverride = true

        var hideCallCount = 0
        controller.hideNonPanelWindowsOverride = {
            hideCallCount += 1
        }

        XCTAssertTrue(controller.presentGlobalHotkeySessionForTesting())
        XCTAssertEqual(hideCallCount, 0)

        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerShowStillHidesRegularWindowsWhileAppIsInactive() {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }
        controller.appIsActiveOverride = false

        var hideCallCount = 0
        controller.hideNonPanelWindowsOverride = {
            hideCallCount += 1
        }

        XCTAssertTrue(controller.presentGlobalHotkeySessionForTesting())
        XCTAssertEqual(hideCallCount, 1)

        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerFewAppsShrinkPanelWidthWithoutChangingSpacing() {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.layoutScenarioApps(count: 5), contextsByID: [:])
        }

        XCTAssertTrue(controller.modelForTesting.startSession(triggerDirection: .forward))

        controller.updatePanelSizeForTesting(
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(controller.modelForTesting.appGridTileSize, 90, accuracy: 0.001)
        XCTAssertEqual(controller.modelForTesting.appGridSpacing, 10, accuracy: 0.001)
        XCTAssertEqual(controller.panelContentSizeForTesting.width, 554, accuracy: 0.001)
    }

    @MainActor
    func testSwitcherPanelControllerManyAppsReduceTileSizeWhileKeepingSpacingConstant() {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.layoutScenarioApps(count: 20), contextsByID: [:])
        }

        XCTAssertTrue(controller.modelForTesting.startSession(triggerDirection: .forward))

        controller.updatePanelSizeForTesting(
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(controller.modelForTesting.appGridSpacing, 10, accuracy: 0.001)
        XCTAssertLessThan(controller.modelForTesting.appGridTileSize, 90)
        XCTAssertEqual(controller.panelContentSizeForTesting.width, 1360, accuracy: 0.001)
    }

    func testRuntimeSnapshotProviderAssemblySelectsPrimaryRowsAndFiltersMinimizedOnlyApps() {
        let rows = RuntimeSnapshotProvider.assembleSnapshotRowsForTesting(
            apps: [
                RuntimeSnapshotProvider.SnapshotAssemblyApp(
                    pid: 10,
                    bundleIdentifier: "com.example.mail",
                    localizedName: "Mail",
                    launchDate: Date(timeIntervalSince1970: 100)
                ),
                RuntimeSnapshotProvider.SnapshotAssemblyApp(
                    pid: 11,
                    bundleIdentifier: "com.example.mail",
                    localizedName: "Mail",
                    launchDate: Date(timeIntervalSince1970: 200)
                ),
                RuntimeSnapshotProvider.SnapshotAssemblyApp(
                    pid: 20,
                    bundleIdentifier: "com.example.chat",
                    localizedName: "Chat",
                    launchDate: Date(timeIntervalSince1970: 150)
                ),
                RuntimeSnapshotProvider.SnapshotAssemblyApp(
                    pid: 30,
                    bundleIdentifier: "com.example.notes",
                    localizedName: "Notes",
                    launchDate: Date(timeIntervalSince1970: 50)
                )
            ],
            windowsByPID: [
                10: [
                    RuntimeSnapshotProvider.SnapshotAssemblyWindow(
                        windowID: "mail-legacy",
                        title: "Inbox",
                        isMinimized: false,
                        cgWindowID: 10
                    )
                ],
                11: [
                    RuntimeSnapshotProvider.SnapshotAssemblyWindow(
                        windowID: "mail-1",
                        title: "Inbox",
                        isMinimized: false,
                        cgWindowID: 11
                    ),
                    RuntimeSnapshotProvider.SnapshotAssemblyWindow(
                        windowID: "mail-2",
                        title: "Draft",
                        isMinimized: false,
                        cgWindowID: 12
                    )
                ],
                20: [
                    RuntimeSnapshotProvider.SnapshotAssemblyWindow(
                        windowID: "chat-1",
                        title: "Standup",
                        isMinimized: true,
                        cgWindowID: 20
                    )
                ]
            ],
            rankByPID: [11: 0, 20: 1, 10: 2, 30: 3],
            hideMinimizedAppsFromAppLayer: true,
            now: 1_000
        )

        XCTAssertEqual(rows.map(\.pid), [11, 30])
        XCTAssertEqual(rows.first?.candidate.id, "com.example.mail")
        XCTAssertEqual(rows.first?.candidate.windows.map(\.id), ["mail-1", "mail-2"])
        XCTAssertEqual(rows.last?.candidate.id, "com.example.notes")
        XCTAssertTrue(rows.allSatisfy { $0.candidate.id != "com.example.chat" })
    }

    func testRuntimeSnapshotProviderAssemblyIncludesMinimizedAppsWhenFilterDisabledAndUsesFallbackGroup() {
        let rows = RuntimeSnapshotProvider.assembleSnapshotRowsForTesting(
            apps: [
                RuntimeSnapshotProvider.SnapshotAssemblyApp(
                    pid: 41,
                    bundleIdentifier: nil,
                    localizedName: "Zulu",
                    launchDate: Date(timeIntervalSince1970: 100)
                ),
                RuntimeSnapshotProvider.SnapshotAssemblyApp(
                    pid: 42,
                    bundleIdentifier: nil,
                    localizedName: "Alpha",
                    launchDate: Date(timeIntervalSince1970: 100)
                )
            ],
            windowsByPID: [
                41: [
                    RuntimeSnapshotProvider.SnapshotAssemblyWindow(
                        windowID: "z-1",
                        title: "Zulu Window",
                        isMinimized: true,
                        cgWindowID: 41
                    )
                ],
                42: [
                    RuntimeSnapshotProvider.SnapshotAssemblyWindow(
                        windowID: "a-1",
                        title: "Alpha Window",
                        isMinimized: true,
                        cgWindowID: 42
                    )
                ]
            ],
            rankByPID: [41: 5, 42: 5],
            hideMinimizedAppsFromAppLayer: false,
            now: 2_000
        )

        XCTAssertEqual(rows.map(\.pid), [42, 41])
        XCTAssertEqual(rows.map(\.candidate.groupID), ["a", "z"])
        XCTAssertTrue(rows.allSatisfy { $0.candidate.windows.first?.isMinimized == true })
    }

    func testRuntimeWindowPreviewProviderGuessesDarkLightAndUnknownTitleBars() {
        let darkImage = makeSolidPreviewCGImage(color: .black)
        let lightImage = makeSolidPreviewCGImage(color: .white)
        let noisyImage = makeStripedPreviewCGImage()

        XCTAssertEqual(
            RuntimeWindowPreviewProvider.guessTitleBarStyleForTesting(from: darkImage),
            .dark
        )
        XCTAssertEqual(
            RuntimeWindowPreviewProvider.guessTitleBarStyleForTesting(from: lightImage),
            .light
        )
        XCTAssertNil(RuntimeWindowPreviewProvider.guessTitleBarStyleForTesting(from: noisyImage))
    }

    func testRuntimeWindowPreviewProviderCandidateWindowOrderingForPreferredAndTitleMatches() {
        let candidateIDs = RuntimeWindowPreviewProvider.candidateWindowIDsForTesting(
            preferredWindowID: 3,
            preferredTitle: "Inbox",
            liveWindows: [
                .init(id: 1, title: "Inbox"),
                .init(id: 2, title: "inbox"),
                .init(id: 3, title: "Draft"),
                .init(id: 4, title: nil)
            ]
        )

        XCTAssertEqual(candidateIDs, [3, 1, 2, 4])
    }

    func testRuntimeWindowPreviewProviderOwnerPIDPathKeepsPreferredWindowFirst() {
        let preferredWindowID: CGWindowID = 777
        let candidateIDs = RuntimeWindowPreviewProvider.candidateWindowIDsForTesting(
            preferredWindowID: preferredWindowID,
            ownerPID: ProcessInfo.processInfo.processIdentifier,
            preferredTitle: "unlikely-title-\(UUID().uuidString)"
        )

        XCTAssertEqual(candidateIDs.first, preferredWindowID)
    }

    func testRuntimeWindowPreviewProviderScaledPreviewSizeAndImageDownscaleBehavior() {
        let largeSize = RuntimeWindowPreviewProvider.scaledPreviewSizeForTesting(
            sourceWidth: 2_400,
            sourceHeight: 1_200
        )
        XCTAssertEqual(largeSize.width, 1_200)
        XCTAssertEqual(largeSize.height, 600)

        let unchangedSize = RuntimeWindowPreviewProvider.scaledPreviewSizeForTesting(
            sourceWidth: 800,
            sourceHeight: 400
        )
        XCTAssertEqual(unchangedSize.width, 800)
        XCTAssertEqual(unchangedSize.height, 400)

        let minimalSize = RuntimeWindowPreviewProvider.scaledPreviewSizeForTesting(
            sourceWidth: 0.2,
            sourceHeight: 0.2
        )
        XCTAssertEqual(minimalSize.width, 1)
        XCTAssertEqual(minimalSize.height, 1)

        let largeImage = makeSolidPreviewCGImage(
            color: .systemTeal,
            size: CGSize(width: 2_000, height: 1_000)
        )
        let scaledImage = RuntimeWindowPreviewProvider.scaledPreviewImageIfNeededForTesting(largeImage)
        XCTAssertEqual(scaledImage?.width, 1_200)
        XCTAssertEqual(scaledImage?.height, 600)

        let smallImage = makeSolidPreviewCGImage(
            color: .systemOrange,
            size: CGSize(width: 600, height: 300)
        )
        let unchangedImage = RuntimeWindowPreviewProvider.scaledPreviewImageIfNeededForTesting(smallImage)
        XCTAssertEqual(unchangedImage?.width, 600)
        XCTAssertEqual(unchangedImage?.height, 300)
    }

    func testRuntimeSnapshotProviderGroupIDMappingCoversFallbackAndBundleShapes() {
        XCTAssertEqual(
            RuntimeSnapshotProvider.groupIDForTesting(
                bundleIdentifier: nil,
                fallbackName: "Notes"
            ),
            "n"
        )
        XCTAssertEqual(
            RuntimeSnapshotProvider.groupIDForTesting(
                bundleIdentifier: "com.example.mail",
                fallbackName: "Mail"
            ),
            "example"
        )
        XCTAssertEqual(
            RuntimeSnapshotProvider.groupIDForTesting(
                bundleIdentifier: "singleton",
                fallbackName: "Single"
            ),
            "singleton"
        )
        XCTAssertEqual(
            RuntimeSnapshotProvider.groupIDForTesting(
                bundleIdentifier: "",
                fallbackName: "Empty"
            ),
            "apps"
        )
    }

    func testRuntimeSnapshotProviderResolveCGWindowAssignmentsUsesGeometryWithDuplicateTitles() {
        let axWindows: [RuntimeSnapshotProvider.AXWindowEntryForTesting] = [
            .init(id: "ax:100:0", index: 0, bounds: CGRect(x: 10, y: 10, width: 600, height: 420)),
            .init(id: "ax:100:1", index: 1, bounds: CGRect(x: 640, y: 10, width: 600, height: 420))
        ]
        let cgWindows: [RuntimeSnapshotProvider.CGWindowEntryForTesting] = [
            .init(
                id: 22,
                title: "Document",
                bounds: CGRect(x: 640, y: 14, width: 600, height: 418)
            ),
            .init(
                id: 11,
                title: "Document",
                bounds: CGRect(x: 8, y: 8, width: 602, height: 420)
            )
        ]

        let assignments = RuntimeSnapshotProvider.resolveCGWindowAssignmentsForTesting(
            axWindows: axWindows,
            cgWindows: cgWindows
        )

        XCTAssertEqual(assignments["ax:100:0"], 11)
        XCTAssertEqual(assignments["ax:100:1"], 22)
    }

    func testRuntimeSnapshotProviderResolveCGWindowAssignmentsSkipsAmbiguousOrLowConfidenceMatches() {
        let axWindows: [RuntimeSnapshotProvider.AXWindowEntryForTesting] = [
            .init(id: "ax:200:2", index: 2, bounds: CGRect(x: 100, y: 100, width: 800, height: 500)),
            .init(id: "ax:200:0", index: 0, bounds: nil)
        ]
        let cgWindows: [RuntimeSnapshotProvider.CGWindowEntryForTesting] = [
            .init(id: 1, title: nil, bounds: CGRect(x: 100, y: 100, width: 800, height: 500)),
            .init(id: 2, title: nil, bounds: CGRect(x: 100, y: 100, width: 800, height: 500)),
            .init(id: 3, title: nil, bounds: CGRect(x: 100, y: 100, width: 800, height: 500)),
            .init(id: 4, title: nil, bounds: CGRect(x: 100, y: 100, width: 800, height: 500)),
            .init(id: 5, title: nil, bounds: CGRect(x: 100, y: 100, width: 800, height: 500))
        ]

        let assignments = RuntimeSnapshotProvider.resolveCGWindowAssignmentsForTesting(
            axWindows: axWindows,
            cgWindows: cgWindows
        )

        XCTAssertNil(assignments["ax:200:2"], "Ambiguous high-score windows should remain unbound")
        XCTAssertNil(assignments["ax:200:0"], "Low-confidence windows should remain unbound")
    }

    func testAXWindowInspectorHelpersRoundTripWindowIDsAndHandleSystemElementLookups() {
        let windowID = AXWindowInspectorForTesting.makeWindowID(pid: 123, index: 7)
        XCTAssertEqual(windowID, "ax:123:7")
        XCTAssertEqual(AXWindowInspectorForTesting.windowIndex(from: windowID, expectedPID: 123), 7)
        XCTAssertNil(AXWindowInspectorForTesting.windowIndex(from: "invalid", expectedPID: 123))
        XCTAssertNil(AXWindowInspectorForTesting.windowIndex(from: "ax:999:7", expectedPID: 123))
        XCTAssertEqual(AXWindowInspectorForTesting.fallbackTitle(index: 0), "Window #1")

        let systemElement = AXUIElementCreateSystemWide()
        let role = AXWindowInspectorForTesting.role(for: systemElement)
        let isSwitchable = AXWindowInspectorForTesting.isSwitchable(systemElement)
        if let role {
            XCTAssertEqual(isSwitchable, role == kAXWindowRole as String)
        } else {
            XCTAssertTrue(isSwitchable)
        }
        XCTAssertFalse(AXWindowInspectorForTesting.isMinimized(systemElement))

        if let title = AXWindowInspectorForTesting.title(for: systemElement) {
            XCTAssertFalse(title.isEmpty)
        }
    }

    @MainActor
    func testLiveSwitcherModelWindowPreviewUsesCaptureCacheAcrossReads() {
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
                    )
                ],
                contextsByID: [appID: context]
            )
        }

        var captureCallCount = 0
        model.previewCaptureOverride = { _, _, title, _ in
            captureCallCount += 1
            let imageColor: NSColor = title == "Inbox" ? .black : .white
            let titleBarStyle: WindowTitleBarStyleGuess = title == "Inbox" ? .dark : .light
            return (
                image: self.makeColorImage(color: imageColor),
                resolvedWindowID: CGWindowID(captureCallCount),
                titleBarStyle: titleBarStyle
            )
        }

        XCTAssertTrue(model.startFocusedAppWindowSession(triggerDirection: .forward))

        let firstSnapshot = model.windowPreviewSnapshotForTesting()
        let secondSnapshot = model.windowPreviewSnapshotForTesting()

        XCTAssertEqual(captureCallCount, 2)
        XCTAssertEqual(firstSnapshot.count, 2)
        XCTAssertTrue(firstSnapshot.allSatisfy { $0.hasImage })
        XCTAssertEqual(
            firstSnapshot.first(where: { $0.id == "front-1" })?.titleBarStyle,
            .dark
        )
        XCTAssertEqual(
            secondSnapshot.first(where: { $0.id == "front-2" })?.titleBarStyle,
            .light
        )
    }

    func testBoundedImageCacheStoresAndClearsImages() {
        let cache = BoundedImageCache(countLimit: 4, totalCostLimit: 1_024 * 1_024)
        let image = makeColorImage(color: .systemBlue)

        cache.insert(image, forKey: "mail")

        XCTAssertNotNil(cache.image(forKey: "mail"))

        cache.removeAll()

        XCTAssertNil(cache.image(forKey: "mail"))
    }

    func testBoundedImageCacheHandlesImagesWithoutBitmapRepresentations() {
        let cache = BoundedImageCache(countLimit: 4, totalCostLimit: 1_024 * 1_024)
        let vectorOnlyImage = NSImage(size: NSSize(width: 19.2, height: 7.8))

        cache.insert(vectorOnlyImage, forKey: "vector")

        XCTAssertNotNil(cache.image(forKey: "vector"))
    }

    func testAppIconProviderCachesResolvedIconsAndMemoizesMissingApps() {
        let cache = BoundedImageCache(countLimit: 8, totalCostLimit: 1_024 * 1_024)
        var requestedAppIDs: [String] = []
        var requestedIconPaths: [String] = []
        let provider = AppIconProvider(
            cache: cache,
            applicationURLProvider: { appID in
                requestedAppIDs.append(appID)
                if appID == "com.example.present" {
                    return URL(fileURLWithPath: "/Applications/Present.app")
                }
                return nil
            },
            fileIconProvider: { path in
                requestedIconPaths.append(path)
                return self.makeColorImage(color: .systemGreen)
            }
        )

        let presentApp = AppSwitchCandidate(
            id: "com.example.present",
            displayName: "Present",
            groupID: "present",
            lastActiveAt: 10,
            windows: []
        )
        let missingApp = AppSwitchCandidate(
            id: "com.example.missing",
            displayName: "Missing",
            groupID: "missing",
            lastActiveAt: 5,
            windows: []
        )

        let firstIcon = provider.icon(for: presentApp, context: nil)
        let secondIcon = provider.icon(for: presentApp, context: nil)

        XCTAssertNotNil(firstIcon)
        if let firstIcon, let secondIcon {
            XCTAssertTrue(firstIcon === secondIcon)
        } else {
            XCTFail("Expected cached icon for present app")
        }
        XCTAssertEqual(requestedAppIDs.filter { $0 == "com.example.present" }.count, 1)
        XCTAssertEqual(requestedIconPaths, ["/Applications/Present.app"])

        XCTAssertNil(provider.icon(for: missingApp, context: nil))
        XCTAssertNil(provider.icon(for: missingApp, context: nil))
        XCTAssertEqual(requestedAppIDs.filter { $0 == "com.example.missing" }.count, 1)
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

    private func searchWrapScenarioApps() -> [AppSwitchCandidate] {
        return (1...10).map { item in
            let suffix = String(format: "%02d", item)
            let rank = 501 - item
            return AppSwitchCandidate(
                id: "com.flowtab.mock.wrap.\(suffix)",
                displayName: "Mock Wrap \(suffix)",
                groupID: "mock",
                lastActiveAt: TimeInterval(rank),
                windows: [
                    WindowCandidate(
                        id: "mock-wrap-\(suffix)-primary",
                        title: "MockWrap\(suffix)Window",
                        isMinimized: false,
                        lastActiveAt: TimeInterval(rank)
                    )
                ]
            )
        }
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

    private func layoutScenarioApps(count: Int) -> [AppSwitchCandidate] {
        (0..<count).map { index in
            let suffix = index + 1
            return AppSwitchCandidate(
                id: "com.example.layout-\(suffix)",
                displayName: "Layout \(suffix)",
                groupID: "layout",
                lastActiveAt: TimeInterval(1_000 - index),
                windows: [
                    WindowCandidate(
                        id: "layout-window-\(suffix)",
                        title: "Window \(suffix)",
                        isMinimized: false,
                        lastActiveAt: TimeInterval(1_000 - index)
                    )
                ]
            )
        }
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

    private func withTemporaryWindowLayerAutoEnterDelay(
        _ delay: Double,
        perform body: () async throws -> Void
    ) async rethrows {
        let defaults = UserDefaults.standard
        let previousDelay = defaults.object(forKey: AppPreferenceKeys.windowLayerAutoEnterDelay)
        defaults.set(delay, forKey: AppPreferenceKeys.windowLayerAutoEnterDelay)
        defer {
            restoreUserDefaultsValue(
                previousDelay,
                forKey: AppPreferenceKeys.windowLayerAutoEnterDelay,
                userDefaults: defaults
            )
        }
        try await body()
    }

    private func makeCarbonHotkeyEvent(
        kind: UInt32,
        signature: OSType,
        id: UInt32,
        includeHotkeyPayload: Bool
    ) -> EventRef {
        var eventRef: EventRef?
        let createStatus = CreateEvent(
            nil,
            OSType(kEventClassKeyboard),
            kind,
            EventTime(0),
            EventAttributes(kEventAttributeNone),
            &eventRef
        )
        XCTAssertEqual(createStatus, noErr)
        guard let eventRef else {
            fatalError("Failed to create Carbon event for tests")
        }

        if includeHotkeyPayload {
            var hotkeyID = EventHotKeyID(signature: signature, id: id)
            let payloadStatus = withUnsafePointer(to: &hotkeyID) { pointer in
                SetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    MemoryLayout<EventHotKeyID>.size,
                    pointer
                )
            }
            XCTAssertEqual(payloadStatus, noErr)
        }
        return eventRef
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

    private static func makeFlagsChangedEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .flagsChanged,
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
            fatalError("Failed to create flagsChanged event for tests")
        }
        return event
    }

    private func makeColorImage(
        color: NSColor,
        size: NSSize = NSSize(width: 48, height: 48)
    ) -> NSImage {
        let cgImage = makeSolidPreviewCGImage(
            color: color,
            size: CGSize(width: size.width, height: size.height)
        )
        return NSImage(cgImage: cgImage, size: size)
    }

    private func makeSolidPreviewCGImage(
        color: NSColor,
        size: CGSize = CGSize(width: 180, height: 120)
    ) -> CGImage {
        makePreviewCGImage(size: size) { context in
            context.setFillColor(color.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeStripedPreviewCGImage(
        size: CGSize = CGSize(width: 180, height: 120)
    ) -> CGImage {
        makePreviewCGImage(size: size) { context in
            let stripeWidth: CGFloat = 10
            var x: CGFloat = 0
            var useRed = true
            while x < size.width {
                context.setFillColor((useRed ? NSColor.systemRed : NSColor.systemBlue).cgColor)
                context.fill(CGRect(x: x, y: 0, width: stripeWidth, height: size.height))
                useRed.toggle()
                x += stripeWidth
            }
        }
    }

    private func makePreviewCGImage(
        size: CGSize,
        draw: (CGContext) -> Void
    ) -> CGImage {
        guard
            let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            fatalError("Failed to create bitmap context for preview tests")
        }

        draw(context)

        guard let image = context.makeImage() else {
            fatalError("Failed to create CGImage for preview tests")
        }
        return image
    }
}

private final class SpyHotkeyMonitor: HotkeyMonitoring {
    var onHotkeyPressed: ((Bool) -> Void)?
    var onHotkeyReleased: ((Bool) -> Void)?

    private(set) var stopCallCount = 0

    func stop() {
        stopCallCount += 1
    }
}

private struct SpyHotkeyMonitorRecord {
    let configuration: SwitcherHotkeyConfiguration
    let signature: OSType
    let forwardHotkeyID: UInt32
    let backwardHotkeyID: UInt32
    let monitor: SpyHotkeyMonitor
}

private final class SpyHotkeyMonitorFactory {
    private(set) var records: [SpyHotkeyMonitorRecord] = []

    func make(
        configuration: SwitcherHotkeyConfiguration,
        signature: OSType,
        forwardHotkeyID: UInt32,
        backwardHotkeyID: UInt32
    ) -> any HotkeyMonitoring {
        let monitor = SpyHotkeyMonitor()
        records.append(
            SpyHotkeyMonitorRecord(
                configuration: configuration,
                signature: signature,
                forwardHotkeyID: forwardHotkeyID,
                backwardHotkeyID: backwardHotkeyID,
                monitor: monitor
            )
        )
        return monitor
    }
}

private final class SpyCommandTabTakeoverController: CommandTabTakeoverControlling {
    private(set) var reconcileCalls: [Bool] = []
    private(set) var restoreCallCount = 0
    var reconcileResult = true

    func reconcileIfNeeded(shouldTakeOver: Bool) -> Bool {
        reconcileCalls.append(shouldTakeOver)
        return reconcileResult
    }

    func restoreSystemShortcutsIfNeeded() {
        restoreCallCount += 1
    }
}

@MainActor
private final class SpyStressRunner: TabSwitchStressRunning {
    private(set) var startCallCount = 0

    func startIfNeeded() {
        startCallCount += 1
    }
}

private final class SpyMRUTracker: MRUTracking {
    private(set) var startCallCount = 0

    func startIfNeeded() {
        startCallCount += 1
    }
}
