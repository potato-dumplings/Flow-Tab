import AppKit
import Carbon
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testLiveSwitcherModelStartSessionLoadsProjectionAndCommitActivatesPreferredTarget() {
        let model = LiveSwitcherModel(
            runtimeProjectionService: RecordingRuntimeProjectionService(
                appSwitcherApps: commitScenarioApps()
            )
        )

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
            let runtimeProjectionService = RecordingRuntimeProjectionService(
                appSwitcherApps: self.searchScenarioApps(),
                committedSearchReadiness: .committedGenerationValidated
            )
            let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

            XCTAssertTrue(model.startSession(triggerDirection: .forward))
            XCTAssertTrue(model.enterSearchMode())
            assertCommittedSearchIndexRead(model, from: runtimeProjectionService)
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
            let runtimeProjectionService = RecordingRuntimeProjectionService(
                appSwitcherApps: self.searchScenarioApps(),
                committedSearchReadiness: .committedGenerationValidated
            )
            let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

            XCTAssertTrue(model.startSession(triggerDirection: .forward))
            XCTAssertTrue(model.enterSearchMode())
            assertCommittedSearchIndexRead(model, from: runtimeProjectionService)
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
            let runtimeProjectionService = RecordingRuntimeProjectionService(
                appSwitcherApps: self.searchScenarioApps(),
                committedSearchReadiness: .committedGenerationValidated
            )
            let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

            XCTAssertTrue(model.startSession(triggerDirection: .forward))
            XCTAssertTrue(model.enterSearchMode())
            assertCommittedSearchIndexRead(model, from: runtimeProjectionService)
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

    @MainActor
    func testLiveSwitcherModelWindowSearchCommitActivatesSelectedWindowTarget() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .window) {
            let apps = self.searchScenarioApps()
            let contextsByID = Dictionary(
                uniqueKeysWithValues: apps.map { app in
                    (
                        app.id,
                        self.makeRuntimeAppContext(
                            appID: app.id,
                            runningApp: NSRunningApplication.current,
                            windows: app.windows
                        )
                    )
                }
            )
            let runtimeProjectionService = RecordingRuntimeProjectionService(
                appSwitcherApps: apps,
                contextsByID: contextsByID,
                committedSearchReadiness: .committedGenerationValidated
            )
            let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

            var activatedTarget: ActivationTarget?
            var activatedContextIDs: Set<String> = []
            model.activationOverride = { target, contextsByID in
                activatedTarget = target
                activatedContextIDs = Set(contextsByID.keys)
            }

            XCTAssertTrue(model.startSession(triggerDirection: .forward))
            XCTAssertTrue(model.enterSearchMode())
            assertCommittedSearchIndexRead(model, from: runtimeProjectionService)
            XCTAssertTrue(
                model.searchCoordinator.replaceQueryWithoutRebuild(
                    "README",
                    cursorPosition: "README".count
                )
            )
            model.searchCoordinator.rebuildResults(resetSelection: true)
            model.publishSearchStateIfNeeded()

            XCTAssertEqual(
                model.searchViewState.selectedResult?.kind,
                .window(appID: "com.example.code", windowID: "code-2")
            )
            XCTAssertTrue(model.applySelectedSearchResultToSession())
            XCTAssertEqual(model.session?.selectedWindow?.id, "code-2")

            model.commitSelection()

            XCTAssertEqual(
                activatedTarget,
                .window(appID: "com.example.code", windowID: "code-2", restoreIfMinimized: false)
            )
            XCTAssertEqual(activatedContextIDs, Set(apps.map(\.id)))
            XCTAssertNil(model.session)
            XCTAssertFalse(model.isSearchActive)
        }
    }

    @MainActor
    func testSwitcherPanelControllerPointerAppSelectionRequiresPointerMovement() {
        let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherApps: searchScenarioApps())
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        )

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        assertAppSwitcherProjectionSessionRead(from: runtimeProjectionService)
        let initialSelectedAppID = controller.modelForTesting.selectedApp?.id

        controller.pointerSelectionGate.reset(currentLocation: .zero)
        controller.selectSwitcherAppByPointer(appID: "com.example.mail", currentLocation: .zero)

        XCTAssertEqual(controller.modelForTesting.selectedApp?.id, initialSelectedAppID)

        controller.selectSwitcherAppByPointer(appID: "com.example.mail", currentLocation: CGPoint(x: 2, y: 0))

        XCTAssertEqual(controller.modelForTesting.selectedApp?.id, "com.example.mail")
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerPointerWindowSelectionUsesWindowOnlySession() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "front-1", title: "Primary", isMinimized: false, lastActiveAt: 300),
            WindowCandidate(id: "front-2", title: "Secondary", isMinimized: false, lastActiveAt: 290)
        ]
        let runtimeProjectionService = makeCurrentAppWindowProjectionService(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        )
        controller.modelForTesting.frontmostApplicationOverride = { currentApp }

        XCTAssertTrue(controller.beginInAppWindowHotkeySessionForTesting())
        assertCurrentAppWindowProjectionRead(appID: appID, from: runtimeProjectionService)
        let initialSelectedWindowID = controller.modelForTesting.session?.selectedWindow?.id
        controller.pointerSelectionGate.reset(currentLocation: .zero)

        controller.selectSwitcherWindowByPointer(
            appID: appID,
            windowID: "front-2",
            currentLocation: .zero
        )

        XCTAssertEqual(controller.modelForTesting.session?.selectedWindow?.id, initialSelectedWindowID)

        controller.selectSwitcherWindowByPointer(
            appID: appID,
            windowID: "front-2",
            currentLocation: CGPoint(x: 2, y: 0)
        )

        XCTAssertEqual(controller.modelForTesting.session?.mode, .windowCycle(appID: appID))
        XCTAssertEqual(controller.modelForTesting.session?.selectedWindow?.id, "front-2")
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerPointerSearchResultSelectionFocusesResults() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService: RecordingRuntimeProjectionService(
                        appSwitcherApps: self.searchScenarioApps()
                    )
                )
            )

            XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
            XCTAssertTrue(controller.enterSearchModeIfPossible())
            XCTAssertTrue(controller.modelForTesting.isSearchInputFocused)

            controller.pointerSelectionGate.reset(currentLocation: .zero)
            controller.selectSwitcherSearchResultByPointer(
                resultID: "app:com.example.browser",
                currentLocation: .zero
            )

            XCTAssertTrue(controller.modelForTesting.isSearchInputFocused)

            controller.selectSwitcherSearchResultByPointer(
                resultID: "app:com.example.browser",
                currentLocation: CGPoint(x: 2, y: 0)
            )

            XCTAssertFalse(controller.modelForTesting.isSearchInputFocused)
            XCTAssertEqual(
                controller.modelForTesting.searchViewState.selectedResult?.kind,
                .app(appID: "com.example.browser")
            )
            controller.cancelSelectionForTesting()
        }
    }

    @MainActor
    func testSwitcherPanelControllerPointerAppClickCommitsImmediatelyWithoutPointerMovement() {
        let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherApps: searchScenarioApps())
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        )
        var activatedTarget: ActivationTarget?
        controller.modelForTesting.activationOverride = { target, _ in
            activatedTarget = target
        }

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        assertAppSwitcherProjectionSessionRead(from: runtimeProjectionService)
        controller.pointerSelectionGate.reset(currentLocation: .zero)

        controller.commitSwitcherAppByPointerClick(appID: "com.example.browser")

        XCTAssertEqual(
            activatedTarget,
            .window(appID: "com.example.browser", windowID: "browser-1", restoreIfMinimized: false)
        )
        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertFalse(controller.modelForTesting.isSearchActive)
        XCTAssertFalse(controller.isPanelPresented)
    }

    @MainActor
    func testSwitcherPanelControllerPointerWindowClickCommitsImmediatelyWithoutPointerMovement() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "front-1", title: "Primary", isMinimized: false, lastActiveAt: 300),
            WindowCandidate(id: "front-2", title: "Secondary", isMinimized: false, lastActiveAt: 290)
        ]
        let runtimeProjectionService = makeCurrentAppWindowProjectionService(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        )
        controller.modelForTesting.frontmostApplicationOverride = { currentApp }
        var activatedTarget: ActivationTarget?
        controller.modelForTesting.activationOverride = { target, _ in
            activatedTarget = target
        }

        XCTAssertTrue(controller.beginInAppWindowHotkeySessionForTesting())
        assertCurrentAppWindowProjectionRead(appID: appID, from: runtimeProjectionService)
        controller.pointerSelectionGate.reset(currentLocation: .zero)

        controller.commitSwitcherWindowByPointerClick(appID: appID, windowID: "front-2")

        XCTAssertEqual(
            activatedTarget,
            .window(appID: appID, windowID: "front-2", restoreIfMinimized: false)
        )
        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertFalse(controller.modelForTesting.isSearchActive)
        XCTAssertFalse(controller.isPanelPresented)
    }

    @MainActor
    func testSwitcherPanelControllerPointerSearchResultClickCommitsImmediatelyWithoutPointerMovement() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService: RecordingRuntimeProjectionService(
                        appSwitcherApps: self.searchScenarioApps()
                    )
                )
            )
            var activatedTarget: ActivationTarget?
            controller.modelForTesting.activationOverride = { target, _ in
                activatedTarget = target
            }

            XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
            XCTAssertTrue(controller.enterSearchModeIfPossible())
            controller.pointerSelectionGate.reset(currentLocation: .zero)

            controller.commitSwitcherSearchResultByPointerClick(resultID: "app:com.example.browser")

            XCTAssertEqual(
                activatedTarget,
                .window(appID: "com.example.browser", windowID: "browser-1", restoreIfMinimized: false)
            )
            XCTAssertNil(controller.modelForTesting.session)
            XCTAssertFalse(controller.modelForTesting.isSearchActive)
            XCTAssertFalse(controller.isPanelPresented)
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
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService: RecordingRuntimeProjectionService(
                        appSwitcherApps: self.searchScenarioApps()
                    )
                )
            )

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
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService: RecordingRuntimeProjectionService(
                        appSwitcherApps: self.searchScenarioApps()
                    )
                )
            )

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
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService: RecordingRuntimeProjectionService(
                        appSwitcherApps: self.searchWrapScenarioApps()
                    )
                )
            )

            var scrollRequests: [String] = []
            controller.modelForTesting.onSearchResultScrollRequestForTesting = { resultID in
                scrollRequests.append(resultID)
            }

            XCTAssertTrue(controller.presentGlobalHotkeySessionForTesting())
            XCTAssertTrue(controller.modelForTesting.enterSearchMode())
            controller.updatePanelSizeForTesting(
                visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
            )
            let didLoadSearchResults = await waitUntil("search results available after entering search mode") {
                controller.modelForTesting.searchResultCount > 0
            }
            XCTAssertTrue(didLoadSearchResults)

            guard let firstResultID = controller.modelForTesting.searchViewState.results.first?.id else {
                XCTFail("Expected search results after entering search mode")
                controller.cancelSelectionForTesting()
                return
            }

            XCTAssertTrue(controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 125)))

            let moveCountToLastResult = max(0, controller.modelForTesting.searchResultCount - 1)
            for _ in 0..<moveCountToLastResult {
                XCTAssertTrue(controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 125)))
            }

            XCTAssertEqual(
                controller.modelForTesting.searchViewState.selectedResultIndex,
                controller.modelForTesting.searchResultCount - 1
            )

            XCTAssertTrue(controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 125)))
            let didWrapToFirstResult = await waitUntil("search wrap scroll request returns to first result") {
                controller.modelForTesting.searchViewState.selectedResultIndex == 0
                    && scrollRequests.last == firstResultID
            }
            XCTAssertTrue(didWrapToFirstResult)

            XCTAssertEqual(controller.modelForTesting.searchViewState.selectedResultIndex, 0)
            XCTAssertEqual(scrollRequests.last, firstResultID)
            controller.cancelSelectionForTesting()
        }
    }

    @MainActor
    func testSwitcherPanelControllerSearchSizingUsesCompleteVisibleRowBudget() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService: RecordingRuntimeProjectionService(
                        appSwitcherApps: self.layoutScenarioApps(count: 10)
                    )
                )
            )

            XCTAssertTrue(controller.modelForTesting.startSession(triggerDirection: .forward))
            XCTAssertTrue(controller.modelForTesting.enterSearchMode())
            XCTAssertEqual(controller.modelForTesting.searchResultCount, 10)
            let measuredLayout = SwitcherSearchLayoutMeasurements(
                presentationHeaderHeight: 54,
                resultRowHeight: 48
            )
            controller.modelForTesting.updateSearchLayoutMeasurements(measuredLayout)

            controller.updatePanelSizeForTesting(
                visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
            )

            let visibleRows = SwitcherPanelLayoutMetrics.Search.visibleRowCount(
                for: controller.modelForTesting.searchResultCount
            )
            let expectedHeight = SwitcherPanelLayoutMetrics.Search.panelHeight(
                visibleRowCount: visibleRows,
                measurements: measuredLayout
            )

            XCTAssertEqual(
                controller.panelContentSizeForTesting.height,
                expectedHeight,
                accuracy: 0.001
            )
            controller.cancelSelectionForTesting()
        }
    }

    @MainActor
    func testSwitcherPanelControllerSearchEntryExpandsBelowCenteredAppLayer() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService: RecordingRuntimeProjectionService(
                        appSwitcherApps: self.layoutScenarioApps(count: 10)
                    )
                )
            )
            let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

            XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
            controller.updatePanelSizeForTesting(visibleFrame: visibleFrame)
            controller.centerPanelOnActiveScreen()
            let appLayerFrame = controller.panel.frame
            guard let screenCenterY = (controller.panel.screen ?? NSScreen.main)?.frame.midY else {
                XCTFail("Expected a screen for switcher panel placement")
                return
            }

            XCTAssertTrue(controller.enterSearchModeIfPossible())
            let searchFrame = controller.panel.frame

            XCTAssertEqual(searchFrame.width, appLayerFrame.width, accuracy: 0.001)
            XCTAssertGreaterThan(searchFrame.height, appLayerFrame.height)
            XCTAssertEqual(appLayerFrame.midY, screenCenterY, accuracy: 0.5)
            XCTAssertEqual(searchFrame.maxY, appLayerFrame.maxY, accuracy: 0.5)
            XCTAssertLessThan(searchFrame.minY, appLayerFrame.minY)
            controller.cancelSelectionForTesting()
        }
    }

    @MainActor
    func testSwitcherPanelControllerSearchHeightChangeKeepsPresentedPanelAnchoredAtTop() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService: RecordingRuntimeProjectionService(
                        appSwitcherApps: self.layoutScenarioApps(count: 10)
                    )
                )
            )

            XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
            XCTAssertTrue(controller.enterSearchModeIfPossible())
            controller.modelForTesting.updateSearchLayoutMeasurements(
                SwitcherSearchLayoutMeasurements(
                    presentationHeaderHeight: 54,
                    resultRowHeight: 48
                )
            )
            let initialSearchFrame = controller.panel.frame

            controller.modelForTesting.updateSearchLayoutMeasurements(
                SwitcherSearchLayoutMeasurements(
                    presentationHeaderHeight: 64,
                    resultRowHeight: 56
                )
            )
            let expandedSearchFrame = controller.panel.frame

            XCTAssertEqual(expandedSearchFrame.width, initialSearchFrame.width, accuracy: 0.001)
            XCTAssertGreaterThan(expandedSearchFrame.height, initialSearchFrame.height)
            XCTAssertEqual(expandedSearchFrame.maxY, initialSearchFrame.maxY, accuracy: 0.5)
            controller.cancelSelectionForTesting()
        }
    }

    @MainActor
    func testSwitcherPanelControllerSearchEnterAppliesSelectionAndEscapeExitsSearch() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService: RecordingRuntimeProjectionService(
                        appSwitcherApps: self.searchScenarioApps()
                    )
                )
            )

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
    func testLiveSwitcherModelStartFocusedAppWindowSessionUsesCurrentAppProjection() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "front-1", title: "Inbox", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "front-2", title: "Draft", isMinimized: false, lastActiveAt: 20)
        ]
        let runtimeProjectionService = makeCurrentAppWindowProjectionService(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        model.frontmostApplicationOverride = { currentApp }

        XCTAssertTrue(model.startFocusedAppWindowSession(triggerDirection: .forward))
        assertCurrentAppWindowProjectionRead(appID: appID, from: runtimeProjectionService)
        XCTAssertEqual(model.overlayStyle, .windowOnly)
        XCTAssertTrue(model.isPreviewLayerMode)
        XCTAssertEqual(model.previewWindowCount, 2)
        XCTAssertEqual(model.selectedApp?.id, appID)
        XCTAssertEqual(model.session?.mode, .windowCycle(appID: appID))
    }

    @MainActor
    func testLiveSwitcherModelAutoEnterWindowLayerSuppressesImmediateReentryAfterManualExit() {
        let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherApps: searchScenarioApps())
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        assertAppSwitcherProjectionSessionRead(from: runtimeProjectionService)
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
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService: RecordingRuntimeProjectionService(
                        appSwitcherApps: self.searchScenarioApps()
                    )
                )
            )

            XCTAssertTrue(controller.modelForTesting.startSession(triggerDirection: .forward))

            let handled = controller.handleKeyDownForTesting(Self.makeKeyDownEvent(keyCode: 36))

            XCTAssertTrue(handled)
            XCTAssertTrue(controller.modelForTesting.isSearchActive)
            XCTAssertNotNil(controller.modelForTesting.session)
            XCTAssertTrue(controller.modelForTesting.isSearchInputFocused)
        }
    }

    @MainActor
    func testUITestSearchLaunchUsesControllerSearchSizingPath() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let previousLaunchArguments = FlowTabTestLaunchOptions.argumentsOverrideForTesting
            let previousLaunchEnvironment = FlowTabTestLaunchOptions.environmentOverrideForTesting
            FlowTabTestLaunchOptions.argumentsOverrideForTesting = [
                "--flowtab-ui-open-switcher-search"
            ]
            FlowTabTestLaunchOptions.environmentOverrideForTesting = [
                FlowTabTestLaunchOptions.uiTestingEnvironmentKey:
                    FlowTabTestLaunchOptions.uiTestingEnvironmentValue
            ]
            defer {
                FlowTabTestLaunchOptions.argumentsOverrideForTesting = previousLaunchArguments
                FlowTabTestLaunchOptions.environmentOverrideForTesting = previousLaunchEnvironment
            }

            let apps = searchScenarioApps()
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService: RecordingRuntimeProjectionService(
                        appSwitcherApps: apps
                    )
                )
            )

            FlowTabUITestBootstrapper.presentInitialUIIfNeeded(panelController: controller)

            let expectedSearchHeight = {
                SwitcherPanelLayoutMetrics.Search.panelHeight(
                    visibleRowCount: SwitcherPanelLayoutMetrics.Search.visibleRowCount(
                        for: apps.count
                    ),
                    measurements: controller.modelForTesting.searchLayoutMeasurements
                )
            }
            let didReachExpectedSearchHeight = await waitUntil("initial UI search sizing reaches expected height") {
                controller.modelForTesting.isSearchActive
                    && abs(controller.panelContentSizeForTesting.height - expectedSearchHeight()) <= 1
            }
            XCTAssertTrue(didReachExpectedSearchHeight)

            XCTAssertTrue(controller.modelForTesting.isSearchActive)
            XCTAssertEqual(
                controller.panelContentSizeForTesting.height,
                expectedSearchHeight(),
                accuracy: 1
            )
            controller.cancelSelectionForTesting()
        }
    }

    @MainActor
    func testSwitcherPanelControllerMarkedTextPassesSearchShortcutKeysThrough() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService: RecordingRuntimeProjectionService(
                        appSwitcherApps: self.searchScenarioApps()
                    )
                )
            )

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
        let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherApps: terminateScenarioApps())
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        )
        controller.modelForTesting.terminateRequestOverride = { _ in
            (sent: true, pid: 42_100)
        }
        controller.modelForTesting.isProcessRunningOverride = { _ in true }

        XCTAssertTrue(controller.modelForTesting.startSession(triggerDirection: .forward))
        assertAppSwitcherProjectionSessionRead(from: runtimeProjectionService)
        let selectedAppID = controller.modelForTesting.selectedApp?.id
        let hotkeyConfiguration = SwitcherHotkeyPreferencesStore.load()

        let handled = controller.handleKeyDownForTesting(
            Self.makeKeyDownEvent(
                keyCode: hotkeyConfiguration.quitKeyCode,
                modifierFlags: hotkeyConfiguration.primaryModifier.eventModifierFlag
            )
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.modelForTesting.terminatingAppID, selectedAppID)
        XCTAssertNotNil(controller.modelForTesting.session)
        controller.modelForTesting.cancelSelection()
    }

    @MainActor
    func testSwitcherPanelControllerQuitFrontmostAppInAppLayerKeepsSessionAfterAutomaticTerminationRefresh() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let initialApps = self.terminateScenarioApps()
            let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherApps: initialApps)
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
            )
            controller.modelForTesting.terminateRequestOverride = { _ in
                (sent: true, pid: 42_100)
            }
            // Use polling path to drive a fully automatic refresh after quit shortcut.
            controller.modelForTesting.isProcessRunningOverride = { _ in false }

            XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
            guard let sessionBeforeTermination = controller.modelForTesting.session else {
                XCTFail("Expected an active session before automatic terminate refresh")
                return
            }
            let terminatedAppID = sessionBeforeTermination.selectedApp.id
            let remainingAppIDs = sessionBeforeTermination.apps.map(\.id).filter { $0 != terminatedAppID }
            let expectedSelectedAppID = remainingAppIDs[
                min(sessionBeforeTermination.selectedAppIndex, remainingAppIDs.count - 1)
            ]
            XCTAssertFalse(controller.modelForTesting.isSearchActive)
            assertAppSwitcherProjectionSessionRead(from: runtimeProjectionService)

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

            XCTAssertNotNil(controller.modelForTesting.session)
            XCTAssertEqual(controller.modelForTesting.appCount, 2)
            XCTAssertEqual(controller.modelForTesting.selectedApp?.id, expectedSelectedAppID)
            XCTAssertFalse(controller.modelForTesting.session?.apps.contains { $0.id == terminatedAppID } ?? true)
            XCTAssertEqual(runtimeProjectionService.appTerminationSignalsRecorded().map(\.appID), [terminatedAppID])
            assertAppSwitcherProjectionSessionRead(from: runtimeProjectionService, minimumReadCount: 2)
            XCTAssertFalse(controller.modelForTesting.isSearchActive)
            controller.cancelSelectionForTesting()
        }
    }

    @MainActor
    private func assertCommittedSearchIndexRead(
        _ model: LiveSwitcherModel,
        from runtimeProjectionService: RecordingRuntimeProjectionService,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(
            runtimeProjectionService.committedSearchIndexReadCount(),
            1,
            file: file,
            line: line
        )
        XCTAssertEqual(
            model.lastSearchIndexReadDiagnostic?.readiness,
            .committedGenerationValidated,
            file: file,
            line: line
        )
        XCTAssertEqual(
            model.lastSearchIndexReadDiagnostic?.resultState,
            .committedGenerationResult,
            file: file,
            line: line
        )
        XCTAssertEqual(
            model.lastSearchIndexReadDiagnostic?.committedIndexCoversCurrentGeneration,
            true,
            file: file,
            line: line
        )
        XCTAssertEqual(
            model.lastSearchIndexReadDiagnostic?.requestedFreshnessBarrier,
            false,
            file: file,
            line: line
        )
        XCTAssertEqual(
            runtimeProjectionService.searchIndexFreshnessBarrierRequestsRecorded(),
            [],
            file: file,
            line: line
        )
    }

    private func assertAppSwitcherProjectionSessionRead(
        from runtimeProjectionService: RecordingRuntimeProjectionService,
        minimumReadCount: Int = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(
            runtimeProjectionService.appSwitcherProjectionReadCount(),
            minimumReadCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherMaintenanceRequestsRecorded(),
            [.switcherSessionStarted],
            file: file,
            line: line
        )
    }

    private func assertCurrentAppWindowProjectionRead(
        appID: String,
        from runtimeProjectionService: RecordingRuntimeProjectionService,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            runtimeProjectionService.currentAppWindowProjectionReadCount(appID: appID),
            1,
            file: file,
            line: line
        )
        XCTAssertEqual(
            runtimeProjectionService.selectedCurrentAppWindowChangeSignalsRecorded().map(\.appID),
            [],
            file: file,
            line: line
        )
    }

}
