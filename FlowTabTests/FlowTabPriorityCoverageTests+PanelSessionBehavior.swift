import AppKit
import Carbon
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
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
    func testSwitcherPanelControllerGlobalHotkeyStartsFromFastAppSnapshot() {
        let controller = SwitcherPanelController()
        let fastApps = searchScenarioApps().map { app in
            AppSwitchCandidate(
                id: app.id,
                displayName: app.displayName,
                groupID: app.groupID,
                lastActiveAt: app.lastActiveAt,
                windows: []
            )
        }
        var fullSnapshotCalls = 0
        controller.modelForTesting.frontmostApplicationOverride = { nil }
        controller.modelForTesting.fastAppSnapshotProviderOverride = {
            RuntimeSnapshot(apps: fastApps, contextsByID: [:])
        }
        controller.modelForTesting.snapshotProviderOverride = {
            fullSnapshotCalls += 1
            Thread.sleep(forTimeInterval: 0.2)
            return RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }

        let start = DispatchTime.now().uptimeNanoseconds
        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0

        XCTAssertLessThan(elapsedMs, 100)
        XCTAssertEqual(fullSnapshotCalls, 0)
        XCTAssertEqual(controller.modelForTesting.session?.apps.count, fastApps.count)
        XCTAssertEqual(controller.modelForTesting.session?.apps.first?.windows.count, 0)
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testLiveSwitcherModelSelectedAppWindowSnapshotUsesSharedRuntimeSnapshotService() async {
        let appID = "com.example.shared-runtime-source"
        let runningApp = NSRunningApplication.current
        let appOnlyCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Shared Runtime Source",
            groupID: "shared-runtime-source",
            lastActiveAt: 100,
            windows: []
        )
        let windows = [
            WindowCandidate(id: "shared-window-1", title: "Shared One", isMinimized: false, lastActiveAt: 20),
            WindowCandidate(id: "shared-window-2", title: "Shared Two", isMinimized: false, lastActiveAt: 10)
        ]
        let windowCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Shared Runtime Source",
            groupID: "shared-runtime-source",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(appID: appID, runningApp: runningApp, windows: windows)
        let selectedSnapshot = RuntimeHomeAppSnapshot(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Shared Runtime Source",
                groupID: "shared-runtime-source",
                lastActiveAt: 100,
                windowCount: windows.count,
                pid: runningApp.processIdentifier
            ),
            candidate: windowCandidate,
            context: context
        )
        let snapshotService = RecordingRuntimeSnapshotService(
            homeSnapshotsByAppID: [appID: selectedSnapshot]
        )
        let model = LiveSwitcherModel(snapshotService: snapshotService)
        model.backgroundFullSnapshotRefreshEnabled = false
        model.fastAppSnapshotProviderOverride = {
            RuntimeSnapshot(apps: [appOnlyCandidate], contextsByID: [:])
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.scheduleSelectedAppWindowSnapshotIfNeeded(for: appID))

        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(snapshotService.recordedHomeAppIDs(), [appID])
        XCTAssertEqual(model.session?.selectedApp.windows.map(\.id), ["shared-window-1", "shared-window-2"])
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
    func testSwitcherPanelControllerDelayedAutoEnterPreservesDeadlineForLateSelectedAppSnapshot() async {
        let controller = SwitcherPanelController()
        let currentApp = NSRunningApplication.current
        let appID = "com.example.deferred-window-snapshot"
        let windows = [
            WindowCandidate(id: "deferred-1", title: "Deferred One", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "deferred-2", title: "Deferred Two", isMinimized: false, lastActiveAt: 20)
        ]
        let appOnlyCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Deferred Snapshot",
            groupID: "deferred",
            lastActiveAt: 100,
            windows: []
        )
        let windowCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Deferred Snapshot",
            groupID: "deferred",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(appID: appID, runningApp: currentApp, windows: windows)
        let selectedSnapshot = RuntimeHomeAppSnapshot(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Deferred Snapshot",
                groupID: "deferred",
                lastActiveAt: 100,
                windowCount: windows.count,
                pid: currentApp.processIdentifier
            ),
            candidate: windowCandidate,
            context: context
        )
        let requestsLock = NSLock()
        var selectedSnapshotRequests: [String] = []

        controller.windowLayerPresentationDelayOverride = 0.01
        controller.modelForTesting.fastAppSnapshotProviderOverride = {
            RuntimeSnapshot(apps: [appOnlyCandidate], contextsByID: [:])
        }
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: [appOnlyCandidate], contextsByID: [:])
        }
        controller.modelForTesting.selectedAppSnapshotProviderOverride = { requestedAppID in
            requestsLock.lock()
            selectedSnapshotRequests.append(requestedAppID)
            requestsLock.unlock()
            Thread.sleep(forTimeInterval: 0.04)
            return selectedSnapshot
        }

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        XCTAssertEqual(controller.modelForTesting.session?.selectedApp.windows.count, 0)

        controller.scheduleDelayedWindowLayerEntryForTesting()

        try? await Task.sleep(nanoseconds: 140_000_000)
        requestsLock.lock()
        let recordedRequests = selectedSnapshotRequests
        requestsLock.unlock()
        XCTAssertEqual(recordedRequests, [appID])
        XCTAssertEqual(
            controller.modelForTesting.session?.mode,
            .windowCycle(appID: appID)
        )
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testLiveSwitcherModelDelaysBackgroundFullSnapshotWhileSelectedAppSnapshotIsPending() async {
        let controller = SwitcherPanelController()
        let currentApp = NSRunningApplication.current
        let appID = "com.example.pending-window-snapshot"
        let windows = [
            WindowCandidate(id: "pending-1", title: "Pending One", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "pending-2", title: "Pending Two", isMinimized: false, lastActiveAt: 20)
        ]
        let appOnlyCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Pending Snapshot",
            groupID: "pending",
            lastActiveAt: 100,
            windows: []
        )
        let windowCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Pending Snapshot",
            groupID: "pending",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(appID: appID, runningApp: currentApp, windows: windows)
        let selectedSnapshot = RuntimeHomeAppSnapshot(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Pending Snapshot",
                groupID: "pending",
                lastActiveAt: 100,
                windowCount: windows.count,
                pid: currentApp.processIdentifier
            ),
            candidate: windowCandidate,
            context: context
        )
        let lock = NSLock()
        var backgroundFullSnapshotCalls = 0

        controller.windowLayerPresentationDelayOverride = 0.01
        controller.modelForTesting.fastAppSnapshotProviderOverride = {
            RuntimeSnapshot(apps: [appOnlyCandidate], contextsByID: [:])
        }
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: [appOnlyCandidate], contextsByID: [:])
        }
        controller.modelForTesting.backgroundFullSnapshotProviderOverride = {
            lock.lock()
            backgroundFullSnapshotCalls += 1
            lock.unlock()
            return RuntimeSnapshot(apps: [windowCandidate], contextsByID: [appID: context])
        }
        controller.modelForTesting.selectedAppSnapshotProviderOverride = { _ in
            Thread.sleep(forTimeInterval: 0.24)
            return selectedSnapshot
        }

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.scheduleDelayedWindowLayerEntryForTesting()

        try? await Task.sleep(nanoseconds: 190_000_000)
        lock.lock()
        let callsWhilePending = backgroundFullSnapshotCalls
        lock.unlock()
        XCTAssertEqual(callsWhilePending, 0)

        try? await Task.sleep(nanoseconds: 260_000_000)
        lock.lock()
        let callsAfterPending = backgroundFullSnapshotCalls
        lock.unlock()
        XCTAssertGreaterThan(callsAfterPending, 0)
        controller.cancelSelectionForTesting()
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

    @MainActor
    func testSwitcherPanelControllerPreviewLayerUsesWindowPreviewWidthForSingleAppManyWindows() {
        let controller = SwitcherPanelController()
        let app = manyWindowLayoutApp(windowCount: 100)
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: [app], contextsByID: [:])
        }

        XCTAssertTrue(controller.modelForTesting.startSession(triggerDirection: .forward))
        XCTAssertTrue(controller.modelForTesting.autoEnterWindowLayerIfPossible())

        controller.updatePanelSizeForTesting(
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(controller.modelForTesting.appGridTileSize, 68, accuracy: 0.001)
        XCTAssertEqual(controller.modelForTesting.appGridSpacing, 0, accuracy: 0.001)
        XCTAssertEqual(controller.panelContentSizeForTesting.width, 1344, accuracy: 0.001)
    }

    @MainActor
    func testSwitcherPanelControllerRecentersPresentedPanelWhenPreviewLayerExpandsWidth() {
        let controller = SwitcherPanelController()
        let app = manyWindowLayoutApp(windowCount: 100)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: [app], contextsByID: [:])
        }

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())

        controller.updatePanelSizeForTesting(visibleFrame: visibleFrame)
        let appLayerFrame = controller.panel.frame

        XCTAssertTrue(controller.modelForTesting.autoEnterWindowLayerIfPossible())

        controller.updatePanelSizeForTesting(visibleFrame: visibleFrame)
        let previewLayerFrame = controller.panel.frame

        XCTAssertGreaterThan(previewLayerFrame.width, appLayerFrame.width)
        XCTAssertEqual(previewLayerFrame.midX, appLayerFrame.midX, accuracy: 0.5)
    }

}

