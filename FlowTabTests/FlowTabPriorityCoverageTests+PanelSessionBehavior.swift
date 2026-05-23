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

        let didCommitInAppRelease = await waitUntil("in-app hotkey release commits selection") {
            controller.modelForTesting.session == nil && activatedTarget != nil
        }
        XCTAssertTrue(didCommitInAppRelease)
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
    func testSwitcherPanelVisibilityProbeIncludesContentStateForInAppSession() {
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

        XCTAssertTrue(controller.beginInAppWindowHotkeySessionForTesting())
        let summary = controller.panelContentProbeSummary()

        XCTAssertTrue(summary.contains("content=ready"))
        XCTAssertTrue(summary.contains("overlay=windowOnly"))
        XCTAssertTrue(summary.contains("mode=windowCycle(\(appID))"))
        XCTAssertTrue(summary.contains("selectedAppID=\(appID)"))
        XCTAssertTrue(summary.contains("selectedWindows=2"))
        XCTAssertTrue(summary.contains("selectedWindowID=front-1"))
        controller.cancelSelectionForTesting()
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

        let didCommitGlobalRelease = await waitUntil("global hotkey release commits selection") {
            controller.modelForTesting.session == nil && activatedTarget != nil
        }
        XCTAssertTrue(didCommitGlobalRelease)
        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertNotNil(activatedTarget)
    }

    @MainActor
    func testSwitcherPanelControllerReleaseConfirmationGenerationInvalidatesCanceledTask() {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.globalPrimaryModifierPressedOverride = false

        controller.scheduleModifierReleaseConfirmation(trigger: "generation_first")
        let firstGeneration = controller.modifierReleaseConfirmationGeneration
        XCTAssertNotNil(controller.pendingModifierReleaseConfirmationTask)
        XCTAssertEqual(
            controller.modifierReleaseState,
            .releaseObserved(trigger: "generation_first", generation: firstGeneration)
        )

        controller.cancelPendingModifierReleaseConfirmation()
        XCTAssertNil(controller.pendingModifierReleaseConfirmationTask)
        XCTAssertEqual(controller.modifierReleaseConfirmationGeneration, firstGeneration + 1)
        XCTAssertEqual(
            controller.modifierReleaseState,
            .canceled(reason: .explicitCancel, generation: firstGeneration)
        )

        controller.scheduleModifierReleaseConfirmation(trigger: "generation_second")
        let secondGeneration = controller.modifierReleaseConfirmationGeneration
        XCTAssertNotNil(controller.pendingModifierReleaseConfirmationTask)
        XCTAssertEqual(
            controller.modifierReleaseState,
            .releaseObserved(trigger: "generation_second", generation: secondGeneration)
        )

        controller.clearPendingModifierReleaseConfirmationTaskIfCurrent(firstGeneration)
        XCTAssertNotNil(controller.pendingModifierReleaseConfirmationTask)
        XCTAssertEqual(
            controller.modifierReleaseState,
            .releaseObserved(trigger: "generation_second", generation: secondGeneration)
        )

        XCTAssertEqual(controller.modifierReleaseConfirmationGeneration, secondGeneration)
        controller.cancelPendingModifierReleaseConfirmation()
        XCTAssertNil(controller.pendingModifierReleaseConfirmationTask)
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerModifierReleaseConfirmationPolicyOwnsTimingConstants() {
        let controller = SwitcherPanelController()

        XCTAssertEqual(controller.modifierReleaseConfirmationPolicy, .default)
        XCTAssertEqual(controller.modifierReleaseConfirmationSampleIntervalNs, 25_000_000)
        XCTAssertEqual(controller.modifierReleaseConfirmationSampleCount, 2)
        XCTAssertEqual(controller.postFinishHotkeyIgnoreWindow, 0.02)
        XCTAssertEqual(controller.modifierReleaseState, .idle)
    }

    @MainActor
    func testSwitcherPanelControllerHotkeyReplaySuppressionUsesReleaseStateGeneration() async {
        let controller = SwitcherPanelController()
        controller.globalPrimaryModifierPressedOverride = false
        controller.globalMainKeyPressedOverride = false

        controller.beginHotkeyReplaySuppressionUntilRelease(
            for: .globalAppSwitcher,
            trigger: "state_machine"
        )

        let generation = controller.modifierReleaseConfirmationGeneration
        XCTAssertTrue(controller.suppressHotkeyReplayUntilReleaseForTesting)
        XCTAssertEqual(
            controller.modifierReleaseState,
            .replaySuppression(trigger: "state_machine", generation: generation, releasedSamples: 0)
        )

        let didEndSuppression = await waitForHotkeyReplaySuppressionToEnd(panelController: controller)
        XCTAssertTrue(didEndSuppression)
        XCTAssertFalse(controller.suppressHotkeyReplayUntilReleaseForTesting)
        XCTAssertEqual(
            controller.modifierReleaseState,
            .replaySuppressionEnded(trigger: "state_machine", generation: generation)
        )
    }

    @MainActor
    func testSwitcherPanelControllerPresentationSessionGenerationTracksSessionLifecycle() {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }

        XCTAssertEqual(controller.presentationSessionGeneration, 0)
        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        let firstSessionGeneration = controller.presentationSessionGeneration
        XCTAssertEqual(firstSessionGeneration, 1)
        XCTAssertTrue(controller.isPresentationSessionGenerationCurrent(firstSessionGeneration))

        controller.globalPrimaryModifierPressedOverride = false
        controller.scheduleModifierReleaseConfirmation(trigger: "session_generation")
        let releaseGeneration = controller.modifierReleaseConfirmationGeneration
        XCTAssertNotNil(controller.pendingModifierReleaseConfirmationTask)

        controller.cancelSelectionForTesting()

        XCTAssertNil(controller.pendingModifierReleaseConfirmationTask)
        XCTAssertFalse(controller.isPresentationSessionGenerationCurrent(firstSessionGeneration))
        XCTAssertEqual(controller.presentationSessionGeneration, firstSessionGeneration + 1)
        XCTAssertEqual(
            controller.modifierReleaseState,
            .canceled(reason: .explicitCancel, generation: releaseGeneration)
        )

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        XCTAssertEqual(controller.presentationSessionGeneration, firstSessionGeneration + 2)
        controller.cancelSelectionForTesting()
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

        let didLoadSelectedAppSnapshot = await waitUntil(
            "selected app window snapshot loads from shared runtime snapshot service",
            timeoutNanoseconds: 1_000_000_000,
            pollIntervalNanoseconds: 10_000_000
        ) {
            model.session?.selectedApp.windows.map(\.id) == ["shared-window-1", "shared-window-2"]
        }
        XCTAssertTrue(didLoadSelectedAppSnapshot)
        XCTAssertEqual(snapshotService.recordedHomeAppIDs(), [appID])
        XCTAssertEqual(model.session?.selectedApp.windows.map(\.id), ["shared-window-1", "shared-window-2"])
    }

    @MainActor
    func testLiveSwitcherModelFocusedWindowSessionUsesFocusedRuntimeSnapshotSource() {
        let runningApp = NSRunningApplication.current
        let appID = runningApp.bundleIdentifier ?? "pid:\(runningApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "focused-window-1", title: "Focused One", isMinimized: false, lastActiveAt: 20),
            WindowCandidate(id: "focused-window-2", title: "Focused Two", isMinimized: false, lastActiveAt: 10)
        ]
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: "Focused Runtime Source",
            groupID: "focused-runtime-source",
            lastActiveAt: 100,
            windows: windows
        )
        let focusedSnapshot = RuntimeHomeAppSnapshot(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Focused Runtime Source",
                groupID: "focused-runtime-source",
                lastActiveAt: 100,
                windowCount: windows.count,
                pid: runningApp.processIdentifier
            ),
            candidate: candidate,
            context: makeRuntimeAppContext(appID: appID, runningApp: runningApp, windows: windows)
        )
        let snapshotService = RecordingRuntimeSnapshotService(
            focusedSnapshotsByPID: [runningApp.processIdentifier: focusedSnapshot]
        )
        let model = LiveSwitcherModel(snapshotService: snapshotService)
        model.frontmostApplicationOverride = { runningApp }
        model.focusedWindowIdentityOverride = { _ in nil }
        model.frontmostRuntimeWindowIDOverride = { _, _, _ in nil }

        XCTAssertTrue(model.startFocusedAppWindowSession(triggerDirection: .forward))

        XCTAssertEqual(snapshotService.recordedFocusedPIDs(), [runningApp.processIdentifier])
        XCTAssertEqual(snapshotService.snapshotRequestCount(), 0)
        XCTAssertEqual(model.session?.mode, .windowCycle(appID: appID))
        XCTAssertEqual(model.session?.selectedApp.windows.map(\.id), ["focused-window-1", "focused-window-2"])
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

        let didEndSession = await waitUntil(
            "flags changed release confirmation ends session",
            timeoutNanoseconds: 1_000_000_000,
            pollIntervalNanoseconds: 10_000_000
        ) {
            controller.modelForTesting.session == nil
        }
        XCTAssertTrue(didEndSession)
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

        let didRecoverVisibility = await waitUntil(
            "active space recovery confirms panel visible",
            timeoutNanoseconds: 1_000_000_000,
            pollIntervalNanoseconds: 10_000_000
        ) {
            controller.lastPanelVisibilityRecoveryDiagnostic?.after.userVisible == true
        }
        XCTAssertTrue(didRecoverVisibility)
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

        let didRecoverVisibility = await waitUntil(
            "active space notification recovery confirms panel visible",
            timeoutNanoseconds: 1_000_000_000,
            pollIntervalNanoseconds: 10_000_000
        ) {
            controller.lastPanelVisibilityRecoveryDiagnostic?.after.userVisible == true
        }
        XCTAssertTrue(didRecoverVisibility)
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

        let didCancelSession = await waitUntil(
            "active space notification cancels session after modifier release",
            timeoutNanoseconds: 1_000_000_000,
            pollIntervalNanoseconds: 10_000_000
        ) {
            controller.modelForTesting.session == nil
        }
        XCTAssertTrue(didCancelSession)
        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertTrue(controller.suppressHotkeyReplayUntilReleaseForTesting)

        let notificationSuppressionEnded = await waitForHotkeyReplaySuppressionToEnd(panelController: controller)
        XCTAssertTrue(notificationSuppressionEnded)
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

        let activeSpaceSuppressionEnded = await waitForHotkeyReplaySuppressionToEnd(panelController: controller)
        XCTAssertTrue(activeSpaceSuppressionEnded)
    }

    @MainActor
    func testSwitcherPanelControllerTerminateRefreshIgnoresFollowUpActiveSpaceChangeAfterModifierRelease() async {
        let controller = SwitcherPanelController()
        let initialApps = terminateScenarioApps()
        var snapshotReadCount = 0
        var terminatedAppID: String?
        controller.modelForTesting.snapshotProviderOverride = {
            defer { snapshotReadCount += 1 }
            guard snapshotReadCount > 0, let terminatedAppID else {
                return RuntimeSnapshot(apps: initialApps, contextsByID: [:])
            }
            return RuntimeSnapshot(
                apps: initialApps.filter { $0.id != terminatedAppID },
                contextsByID: [:]
            )
        }
        controller.globalPrimaryModifierPressedOverride = false
        controller.globalMainKeyPressedOverride = false

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        terminatedAppID = controller.modelForTesting.selectedApp?.id
        guard let terminatedAppID else {
            XCTFail("Expected selected app before terminate refresh")
            return
        }
        XCTAssertEqual(controller.modelForTesting.selectedApp?.id, terminatedAppID)

        controller.handleWorkspaceApplicationTerminatedForTesting(appID: terminatedAppID, pid: 42_300)

        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertFalse(controller.modelForTesting.session?.apps.contains { $0.id == terminatedAppID } ?? true)

        controller.handleActiveSpaceDidChangeForTesting()

        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertFalse(controller.suppressHotkeyReplayUntilReleaseForTesting)
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerTerminateRequestProtectsPanelResignAfterModifierRelease() async {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.terminateScenarioApps(), contextsByID: [:])
        }
        controller.modelForTesting.terminateRequestOverride = { _ in
            (sent: true, pid: 42_301)
        }
        controller.modelForTesting.isProcessRunningOverride = { _ in true }
        controller.globalPrimaryModifierPressedOverride = false
        controller.globalMainKeyPressedOverride = false
        controller.appIsActiveOverride = false

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        let selectedAppID = controller.modelForTesting.selectedApp?.id

        controller.terminateSelectedApp()
        let didEnterTerminateProtection = await waitUntil(
            "terminate request enters interruption protection before panel resign",
            timeoutNanoseconds: 1_000_000_000,
            pollIntervalNanoseconds: 10_000_000
        ) {
            controller.modelForTesting.terminatingAppID == selectedAppID
                && controller.shouldProtectTerminateSystemInterruption()
        }
        XCTAssertTrue(didEnterTerminateProtection)

        XCTAssertEqual(controller.modelForTesting.terminatingAppID, selectedAppID)
        controller.handlePanelDidResignKeyForTesting()

        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertFalse(controller.suppressHotkeyReplayUntilReleaseForTesting)
        controller.cancelSelectionForTesting()
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

        let didRecoverVisibility = await waitUntil(
            "recoverable occlusion confirms panel visible",
            timeoutNanoseconds: 1_000_000_000,
            pollIntervalNanoseconds: 10_000_000
        ) {
            occlusionController.lastPanelVisibilityRecoveryDiagnostic?.after.userVisible == true
        }
        XCTAssertTrue(didRecoverVisibility)
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

        let activeSpaceSuppressionEnded = await waitForHotkeyReplaySuppressionToEnd(panelController: controller)
        XCTAssertTrue(activeSpaceSuppressionEnded)

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.panelOcclusionStateOverride = []
        controller.handlePanelOcclusionStateDidChangeForTesting()

        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertTrue(controller.suppressHotkeyReplayUntilReleaseForTesting)

        let occlusionSuppressionEnded = await waitForHotkeyReplaySuppressionToEnd(panelController: controller)
        XCTAssertTrue(occlusionSuppressionEnded)

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

        let didEnterWindowLayer = await waitUntil(
            "configured delayed auto-enter switches to window layer",
            timeoutNanoseconds: 1_000_000_000,
            pollIntervalNanoseconds: 10_000_000
        ) {
            guard case .windowCycle = controller.modelForTesting.session?.mode else {
                return false
            }
            return true
        }
        XCTAssertTrue(didEnterWindowLayer)
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

            let didEnterWindowLayer = await waitUntil(
                "preference delayed auto-enter switches to window layer",
                timeoutNanoseconds: 1_000_000_000,
                pollIntervalNanoseconds: 10_000_000
            ) {
                guard case .windowCycle = controller.modelForTesting.session?.mode else {
                    return false
                }
                return true
            }
            XCTAssertTrue(didEnterWindowLayer)
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

        let didPreserveDeadline = await waitUntil(
            "delayed auto-enter waits for late selected app snapshot before switching",
            timeoutNanoseconds: 1_000_000_000,
            pollIntervalNanoseconds: 10_000_000
        ) {
            requestsLock.lock()
            let recordedRequests = selectedSnapshotRequests
            requestsLock.unlock()
            return recordedRequests == [appID]
                && controller.modelForTesting.session?.mode == .windowCycle(appID: appID)
        }
        XCTAssertTrue(didPreserveDeadline)
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
        func backgroundCallCount() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return backgroundFullSnapshotCalls
        }

        controller.windowLayerPresentationDelayOverride = 0.01
        controller.modelForTesting.backgroundFullSnapshotRefreshDelay = .milliseconds(20)
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
            Thread.sleep(forTimeInterval: 0.08)
            return selectedSnapshot
        }

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.scheduleDelayedWindowLayerEntryForTesting()

        let deferredWhilePending = await waitUntil(
            "background full snapshot deferred while selected app snapshot is pending",
            timeoutNanoseconds: 1_000_000_000,
            pollIntervalNanoseconds: 10_000_000
        ) {
            controller.modelForTesting.deferredBackgroundFullSnapshotRefreshRequest != nil
                && backgroundCallCount() == 0
        }
        XCTAssertTrue(deferredWhilePending)

        let resumedAfterPendingSnapshot = await waitUntil(
            "background full snapshot resumes after selected app snapshot completes",
            timeoutNanoseconds: 1_000_000_000,
            pollIntervalNanoseconds: 10_000_000
        ) {
            backgroundCallCount() > 0
        }
        XCTAssertTrue(resumedAfterPendingSnapshot)
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
    func testSwitcherPanelControllerPreviewLayerExpandsBelowCenteredAppLayer() {
        let controller = SwitcherPanelController()
        let app = manyWindowLayoutApp(windowCount: 100)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: [app], contextsByID: [:])
        }

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())

        controller.updatePanelSizeForTesting(visibleFrame: visibleFrame)
        controller.centerPanelOnActiveScreen()
        let appLayerFrame = controller.panel.frame
        guard let screenCenterY = (controller.panel.screen ?? NSScreen.main)?.frame.midY else {
            XCTFail("Expected a screen for switcher panel placement")
            return
        }

        XCTAssertTrue(controller.modelForTesting.autoEnterWindowLayerIfPossible())

        controller.updatePanelSizeForTesting(visibleFrame: visibleFrame)
        let previewLayerFrame = controller.panel.frame

        XCTAssertGreaterThan(previewLayerFrame.width, appLayerFrame.width)
        XCTAssertEqual(previewLayerFrame.midX, appLayerFrame.midX, accuracy: 0.5)
        XCTAssertEqual(appLayerFrame.midY, screenCenterY, accuracy: 0.5)
        XCTAssertEqual(previewLayerFrame.maxY, appLayerFrame.maxY, accuracy: 0.5)
    }

}
