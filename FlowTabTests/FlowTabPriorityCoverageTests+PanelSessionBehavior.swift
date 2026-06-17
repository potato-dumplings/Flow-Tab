import AppKit
import Carbon
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testSwitcherPanelControllerInAppHotkeyReleaseCommitsFocusedWindowSession() async {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "front-1", title: "Inbox", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "front-2", title: "Draft", isMinimized: false, lastActiveAt: 20)
        ]
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                snapshotService: makeCurrentAppWindowProjectionService(
                    appID: appID,
                    runningApp: currentApp,
                    windows: windows
                )
            )
        )
        controller.modelForTesting.frontmostApplicationOverride = { currentApp }

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
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "front-1", title: "Inbox", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "front-2", title: "Draft", isMinimized: false, lastActiveAt: 20)
        ]
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                snapshotService: makeCurrentAppWindowProjectionService(
                    appID: appID,
                    runningApp: currentApp,
                    windows: windows
                )
            )
        )
        controller.modelForTesting.frontmostApplicationOverride = { currentApp }

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
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                snapshotService: RecordingRuntimeSnapshotService(
                    appSwitcherApps: searchScenarioApps()
                )
            )
        )

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
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                snapshotService: RecordingRuntimeSnapshotService(
                    appSwitcherApps: searchScenarioApps()
                )
            )
        )

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

    private func makeCurrentAppWindowProjectionService(
        appID: String,
        runningApp: NSRunningApplication,
        windows: [WindowCandidate]
    ) -> RecordingRuntimeSnapshotService {
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: runningApp.localizedName ?? "Current App",
            groupID: "current",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: runningApp,
            windows: windows
        )
        let snapshot = RuntimeHomeAppSnapshot(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: candidate.displayName,
                groupID: candidate.groupID,
                lastActiveAt: candidate.lastActiveAt,
                windowCount: windows.count,
                pid: runningApp.processIdentifier
            ),
            candidate: candidate,
            context: context
        )
        return RecordingRuntimeSnapshotService(
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    snapshot: snapshot,
                    freshness: RuntimeProjectionFreshness(
                        generatedAt: 10,
                        sourceGeneration: RuntimeReadModelGeneration(projection: 1),
                        dirtyAppIDs: [],
                        dirtyPIDs: [],
                        dirtyCGWindowIDs: [],
                        pendingRepairScopes: [],
                        isCompleteForScope: true
                    )
                )
            ]
        )
    }

    @MainActor
    private func makeAppSwitcherProjectionPanelController() -> SwitcherPanelController {
        SwitcherPanelController(
            model: LiveSwitcherModel(
                snapshotService: RecordingRuntimeSnapshotService(
                    appSwitcherApps: searchScenarioApps()
                )
            )
        )
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
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                snapshotService: RecordingRuntimeSnapshotService(
                    appSwitcherApps: searchScenarioApps()
                )
            )
        )

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
    func testSwitcherPanelControllerGlobalHotkeyStartsFromAppSwitcherProjection() {
        let fastApps = searchScenarioApps().map { app in
            AppSwitchCandidate(
                id: app.id,
                displayName: app.displayName,
                groupID: app.groupID,
                lastActiveAt: app.lastActiveAt,
                windows: []
            )
        }
        let runtimeService = RecordingRuntimeSnapshotService(appSwitcherApps: fastApps)
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(snapshotService: runtimeService)
        )
        controller.modelForTesting.frontmostApplicationOverride = { nil }

        let start = DispatchTime.now().uptimeNanoseconds
        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0

        XCTAssertLessThan(elapsedMs, 100)
        XCTAssertEqual(runtimeService.appSwitcherMaintenanceRequestsRecorded(), [.switcherSessionStarted])
        XCTAssertEqual(controller.modelForTesting.session?.apps.count, fastApps.count)
        XCTAssertEqual(controller.modelForTesting.session?.apps.first?.windows.count, 0)
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testLiveSwitcherModelStartsAppSessionFromRuntimeProjectionWithoutLightweightSampling() {
        let apps = searchScenarioApps().map { app in
            AppSwitchCandidate(
                id: app.id,
                displayName: app.displayName,
                groupID: app.groupID,
                lastActiveAt: app.lastActiveAt,
                windows: []
            )
        }
        let projection = RuntimeAppSwitcherProjection(
            apps: apps,
            contextsByID: [:],
            freshness: RuntimeProjectionFreshness(
                generatedAt: 10,
                sourceGeneration: RuntimeReadModelGeneration(projection: 1),
                dirtyAppIDs: [],
                dirtyPIDs: [],
                dirtyCGWindowIDs: [],
                pendingRepairScopes: [],
                isCompleteForScope: true
            )
        )
        let snapshotService = RecordingRuntimeSnapshotService(appSwitcherProjection: projection)
        let model = LiveSwitcherModel(snapshotService: snapshotService)
        model.runtimeProjectionMaintenanceEnabled = false

        XCTAssertTrue(model.startSession(triggerDirection: .forward))

        XCTAssertEqual(snapshotService.lightweightSnapshotRequestCount(), 0)
        XCTAssertEqual(snapshotService.snapshotRequestCount(), 0)
        XCTAssertEqual(model.session?.apps.map(\.id), apps.map(\.id))
        XCTAssertEqual(model.session?.apps.flatMap(\.windows).count, 0)
    }

    @MainActor
    func testLiveSwitcherModelRequestsMaintenanceWhenAppSwitcherProjectionIsMissing() {
        let snapshotService = RecordingRuntimeSnapshotService()
        let model = LiveSwitcherModel(snapshotService: snapshotService)

        XCTAssertFalse(model.startSession(triggerDirection: .forward))

        XCTAssertNil(model.session)
        XCTAssertEqual(snapshotService.snapshotRequestCount(), 0)
        XCTAssertEqual(snapshotService.lightweightSnapshotRequestCount(), 0)
        XCTAssertEqual(
            snapshotService.appSwitcherMaintenanceRequestsRecorded(),
            [.switcherSessionStarted]
        )
    }

    @MainActor
    func testLiveSwitcherModelDoesNotExposeDirtyProjectionWindowsAsFreshWindowCycle() {
        let appID = "com.example.dirty-projection"
        let staleWindows = [
            WindowCandidate(id: "stale-1", title: "Stale One", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "stale-2", title: "Stale Two", isMinimized: false, lastActiveAt: 20),
            WindowCandidate(id: "stale-3", title: "Stale Three", isMinimized: false, lastActiveAt: 10)
        ]
        let staleApp = AppSwitchCandidate(
            id: appID,
            displayName: "Dirty Projection",
            groupID: "dirty-projection",
            lastActiveAt: 100,
            windows: staleWindows
        )
        let projection = RuntimeAppSwitcherProjection(
            apps: [staleApp],
            contextsByID: [:],
            freshness: RuntimeProjectionFreshness(
                generatedAt: 10,
                sourceGeneration: RuntimeReadModelGeneration(space: 1, projection: 1),
                dirtyAppIDs: [],
                dirtyPIDs: [],
                dirtyCGWindowIDs: [CGWindowID(42)],
                pendingRepairScopes: ["spaceTopology"],
                isCompleteForScope: false
            )
        )
        let snapshotService = RecordingRuntimeSnapshotService(appSwitcherProjection: projection)
        let model = LiveSwitcherModel(snapshotService: snapshotService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))

        XCTAssertEqual(snapshotService.snapshotRequestCount(), 0)
        XCTAssertEqual(snapshotService.lightweightSnapshotRequestCount(), 0)
        XCTAssertEqual(snapshotService.appSwitcherMaintenanceRequestsRecorded(), [.switcherSessionStarted])
        XCTAssertEqual(model.session?.apps.map(\.id), [appID])
        XCTAssertEqual(model.session?.selectedApp.windows.map(\.id), [])

        model.handle(.downArrow)

        XCTAssertEqual(model.session?.mode, .appCycle)
        XCTAssertNil(model.session?.selectedWindow)
    }

    @MainActor
    func testLiveSwitcherModelSelectedAppWindowSnapshotUsesRuntimeProjectionWithoutHomeSampling() {
        let appID = "com.example.projected-current-app"
        let runningApp = NSRunningApplication.current
        let appOnlyCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Projected Runtime Source",
            groupID: "projected-runtime-source",
            lastActiveAt: 100,
            windows: []
        )
        let windows = [
            WindowCandidate(id: "projected-window-1", title: "Projected One", isMinimized: false, lastActiveAt: 20),
            WindowCandidate(id: "projected-window-2", title: "Projected Two", isMinimized: false, lastActiveAt: 10)
        ]
        let windowCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Projected Runtime Source",
            groupID: "projected-runtime-source",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(appID: appID, runningApp: runningApp, windows: windows)
        let selectedSnapshot = RuntimeHomeAppSnapshot(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Projected Runtime Source",
                groupID: "projected-runtime-source",
                lastActiveAt: 100,
                windowCount: windows.count,
                pid: runningApp.processIdentifier
            ),
            candidate: windowCandidate,
            context: context
        )
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 11,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let snapshotService = RecordingRuntimeSnapshotService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [appOnlyCandidate],
                contextsByID: [:],
                freshness: freshness
            ),
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    snapshot: selectedSnapshot,
                    freshness: freshness
                )
            ]
        )
        let model = LiveSwitcherModel(snapshotService: snapshotService)
        model.runtimeProjectionMaintenanceEnabled = false

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.scheduleSelectedAppWindowSnapshotIfNeeded(for: appID))

        XCTAssertEqual(snapshotService.recordedHomeAppIDs(), [])
        XCTAssertEqual(model.session?.selectedApp.windows.map(\.id), ["projected-window-1", "projected-window-2"])
        XCTAssertEqual(model.runtimeContextsByID[appID]?.windowsByID["projected-window-1"]?.title, "Projected One")
    }

    @MainActor
    func testLiveSwitcherModelSelectedAppWindowSnapshotSignalsRuntimeRepairWhenProjectionIsMissing() {
        let appID = "com.example.missing-window-projection"
        let runningApp = NSRunningApplication.current
        let appOnlyCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Missing Window Projection",
            groupID: "missing-window-projection",
            lastActiveAt: 100,
            windows: []
        )
        let windows = [
            WindowCandidate(id: "contaminated-home-window-1", title: "Home One", isMinimized: false, lastActiveAt: 20),
            WindowCandidate(id: "contaminated-home-window-2", title: "Home Two", isMinimized: false, lastActiveAt: 10)
        ]
        let context = makeRuntimeAppContext(appID: appID, runningApp: runningApp, windows: windows)
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 12,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let snapshotService = RecordingRuntimeSnapshotService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [appOnlyCandidate],
                contextsByID: [appID: context],
                freshness: freshness
            )
        )
        let model = LiveSwitcherModel(snapshotService: snapshotService)
        model.runtimeProjectionMaintenanceEnabled = false

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.scheduleSelectedAppWindowSnapshotIfNeeded(for: appID))

        XCTAssertEqual(snapshotService.recordedHomeAppIDs(), [])
        XCTAssertEqual(snapshotService.appWindowChangeSignalsRecorded().map(\.appID), [appID])
        XCTAssertEqual(snapshotService.appWindowChangeSignalsRecorded().map(\.pid), [runningApp.processIdentifier])
        XCTAssertEqual(model.session?.mode, .appCycle)
        XCTAssertEqual(model.session?.selectedApp.windows.map(\.id), [])
    }

    @MainActor
    func testLiveSwitcherModelFocusedWindowSessionUsesRuntimeProjectionWithoutFocusedSampling() {
        let runningApp = NSRunningApplication.current
        let appID = runningApp.bundleIdentifier ?? "pid:\(runningApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "focused-projected-1", title: "Focused Projected One", isMinimized: false, lastActiveAt: 20),
            WindowCandidate(id: "focused-projected-2", title: "Focused Projected Two", isMinimized: false, lastActiveAt: 10)
        ]
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: "Focused Runtime Projection",
            groupID: "focused-runtime-projection",
            lastActiveAt: 100,
            windows: windows
        )
        let snapshot = RuntimeHomeAppSnapshot(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Focused Runtime Projection",
                groupID: "focused-runtime-projection",
                lastActiveAt: 100,
                windowCount: windows.count,
                pid: runningApp.processIdentifier
            ),
            candidate: candidate,
            context: makeRuntimeAppContext(appID: appID, runningApp: runningApp, windows: windows)
        )
        let snapshotService = RecordingRuntimeSnapshotService(
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    snapshot: snapshot,
                    freshness: RuntimeProjectionFreshness(
                        generatedAt: 12,
                        sourceGeneration: RuntimeReadModelGeneration(projection: 1),
                        dirtyAppIDs: [],
                        dirtyPIDs: [],
                        dirtyCGWindowIDs: [],
                        pendingRepairScopes: [],
                        isCompleteForScope: true
                    )
                )
            ]
        )
        let model = LiveSwitcherModel(snapshotService: snapshotService)
        model.frontmostApplicationOverride = { runningApp }

        XCTAssertTrue(model.startFocusedAppWindowSession(triggerDirection: .forward))

        XCTAssertEqual(snapshotService.snapshotRequestCount(), 0)
        XCTAssertEqual(model.session?.mode, .windowCycle(appID: appID))
        XCTAssertEqual(model.session?.selectedApp.windows.map(\.id), ["focused-projected-1", "focused-projected-2"])
    }

    @MainActor
    func testLiveSwitcherModelFocusedWindowSessionSignalsRuntimeRepairWhenProjectionIsMissing() {
        let runningApp = NSRunningApplication.current
        let appID = runningApp.bundleIdentifier ?? "pid:\(runningApp.processIdentifier)"
        let snapshotService = RecordingRuntimeSnapshotService()
        let model = LiveSwitcherModel(snapshotService: snapshotService)
        model.frontmostApplicationOverride = { runningApp }

        XCTAssertFalse(model.startFocusedAppWindowSession(triggerDirection: .forward))

        XCTAssertEqual(snapshotService.appWindowChangeSignalsRecorded().map(\.appID), [appID])
        XCTAssertEqual(snapshotService.appWindowChangeSignalsRecorded().map(\.pid), [runningApp.processIdentifier])
        XCTAssertEqual(snapshotService.snapshotRequestCount(), 0)
        XCTAssertNil(model.session)
    }

    @MainActor
    func testSwitcherPanelControllerDownArrowInAppCycleEntersWindowLayer() {
        let controller = makeAppSwitcherProjectionPanelController()

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
        let controller = makeAppSwitcherProjectionPanelController()

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
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    snapshotService: RecordingRuntimeSnapshotService(
                        appSwitcherApps: self.searchScenarioApps()
                    )
                )
            )

            XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
            XCTAssertTrue(controller.modelForTesting.enterSearchMode())
            controller.panelContainsPointOverride = { _ in false }

            controller.handleGlobalMouseDownForTesting(location: .zero)

            XCTAssertNil(controller.modelForTesting.session)
        }
    }

    @MainActor
    func testSwitcherPanelControllerActiveSpaceChangeKeepsSessionVisibleWithoutReactivatingApp() async {
        let snapshotService = RecordingRuntimeSnapshotService(appSwitcherApps: searchScenarioApps())
        let model = LiveSwitcherModel(snapshotService: snapshotService)
        let controller = SwitcherPanelController(model: model)
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
            if case .visibleConfirmed = controller.panelVisibilityRecoveryState {
                return true
            }
            return false
        }
        XCTAssertTrue(didRecoverVisibility)
        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertEqual(activateCallCount, 0)
        XCTAssertFalse(controller.suppressHotkeyReplayUntilReleaseForTesting)
    }

    @MainActor
    func testSwitcherPanelControllerActiveSpaceNotificationSignalsRuntimeTopologyChange() async {
        let snapshotService = RecordingRuntimeSnapshotService()
        let model = LiveSwitcherModel(snapshotService: snapshotService)
        let controller = SwitcherPanelController(model: model)

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        let didSignalRuntime = await waitUntil(
            "active space notification signals runtime topology change",
            timeoutNanoseconds: 1_000_000_000,
            pollIntervalNanoseconds: 10_000_000
        ) {
            snapshotService.spaceTopologyChangeSignalCount() == 1
        }
        XCTAssertTrue(didSignalRuntime)
        XCTAssertNil(controller.modelForTesting.session)
    }

    @MainActor
    func testSwitcherPanelControllerActiveSpaceChangeCancelsSessionAfterModifierRelease() async {
        let snapshotService = RecordingRuntimeSnapshotService(appSwitcherApps: searchScenarioApps())
        let model = LiveSwitcherModel(snapshotService: snapshotService)
        let controller = SwitcherPanelController(model: model)
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
        controller.modelForTesting.testingSnapshotProviderOverride = {
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
        controller.modelForTesting.testingSnapshotProviderOverride = {
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
        let occlusionController = makeAppSwitcherProjectionPanelController()
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
        let controller = makeAppSwitcherProjectionPanelController()
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
        let controller = makeAppSwitcherProjectionPanelController()
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
            let controller = makeAppSwitcherProjectionPanelController()

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
        controller.modelForTesting.testingFastAppSnapshotProviderOverride = {
            RuntimeSnapshot(apps: [appOnlyCandidate], contextsByID: [:])
        }
        controller.modelForTesting.testingSnapshotProviderOverride = {
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
    func testLiveSwitcherModelStartSessionRequestsRuntimeMaintenanceWithoutSurfaceSampling() {
        let appID = "com.flowtab.tests.runtime-maintenance"
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: "Runtime Maintenance",
            groupID: "maintenance",
            lastActiveAt: 100,
            windows: []
        )
        let snapshotService = RecordingRuntimeSnapshotService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [candidate],
                contextsByID: [:],
                freshness: RuntimeProjectionFreshness(
                    generatedAt: 20,
                    sourceGeneration: RuntimeReadModelGeneration(projection: 1),
                    dirtyAppIDs: [],
                    dirtyPIDs: [],
                    dirtyCGWindowIDs: [],
                    pendingRepairScopes: [],
                    isCompleteForScope: true
                )
            )
        )
        let model = LiveSwitcherModel(snapshotService: snapshotService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))

        XCTAssertEqual(snapshotService.snapshotRequestCount(), 0)
        XCTAssertEqual(snapshotService.lightweightSnapshotRequestCount(), 0)
        XCTAssertEqual(snapshotService.appSwitcherMaintenanceRequestsRecorded(), [.switcherSessionStarted])
        XCTAssertEqual(model.lastRuntimeProjectionMaintenanceDiagnostic?.result, "maintenanceRequested")
        XCTAssertEqual(model.lastRuntimeProjectionMaintenanceDiagnostic?.applyGeneration, nil)
    }

    @MainActor
    func testSwitcherPanelControllerShowSkipsHidingRegularWindowsWhileAppIsActive() {
        let controller = SwitcherPanelController()
        controller.modelForTesting.testingSnapshotProviderOverride = {
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
        controller.modelForTesting.testingSnapshotProviderOverride = {
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
        controller.modelForTesting.testingSnapshotProviderOverride = {
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
        controller.modelForTesting.testingSnapshotProviderOverride = {
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
        controller.modelForTesting.testingSnapshotProviderOverride = {
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
        controller.modelForTesting.testingSnapshotProviderOverride = {
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