private final class RecordingRuntimeSnapshotService: RuntimeSnapshotServing, @unchecked Sendable {
    private let lock = NSLock()
    private let homeSnapshotsByAppID: [String: RuntimeHomeAppSnapshot]
    private var requestedHomeAppIDs: [String] = []

    init(homeSnapshotsByAppID: [String: RuntimeHomeAppSnapshot]) {
        self.homeSnapshotsByAppID = homeSnapshotsByAppID
    }

    func recordedHomeAppIDs() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return requestedHomeAppIDs
    }

    func snapshot() -> RuntimeSnapshot {
        RuntimeSnapshot(apps: [], contextsByID: [:])
    }

    func lightweightAppSnapshot() -> RuntimeSnapshot {
        RuntimeSnapshot(apps: [], contextsByID: [:])
    }

    func homeAppSummaries() async -> [RuntimeHomeAppSummary] {
        homeSnapshotsByAppID.values.map(\.summary)
    }

    func homeAppSummary(for appID: String) async -> RuntimeHomeAppSummary? {
        homeSnapshotsByAppID[appID]?.summary
    }

    func homeAppSnapshot(for appID: String) async -> RuntimeHomeAppSnapshot? {
        homeAppSnapshotSynchronously(for: appID)
    }

    func homeAppSnapshotSynchronously(for appID: String) -> RuntimeHomeAppSnapshot? {
        lock.lock()
        requestedHomeAppIDs.append(appID)
        lock.unlock()
        return homeSnapshotsByAppID[appID]
    }

    func currentCGWindowsByPID() -> [pid_t: [RuntimeSnapshotProvider.CGWindowEntry]] {
        [:]
    }

    func isLikelyTransientAXRebuild(for pid: pid_t) -> Bool {
        false
    }
}
