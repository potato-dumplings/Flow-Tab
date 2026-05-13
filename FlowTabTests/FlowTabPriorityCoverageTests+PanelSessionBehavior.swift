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

}
