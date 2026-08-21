import AppKit
import Carbon
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testSwitcherPanelControllerInAppHotkeySessionCommitsFocusedRuntimeProjectionWindow() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "front-1", title: "Inbox", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "front-2", title: "Draft", isMinimized: false, lastActiveAt: 20)
        ]
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: makeCurrentAppWindowProjectionService(
                    appID: appID,
                    runningApp: currentApp,
                    windows: windows
                )
            )
        )
        var activatedTarget: ActivationTarget?
        controller.modelForTesting.activationOverride = { target, _ in
            activatedTarget = target
        }

        XCTAssertTrue(controller.beginInAppWindowHotkeySessionForTesting())
        XCTAssertEqual(controller.modelForTesting.overlayStyle, .windowOnly)
        XCTAssertEqual(controller.modelForTesting.session?.mode, .windowCycle(appID: appID))
        let selectedWindowID = controller.modelForTesting.session?.selectedWindow?.id
        XCTAssertNotNil(selectedWindowID)

        controller.finishSelection()

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
                runtimeProjectionService: makeCurrentAppWindowProjectionService(
                    appID: appID,
                    runningApp: currentApp,
                    windows: windows
                )
            )
        )
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
    func testSwitcherPanelControllerGlobalHotkeyAdvanceAndReleaseCommitSession() {
        let releaseScheduler = ManualModifierReleaseObservationScheduler()
        let releaseEventSource = ManualModifierReleaseEventSource()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: RecordingRuntimeProjectionService(
                    appSwitcherApps: searchScenarioApps()
                )
            ),
            modifierReleaseObservationScheduler: releaseScheduler,
            modifierReleaseEventSource: releaseEventSource
        )

        var activatedTarget: ActivationTarget?
        controller.modelForTesting.activationOverride = { target, _ in
            activatedTarget = target
        }

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        let hotkeyInput = ManualHotkeyInputSource()
        hotkeyInput.register(on: controller, for: .globalAppSwitcher)
        controller.globalHotkeyHoldSetPressedOverride = true
        let initialSelectedAppID = controller.modelForTesting.selectedApp?.id

        hotkeyInput.emit(
            phase: .pressed,
            to: controller,
            for: .globalAppSwitcher
        )

        XCTAssertNotEqual(controller.modelForTesting.selectedApp?.id, initialSelectedAppID)

        controller.globalHotkeyHoldSetPressedOverride = false
        hotkeyInput.emit(
            phase: .released,
            to: controller,
            for: .globalAppSwitcher
        )

        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertTrue(controller.hasPendingModifierReleaseConfirmation)
        releaseScheduler.fireNext()

        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertNotNil(activatedTarget)
        XCTAssertEqual(releaseEventSource.activeObserverCount, 0)
    }

    @MainActor
    func testSwitcherPanelControllerCountsDistinctImmediateHotkeyEventsOnceEach() {
        let controller = makeAppSwitcherProjectionPanelController()
        let hotkeyInput = ManualHotkeyInputSource()
        hotkeyInput.register(on: controller, for: .globalAppSwitcher)

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.globalHotkeyHoldSetPressedOverride = true
        let initialAppID = controller.modelForTesting.selectedApp?.id

        let firstEvent = hotkeyInput.emit(
            phase: .pressed,
            to: controller,
            for: .globalAppSwitcher
        )
        let firstAdvancedAppID = controller.modelForTesting.selectedApp?.id
        hotkeyInput.deliver(
            firstEvent,
            to: controller,
            for: .globalAppSwitcher
        )
        XCTAssertEqual(
            controller.modelForTesting.selectedApp?.id,
            firstAdvancedAppID
        )

        hotkeyInput.emit(
            phase: .pressed,
            to: controller,
            for: .globalAppSwitcher
        )
        let secondAdvancedAppID = controller.modelForTesting.selectedApp?.id

        XCTAssertNotEqual(firstAdvancedAppID, initialAppID)
        XCTAssertNotEqual(secondAdvancedAppID, firstAdvancedAppID)
        XCTAssertEqual(controller.hotkeyInputOwner.inputGeneration, 2)
        controller.globalHotkeyHoldSetPressedOverride = false
        controller.globalMainKeySetPressedOverride = false
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerReplayGateEndsOnObservedRelease() {
        let releaseScheduler = ManualModifierReleaseObservationScheduler()
        let releaseEventSource = ManualModifierReleaseEventSource()
        let controller = makeAppSwitcherProjectionPanelController(
            modifierReleaseObservationScheduler: releaseScheduler,
            modifierReleaseEventSource: releaseEventSource
        )
        controller.modelForTesting.activationOverride = { _, _ in }
        let hotkeyInput = ManualHotkeyInputSource()
        hotkeyInput.register(on: controller, for: .globalAppSwitcher)

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.globalHotkeyHoldSetPressedOverride = true
        controller.globalMainKeySetPressedOverride = false
        let finishingEvent = hotkeyInput.emit(
            phase: .pressed,
            to: controller,
            for: .globalAppSwitcher
        )

        controller.finishSelection()

        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertTrue(controller.suppressHotkeyReplayUntilReleaseForTesting)
        XCTAssertEqual(releaseScheduler.pendingCount, 1)
        hotkeyInput.deliver(
            finishingEvent,
            to: controller,
            for: .globalAppSwitcher
        )
        hotkeyInput.emit(
            phase: .pressed,
            to: controller,
            for: .globalAppSwitcher
        )
        XCTAssertNil(controller.modelForTesting.session)

        controller.globalHotkeyHoldSetPressedOverride = false
        hotkeyInput.emit(
            phase: .released,
            to: controller,
            for: .globalAppSwitcher
        )

        XCTAssertFalse(controller.suppressHotkeyReplayUntilReleaseForTesting)
        XCTAssertEqual(releaseScheduler.pendingCount, 0)
        XCTAssertEqual(releaseEventSource.activeObserverCount, 0)

        controller.globalHotkeyHoldSetPressedOverride = true
        hotkeyInput.emit(
            phase: .pressed,
            to: controller,
            for: .globalAppSwitcher
        )
        XCTAssertNotNil(controller.modelForTesting.session)
        controller.globalHotkeyHoldSetPressedOverride = false
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerKeepsFirstModifierReleaseConfirmationWhenTriggersOverlap() {
        let releaseScheduler = ManualModifierReleaseObservationScheduler()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: RecordingRuntimeProjectionService(
                    appSwitcherApps: searchScenarioApps()
                )
            ),
            modifierReleaseObservationScheduler: releaseScheduler,
            modifierReleaseEventSource: ManualModifierReleaseEventSource()
        )
        var activatedTargets: [ActivationTarget] = []
        controller.modelForTesting.activationOverride = { target, _ in
            activatedTargets.append(target)
        }

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.globalHotkeyHoldSetPressedOverride = false

        controller.scheduleModifierReleaseConfirmation(trigger: "presentation_recovered")
        let releaseGeneration = controller.modifierReleaseConfirmationGeneration
        controller.scheduleModifierReleaseConfirmation(trigger: "flags_changed")

        XCTAssertEqual(controller.modifierReleaseConfirmationGeneration, releaseGeneration)
        XCTAssertEqual(
            controller.modifierReleaseState,
            .confirming(
                trigger: "presentation_recovered",
                generation: releaseGeneration,
                releasedSamples: 1
            )
        )

        XCTAssertEqual(releaseScheduler.pendingCount, 1)
        releaseScheduler.fireNext()

        XCTAssertEqual(activatedTargets.count, 1)
        XCTAssertFalse(controller.hasPendingModifierReleaseConfirmation)
    }

    @MainActor
    func testSwitcherPanelControllerReleaseConfirmationGenerationInvalidatesCanceledTask() {
        let releaseScheduler = ManualModifierReleaseObservationScheduler()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: RecordingRuntimeProjectionService(
                    appSwitcherApps: searchScenarioApps()
                )
            ),
            modifierReleaseObservationScheduler: releaseScheduler,
            modifierReleaseEventSource: ManualModifierReleaseEventSource()
        )

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.globalHotkeyHoldSetPressedOverride = false

        controller.scheduleModifierReleaseConfirmation(trigger: "generation_first")
        let firstGeneration = controller.modifierReleaseConfirmationGeneration
        XCTAssertTrue(controller.hasPendingModifierReleaseConfirmation)
        XCTAssertEqual(
            controller.modifierReleaseState,
            .confirming(
                trigger: "generation_first",
                generation: firstGeneration,
                releasedSamples: 1
            )
        )

        controller.cancelPendingModifierReleaseConfirmation()
        XCTAssertFalse(controller.hasPendingModifierReleaseConfirmation)
        XCTAssertEqual(controller.modifierReleaseConfirmationGeneration, firstGeneration + 1)
        XCTAssertFalse(
            controller.isModifierReleaseConfirmationGenerationCurrent(
                firstGeneration
            )
        )
        XCTAssertEqual(
            controller.modifierReleaseState,
            .canceled(reason: .explicitCancel, generation: firstGeneration)
        )

        controller.scheduleModifierReleaseConfirmation(trigger: "generation_second")
        let secondGeneration = controller.modifierReleaseConfirmationGeneration
        XCTAssertTrue(controller.hasPendingModifierReleaseConfirmation)
        XCTAssertEqual(
            controller.modifierReleaseState,
            .confirming(
                trigger: "generation_second",
                generation: secondGeneration,
                releasedSamples: 1
            )
        )

        XCTAssertEqual(controller.modifierReleaseConfirmationGeneration, secondGeneration)
        controller.cancelPendingModifierReleaseConfirmation()
        XCTAssertFalse(controller.hasPendingModifierReleaseConfirmation)
        XCTAssertEqual(releaseScheduler.pendingCount, 0)
        controller.cancelSelectionForTesting()
    }

    private func makeCurrentAppWindowProjectionService(
        appID: String,
        runningApp: NSRunningApplication,
        windows: [WindowCandidate]
    ) -> RecordingRuntimeProjectionService {
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
        let currentAppWindowPayload = RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: candidate.displayName,
                groupID: candidate.groupID,
                lastActiveAt: candidate.lastActiveAt,
                windowCount: windows.count,
                pid: runningApp.processIdentifier
            ),
            candidate: candidate,
            context: context,
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: runningApp)]
        )
        return RecordingRuntimeProjectionService(
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    currentAppWindowPayload: currentAppWindowPayload,
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
    private func makeAppSwitcherProjectionPanelController(
        apps: [AppSwitchCandidate]? = nil,
        modifierReleaseObservationScheduler:
            (any ModifierReleaseObservationScheduling)? = nil,
        modifierReleaseEventSource:
            (any ModifierReleaseEventObserving)? = nil,
        panelVisibilityRecoveryObservationScheduler:
            (any PanelVisibilityRecoveryObservationScheduling)? = nil
    ) -> SwitcherPanelController {
        SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: RecordingRuntimeProjectionService(
                    appSwitcherApps: apps ?? searchScenarioApps()
                )
            ),
            modifierReleaseObservationScheduler:
                modifierReleaseObservationScheduler,
            modifierReleaseEventSource: modifierReleaseEventSource,
            panelVisibilityRecoveryObservationScheduler:
                panelVisibilityRecoveryObservationScheduler
        )
    }

    @MainActor
    func testSwitcherPanelControllerModifierReleaseConfirmationPolicyOwnsTimingConstants() {
        let controller = SwitcherPanelController()

        XCTAssertEqual(controller.modifierReleaseConfirmationPolicy, .default)
        XCTAssertEqual(controller.modifierReleaseConfirmationSampleIntervalNs, 25_000_000)
        XCTAssertEqual(controller.modifierReleaseConfirmationSampleCount, 2)
        XCTAssertEqual(controller.modifierReleaseState, .idle)
    }

    @MainActor
    func testSwitcherPanelControllerHotkeyReplaySuppressionUsesReleaseStateGeneration() {
        let releaseScheduler = ManualModifierReleaseObservationScheduler()
        let releaseEventSource = ManualModifierReleaseEventSource()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(),
            modifierReleaseObservationScheduler: releaseScheduler,
            modifierReleaseEventSource: releaseEventSource
        )
        controller.globalHotkeyHoldSetPressedOverride = true
        controller.globalMainKeySetPressedOverride = false

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

        controller.globalHotkeyHoldSetPressedOverride = false
        releaseEventSource.emitInputTransition()

        XCTAssertFalse(controller.suppressHotkeyReplayUntilReleaseForTesting)
        XCTAssertEqual(releaseScheduler.pendingCount, 0)
        XCTAssertEqual(
            controller.modifierReleaseState,
            .replaySuppressionEnded(trigger: "state_machine", generation: generation)
        )
    }

    @MainActor
    func testSwitcherPanelControllerPresentationSessionGenerationTracksSessionLifecycle() {
        let releaseScheduler = ManualModifierReleaseObservationScheduler()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: RecordingRuntimeProjectionService(
                    appSwitcherApps: searchScenarioApps()
                )
            ),
            modifierReleaseObservationScheduler: releaseScheduler,
            modifierReleaseEventSource: ManualModifierReleaseEventSource()
        )

        XCTAssertEqual(controller.presentationSessionGeneration, 0)
        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        let firstSessionGeneration = controller.presentationSessionGeneration
        XCTAssertEqual(firstSessionGeneration, 1)
        XCTAssertTrue(controller.isPresentationSessionGenerationCurrent(firstSessionGeneration))

        controller.globalHotkeyHoldSetPressedOverride = false
        controller.globalMainKeySetPressedOverride = false
        controller.scheduleModifierReleaseConfirmation(trigger: "session_generation")
        XCTAssertTrue(controller.hasPendingModifierReleaseConfirmation)

        controller.cancelSelectionForTesting()

        XCTAssertFalse(controller.hasPendingModifierReleaseConfirmation)
        XCTAssertFalse(controller.isPresentationSessionGenerationCurrent(firstSessionGeneration))
        XCTAssertEqual(controller.presentationSessionGeneration, firstSessionGeneration + 1)
        XCTAssertFalse(controller.suppressHotkeyReplayUntilReleaseForTesting)

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
        let runtimeService = RecordingRuntimeProjectionService(appSwitcherApps: fastApps)
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(runtimeProjectionService: runtimeService)
        )
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
    func testSwitcherPanelControllerAppSwitcherProjectionCommitRefreshesOpenSession() {
        let initialApps = [
            AppSwitchCandidate(
                id: "com.example.alpha",
                displayName: "Alpha",
                groupID: "alpha",
                lastActiveAt: 100,
                windows: []
            ),
            AppSwitchCandidate(
                id: "com.example.beta",
                displayName: "Beta",
                groupID: "beta",
                lastActiveAt: 90,
                windows: []
            )
        ]
        let updatedApps = [
            initialApps[0],
            AppSwitchCandidate(
                id: "com.example.beta",
                displayName: "Beta",
                groupID: "beta",
                lastActiveAt: 90,
                windows: [
                    WindowCandidate(
                        id: "beta-1",
                        title: "Beta One",
                        isMinimized: false,
                        lastActiveAt: 30
                    )
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.gamma",
                displayName: "Gamma",
                groupID: "gamma",
                lastActiveAt: 80,
                windows: []
            )
        ]
        let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherApps: initialApps)
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        )

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        let selectedAppIDBeforeUpdate = controller.modelForTesting.selectedApp?.id
        XCTAssertEqual(controller.modelForTesting.session?.apps.map(\.id), initialApps.map(\.id))

        runtimeProjectionService.installAppSwitcherProjection(apps: updatedApps, generatedAt: 20)
        XCTAssertTrue(controller.handleAppSwitcherProjectionDidUpdateForTesting())

        XCTAssertEqual(controller.modelForTesting.session?.apps.map(\.id), updatedApps.map(\.id))
        XCTAssertEqual(controller.modelForTesting.selectedApp?.id, selectedAppIDBeforeUpdate)
        XCTAssertEqual(runtimeProjectionService.appSwitcherProjectionReadCount(), 2)
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherMaintenanceRequestsRecorded(),
            [.switcherSessionStarted]
        )
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
        let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherProjection: projection)
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        model.runtimeProjectionMaintenanceEnabled = false

        XCTAssertTrue(model.startSession(triggerDirection: .forward))

        assertAppSwitcherProjectionRead(
            from: runtimeProjectionService,
            maintenanceRequests: []
        )
        XCTAssertEqual(model.session?.apps.map(\.id), apps.map(\.id))
        XCTAssertEqual(model.session?.apps.flatMap(\.windows).count, 0)
    }

    @MainActor
    func testLiveSwitcherModelRequestsMaintenanceWhenAppSwitcherProjectionIsMissing() {
        let runtimeProjectionService = RecordingRuntimeProjectionService()
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        XCTAssertFalse(model.startSession(triggerDirection: .forward))

        XCTAssertNil(model.session)
        assertAppSwitcherProjectionRead(
            from: runtimeProjectionService,
            maintenanceRequests: [.switcherSessionStarted]
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
        let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherProjection: projection)
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))

        assertAppSwitcherProjectionRead(
            from: runtimeProjectionService,
            maintenanceRequests: [.switcherSessionStarted]
        )
        XCTAssertEqual(model.session?.apps.map(\.id), [appID])
        XCTAssertEqual(model.session?.selectedApp.windows.map(\.id), [])

        model.handle(.downArrow)

        XCTAssertEqual(model.session?.mode, .appCycle)
        XCTAssertNil(model.session?.selectedWindow)
    }

    @MainActor
    func testLiveSwitcherModelSelectedAppWindowProjectionUsesRuntimeProjectionWithoutHomeSampling() {
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
        let selectedCurrentAppWindowPayload = RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Projected Runtime Source",
                groupID: "projected-runtime-source",
                lastActiveAt: 100,
                windowCount: windows.count,
                pid: runningApp.processIdentifier
            ),
            candidate: windowCandidate,
            context: context,
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: runningApp)]
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
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [appOnlyCandidate],
                contextsByID: [:],
                freshness: freshness
            ),
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    currentAppWindowPayload: selectedCurrentAppWindowPayload,
                    freshness: freshness
                )
            ]
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        model.runtimeProjectionMaintenanceEnabled = false

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.scheduleSelectedAppWindowProjectionIfNeeded(for: appID))

        XCTAssertEqual(model.session?.selectedApp.windows.map(\.id), ["projected-window-1", "projected-window-2"])
        XCTAssertEqual(model.runtimeContextsByID[appID]?.windowsByID["projected-window-1"]?.title, "Projected One")
    }

    @MainActor
    func testLiveSwitcherModelKeepsStaleSelectedAppWindowProjectionPendingAndSignalsRuntimeRepair() {
        let appID = "com.example.stale-projected-current-app"
        let runningApp = NSRunningApplication.current
        let appOnlyCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Stale Projected Runtime Source",
            groupID: "stale-projected-runtime-source",
            lastActiveAt: 100,
            windows: []
        )
        let windows = [
            WindowCandidate(id: "stale-projected-window-1", title: "Stale Projected One", isMinimized: false, lastActiveAt: 20),
            WindowCandidate(id: "stale-projected-window-2", title: "Stale Projected Two", isMinimized: false, lastActiveAt: 10)
        ]
        let windowCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Stale Projected Runtime Source",
            groupID: "stale-projected-runtime-source",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(appID: appID, runningApp: runningApp, windows: windows)
        let selectedCurrentAppWindowPayload = RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Stale Projected Runtime Source",
                groupID: "stale-projected-runtime-source",
                lastActiveAt: 100,
                windowCount: windows.count,
                pid: runningApp.processIdentifier
            ),
            candidate: windowCandidate,
            context: context,
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: runningApp)]
        )
        let appSwitcherFreshness = RuntimeProjectionFreshness(
            generatedAt: 11,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let currentAppFreshness = RuntimeProjectionFreshness(
            generatedAt: 12,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [appID],
            dirtyPIDs: [runningApp.processIdentifier],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: ["appWindows:\(appID)"],
            isCompleteForScope: false
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [appOnlyCandidate],
                contextsByID: [appID: context],
                freshness: appSwitcherFreshness
            ),
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    currentAppWindowPayload: selectedCurrentAppWindowPayload,
                    freshness: currentAppFreshness
                )
            ]
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        model.runtimeProjectionMaintenanceEnabled = false

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertFalse(model.scheduleSelectedAppWindowProjectionIfNeeded(for: appID))

        XCTAssertEqual(model.session?.mode, .appCycle)
        XCTAssertEqual(model.session?.selectedApp.windows.map(\.id), [])
        XCTAssertEqual(runtimeProjectionService.currentAppWindowProjectionReadCount(appID: appID), 1)
        XCTAssertEqual(runtimeProjectionService.selectedCurrentAppWindowChangeSignalsRecorded().map(\.appID), [appID])
        XCTAssertEqual(
            runtimeProjectionService.selectedCurrentAppWindowChangeSignalsRecorded().map(\.pid),
            [runningApp.processIdentifier]
        )
    }

    @MainActor
    func testLiveSwitcherModelDoesNotApplyStaleSelectedAppWindowProjectionFromReadyPoll() {
        let appID = "com.example.stale-ready-current-app"
        let runningApp = NSRunningApplication.current
        let appOnlyCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Stale Ready Runtime Source",
            groupID: "stale-ready-runtime-source",
            lastActiveAt: 100,
            windows: []
        )
        let windows = [
            WindowCandidate(id: "stale-ready-window-1", title: "Stale Ready One", isMinimized: false, lastActiveAt: 20)
        ]
        let windowCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Stale Ready Runtime Source",
            groupID: "stale-ready-runtime-source",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(appID: appID, runningApp: runningApp, windows: windows)
        let selectedCurrentAppWindowPayload = RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Stale Ready Runtime Source",
                groupID: "stale-ready-runtime-source",
                lastActiveAt: 100,
                windowCount: windows.count,
                pid: runningApp.processIdentifier
            ),
            candidate: windowCandidate,
            context: context,
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: runningApp)]
        )
        let appSwitcherFreshness = RuntimeProjectionFreshness(
            generatedAt: 11,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let currentAppFreshness = RuntimeProjectionFreshness(
            generatedAt: 12,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [appID],
            dirtyPIDs: [runningApp.processIdentifier],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: ["appWindows:\(appID)"],
            isCompleteForScope: false
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [appOnlyCandidate],
                contextsByID: [appID: context],
                freshness: appSwitcherFreshness
            ),
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    currentAppWindowPayload: selectedCurrentAppWindowPayload,
                    freshness: currentAppFreshness
                )
            ]
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        model.runtimeProjectionMaintenanceEnabled = false

        XCTAssertTrue(model.startSession(triggerDirection: .forward))

        XCTAssertFalse(model.applySelectedAppWindowProjectionIfReady(for: appID))
        XCTAssertEqual(model.session?.mode, .appCycle)
        XCTAssertEqual(model.session?.selectedApp.windows.map(\.id), [])
        XCTAssertEqual(runtimeProjectionService.currentAppWindowProjectionReadCount(appID: appID), 1)
        XCTAssertTrue(runtimeProjectionService.selectedCurrentAppWindowChangeSignalsRecorded().isEmpty)
    }

    @MainActor
    func testLiveSwitcherModelReplaysManualWindowLayerEntryAfterSelectedAppProjectionApplies() {
        let appID = "com.example.projected-window-layer-entry"
        let runningApp = NSRunningApplication.current
        let appOnlyCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Projected Window Layer Entry",
            groupID: "projected-window-layer-entry",
            lastActiveAt: 100,
            windows: []
        )
        let windows = [
            WindowCandidate(id: "projected-entry-1", title: "Projected Entry One", isMinimized: false, lastActiveAt: 20),
            WindowCandidate(id: "projected-entry-2", title: "Projected Entry Two", isMinimized: false, lastActiveAt: 10)
        ]
        let windowCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Projected Window Layer Entry",
            groupID: "projected-window-layer-entry",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(appID: appID, runningApp: runningApp, windows: windows)
        let selectedCurrentAppWindowPayload = RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Projected Window Layer Entry",
                groupID: "projected-window-layer-entry",
                lastActiveAt: 100,
                windowCount: windows.count,
                pid: runningApp.processIdentifier
            ),
            candidate: windowCandidate,
            context: context,
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: runningApp)]
        )
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 12,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [appOnlyCandidate],
                contextsByID: [appID: context],
                freshness: freshness
            ),
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    currentAppWindowPayload: selectedCurrentAppWindowPayload,
                    freshness: freshness
                )
            ]
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        model.runtimeProjectionMaintenanceEnabled = false

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        model.handle(.downArrow)
        XCTAssertEqual(model.session?.mode, .appCycle)

        XCTAssertTrue(model.scheduleSelectedAppWindowProjectionIfNeeded(for: appID))

        XCTAssertEqual(model.session?.mode, .windowCycle(appID: appID))
        XCTAssertEqual(model.session?.selectedApp.windows.map(\.id), ["projected-entry-1", "projected-entry-2"])
        XCTAssertEqual(runtimeProjectionService.currentAppWindowProjectionReadCount(appID: appID), 1)
        XCTAssertTrue(runtimeProjectionService.selectedCurrentAppWindowChangeSignalsRecorded().isEmpty)
    }

    @MainActor
    func testLiveSwitcherModelKeepsWindowLayerSnapshotWhenCurrentAppProjectionRefreshes() {
        let appID = "com.example.active-window-cycle-refresh"
        let runningApp = NSRunningApplication.current
        let initialWindows = [
            WindowCandidate(id: "fullscreen", title: "Chrome Fullscreen Tab", isMinimized: false, lastActiveAt: 40),
            WindowCandidate(id: "normal", title: "Chrome Normal Tab", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "incognito", title: "Chrome Incognito Tab", isMinimized: false, lastActiveAt: 20),
            WindowCandidate(id: "second-fullscreen", title: "Chrome Second Fullscreen Tab", isMinimized: false, lastActiveAt: 10)
        ]
        let refreshedWindows = [
            WindowCandidate(id: "normal", title: "Chrome Normal Tab", isMinimized: false, lastActiveAt: 50),
            WindowCandidate(id: "fullscreen", title: "Chrome Fullscreen Tab", isMinimized: false, lastActiveAt: 45),
            WindowCandidate(id: "incognito", title: "Chrome Incognito Tab", isMinimized: false, lastActiveAt: 20),
            WindowCandidate(id: "second-fullscreen", title: "Chrome Second Fullscreen Tab", isMinimized: false, lastActiveAt: 10)
        ]
        let initialCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Chrome Fixture",
            groupID: "chrome-fixture",
            lastActiveAt: 100,
            windows: initialWindows
        )
        let refreshedCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Chrome Fixture",
            groupID: "chrome-fixture",
            lastActiveAt: 100,
            windows: refreshedWindows
        )
        let context = makeRuntimeAppContext(appID: appID, runningApp: runningApp, windows: refreshedWindows)
        let refreshedPayload = RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Chrome Fixture",
                groupID: "chrome-fixture",
                lastActiveAt: 100,
                windowCount: refreshedWindows.count,
                pid: runningApp.processIdentifier
            ),
            candidate: refreshedCandidate,
            context: context,
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: runningApp)]
        )
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 12,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [initialCandidate],
                contextsByID: [appID: context],
                freshness: freshness
            ),
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    currentAppWindowPayload: refreshedPayload,
                    freshness: freshness
                )
            ]
        )
        let model = LiveSwitcherModel(
            windowRecencyTracker: RuntimeWindowRecencyTracker(),
            runtimeProjectionService: runtimeProjectionService
        )
        model.runtimeProjectionMaintenanceEnabled = false

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        model.handle(.downArrow)
        XCTAssertEqual(model.session?.selectedWindow?.id, "fullscreen")
        model.handle(.rightArrow)
        XCTAssertEqual(model.session?.selectedWindow?.id, "normal")

        XCTAssertFalse(model.applyCurrentAppWindowProjectionIfReady(appID: appID))
        XCTAssertEqual(
            runtimeProjectionService.currentAppWindowProjectionReadCount(appID: appID),
            0
        )
        XCTAssertEqual(
            model.session?.selectedApp.windows.map(\.id),
            ["fullscreen", "normal", "incognito", "second-fullscreen"]
        )
        XCTAssertEqual(model.session?.selectedWindow?.id, "normal")

        model.handle(.rightArrow)

        XCTAssertEqual(model.session?.selectedWindow?.id, "incognito")
    }

    @MainActor
    func testLiveSwitcherModelKeepsWindowLayerSnapshotWhenAppSwitcherProjectionRefreshes() {
        let appID = "com.example.active-window-cycle-app-refresh"
        let runningApp = NSRunningApplication.current
        let initialWindows = [
            WindowCandidate(id: "fullscreen", title: "Chrome Fullscreen Tab", isMinimized: false, lastActiveAt: 40),
            WindowCandidate(id: "normal", title: "Chrome Normal Tab", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "incognito", title: "Chrome Incognito Tab", isMinimized: false, lastActiveAt: 20),
            WindowCandidate(id: "second-fullscreen", title: "Chrome Second Fullscreen Tab", isMinimized: false, lastActiveAt: 10)
        ]
        let refreshedWindows = [
            WindowCandidate(id: "normal", title: "Chrome Normal Tab", isMinimized: false, lastActiveAt: 50),
            WindowCandidate(id: "fullscreen", title: "Chrome Fullscreen Tab", isMinimized: false, lastActiveAt: 45),
            WindowCandidate(id: "incognito", title: "Chrome Incognito Tab", isMinimized: false, lastActiveAt: 20),
            WindowCandidate(id: "second-fullscreen", title: "Chrome Second Fullscreen Tab", isMinimized: false, lastActiveAt: 10)
        ]
        let initialCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Chrome Fixture",
            groupID: "chrome-fixture",
            lastActiveAt: 100,
            windows: initialWindows
        )
        let refreshedCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Chrome Fixture",
            groupID: "chrome-fixture",
            lastActiveAt: 100,
            windows: refreshedWindows
        )
        let context = makeRuntimeAppContext(appID: appID, runningApp: runningApp, windows: refreshedWindows)
        let refreshedPayload = RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Chrome Fixture",
                groupID: "chrome-fixture",
                lastActiveAt: 100,
                windowCount: refreshedWindows.count,
                pid: runningApp.processIdentifier
            ),
            candidate: refreshedCandidate,
            context: context,
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: runningApp)]
        )
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 12,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [initialCandidate],
                contextsByID: [appID: context],
                freshness: freshness
            ),
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    currentAppWindowPayload: refreshedPayload,
                    freshness: freshness
                )
            ]
        )
        let model = LiveSwitcherModel(
            windowRecencyTracker: RuntimeWindowRecencyTracker(),
            runtimeProjectionService: runtimeProjectionService
        )
        model.runtimeProjectionMaintenanceEnabled = false

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        model.handle(.downArrow)
        model.handle(.rightArrow)
        XCTAssertEqual(model.session?.selectedWindow?.id, "normal")

        runtimeProjectionService.installAppSwitcherProjection(
            apps: [refreshedCandidate],
            contextsByID: [appID: context],
            generatedAt: 13
        )

        XCTAssertFalse(model.handleAppSwitcherProjectionDidUpdate())
        XCTAssertEqual(
            model.session?.selectedApp.windows.map(\.id),
            ["fullscreen", "normal", "incognito", "second-fullscreen"]
        )
        XCTAssertEqual(model.session?.selectedWindow?.id, "normal")

        model.handle(.rightArrow)

        XCTAssertEqual(model.session?.selectedWindow?.id, "incognito")
    }

    @MainActor
    func testLiveSwitcherModelSelectedAppWindowProjectionSignalsRuntimeRepairWhenProjectionIsMissing() {
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
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [appOnlyCandidate],
                contextsByID: [appID: context],
                freshness: freshness
            )
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        model.runtimeProjectionMaintenanceEnabled = false

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertTrue(model.scheduleSelectedAppWindowProjectionIfNeeded(for: appID))

        XCTAssertTrue(runtimeProjectionService.appWindowChangeSignalsRecorded().isEmpty)
        XCTAssertEqual(runtimeProjectionService.selectedCurrentAppWindowChangeSignalsRecorded().map(\.appID), [appID])
        XCTAssertEqual(
            runtimeProjectionService.selectedCurrentAppWindowChangeSignalsRecorded().map(\.pid),
            [runningApp.processIdentifier]
        )
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
        let context = makeRuntimeAppContext(appID: appID, runningApp: runningApp, windows: windows)
        let currentAppWindowPayload = RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Focused Runtime Projection",
                groupID: "focused-runtime-projection",
                lastActiveAt: 100,
                windowCount: windows.count,
                pid: runningApp.processIdentifier
            ),
            candidate: candidate,
            context: context,
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: runningApp)]
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    currentAppWindowPayload: currentAppWindowPayload,
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
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        XCTAssertTrue(model.startFocusedAppWindowSession(triggerDirection: .forward))

        XCTAssertEqual(runtimeProjectionService.focusedCurrentAppWindowProjectionReadCount(), 1)
        XCTAssertEqual(runtimeProjectionService.currentAppWindowProjectionReadCount(appID: appID), 1)
        XCTAssertTrue(runtimeProjectionService.selectedCurrentAppWindowChangeSignalsRecorded().isEmpty)
        XCTAssertEqual(model.session?.mode, .windowCycle(appID: appID))
        XCTAssertEqual(model.session?.selectedApp.windows.map(\.id), ["focused-projected-1", "focused-projected-2"])
    }

    @MainActor
    func testLiveSwitcherModelFocusedWindowSessionSignalsRuntimeRepairWhenProjectionIsMissing() {
        let runningApp = NSRunningApplication.current
        let appID = runningApp.bundleIdentifier ?? "pid:\(runningApp.processIdentifier)"
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            focusedCurrentAppWindowProjectionRead: RuntimeFocusedCurrentAppWindowProjectionRead(
                appID: appID,
                pid: runningApp.processIdentifier,
                projection: nil
            )
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        XCTAssertFalse(model.startFocusedAppWindowSession(triggerDirection: .forward))

        XCTAssertTrue(runtimeProjectionService.appWindowChangeSignalsRecorded().isEmpty)
        XCTAssertEqual(runtimeProjectionService.selectedCurrentAppWindowChangeSignalsRecorded().map(\.appID), [appID])
        XCTAssertEqual(
            runtimeProjectionService.selectedCurrentAppWindowChangeSignalsRecorded().map(\.pid),
            [runningApp.processIdentifier]
        )
        XCTAssertEqual(runtimeProjectionService.focusedCurrentAppWindowProjectionReadCount(), 1)
        XCTAssertEqual(runtimeProjectionService.currentAppWindowProjectionReadCount(appID: appID), 1)
        XCTAssertNil(model.session)
    }

    @MainActor
    func testLiveSwitcherModelFocusedWindowSessionUsesStaleCommittedProjectionAsDegradedRead() {
        let runningApp = NSRunningApplication.current
        let appID = runningApp.bundleIdentifier ?? "pid:\(runningApp.processIdentifier)"
        let windows = [
            WindowCandidate(id: "stale-focused-projected-1", title: "Stale Focused One", isMinimized: false, lastActiveAt: 20),
            WindowCandidate(id: "stale-focused-projected-2", title: "Stale Focused Two", isMinimized: false, lastActiveAt: 10)
        ]
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: "Stale Focused Runtime Projection",
            groupID: "stale-focused-runtime-projection",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(appID: appID, runningApp: runningApp, windows: windows)
        let currentAppWindowPayload = RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Stale Focused Runtime Projection",
                groupID: "stale-focused-runtime-projection",
                lastActiveAt: 100,
                windowCount: windows.count,
                pid: runningApp.processIdentifier
            ),
            candidate: candidate,
            context: context,
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: runningApp)]
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    currentAppWindowPayload: currentAppWindowPayload,
                    freshness: RuntimeProjectionFreshness(
                        generatedAt: 12,
                        sourceGeneration: RuntimeReadModelGeneration(projection: 1),
                        dirtyAppIDs: [appID],
                        dirtyPIDs: [runningApp.processIdentifier],
                        dirtyCGWindowIDs: [],
                        pendingRepairScopes: ["appWindows:\(appID)"],
                        isCompleteForScope: false
                    )
                )
            ]
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        XCTAssertTrue(model.startFocusedAppWindowSession(triggerDirection: .forward))

        XCTAssertEqual(runtimeProjectionService.focusedCurrentAppWindowProjectionReadCount(), 1)
        XCTAssertEqual(runtimeProjectionService.currentAppWindowProjectionReadCount(appID: appID), 1)
        XCTAssertEqual(runtimeProjectionService.selectedCurrentAppWindowChangeSignalsRecorded().map(\.appID), [appID])
        XCTAssertEqual(
            runtimeProjectionService.selectedCurrentAppWindowChangeSignalsRecorded().map(\.pid),
            [runningApp.processIdentifier]
        )
        XCTAssertEqual(model.session?.mode, .windowCycle(appID: appID))
        XCTAssertEqual(
            model.session?.selectedApp.windows.map(\.id),
            ["stale-focused-projected-1", "stale-focused-projected-2"]
        )
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
    func testSwitcherPanelControllerFlagsChangedReleaseConfirmationEndsSession() {
        let releaseScheduler = ManualModifierReleaseObservationScheduler()
        let releaseEventSource = ManualModifierReleaseEventSource()
        let controller = makeAppSwitcherProjectionPanelController(
            modifierReleaseObservationScheduler: releaseScheduler,
            modifierReleaseEventSource: releaseEventSource
        )

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.globalHotkeyHoldSetPressedOverride = false
        guard
            let holdModifierKey = controller.activeHotkeyHoldKeys()
                .orderedKeys.first(where: { $0.modifier != nil })
        else {
            return XCTFail("Expected a modifier in the active hotkey hold set")
        }

        controller.handleFlagsChangedForTesting(
            Self.makeFlagsChangedEvent(keyCode: holdModifierKey.keyCode)
        )

        XCTAssertTrue(controller.hasPendingModifierReleaseConfirmation)
        XCTAssertEqual(releaseEventSource.activeObserverCount, 1)
        releaseScheduler.fireNext()

        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertEqual(releaseEventSource.activeObserverCount, 0)
    }

    @MainActor
    func testSwitcherPanelControllerMouseDownOutsideSearchCancelsSession() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let controller = SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService: RecordingRuntimeProjectionService(
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
    func testSwitcherPanelPresentationReadsRuntimeSpaceTopologyProjectionForFullscreenLevel() {
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherApps: searchScenarioApps(),
            spaceTopologyProjection: makeCompleteCurrentSpaceFullscreenProjectionForTesting()
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        let controller = SwitcherPanelController(model: model)

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())

        XCTAssertGreaterThan(
            controller.panel.level.rawValue,
            SwitcherPanelWindowConfiguration.level.rawValue
        )
        XCTAssertEqual(runtimeProjectionService.spaceTopologyProjectionReadCount(), 1)
        XCTAssertEqual(runtimeProjectionService.spaceTopologyChangeSignalCount(), 0)
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelPresentationSignalsRuntimeWhenSpaceTopologyProjectionIsMissing() {
        let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherApps: searchScenarioApps())
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        let controller = SwitcherPanelController(model: model)

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())

        XCTAssertEqual(controller.panel.level, SwitcherPanelWindowConfiguration.level)
        XCTAssertEqual(runtimeProjectionService.spaceTopologyProjectionReadCount(), 1)
        XCTAssertEqual(runtimeProjectionService.spaceTopologyChangeSignalCount(), 1)
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelPresentationFailsClosedForIncompleteSpaceTopologyProjection() {
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherApps: searchScenarioApps(),
            spaceTopologyProjection: makeCompleteCurrentSpaceFullscreenProjectionForTesting(
                isCompleteForScope: false,
                pendingRepairScopes: ["spaceTopology"]
            )
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        let controller = SwitcherPanelController(model: model)

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())

        XCTAssertEqual(controller.panel.level, SwitcherPanelWindowConfiguration.level)
        XCTAssertEqual(runtimeProjectionService.spaceTopologyProjectionReadCount(), 1)
        XCTAssertEqual(runtimeProjectionService.spaceTopologyChangeSignalCount(), 0)
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerRecoverableOcclusionKeepsSessionVisible() {
        let recoveryScheduler =
            ManualPanelVisibilityRecoveryObservationScheduler()
        let occlusionController =
            makeAppSwitcherProjectionPanelController(
                panelVisibilityRecoveryObservationScheduler:
                    recoveryScheduler
            )
        occlusionController.globalHotkeyHoldSetPressedOverride = true

        XCTAssertTrue(occlusionController.beginGlobalHotkeySessionForTesting())
        occlusionController.panelOcclusionStateOverride = []

        occlusionController.handlePanelOcclusionStateDidChangeForTesting()
        occlusionController.panelVisibilityOverride = false
        recoveryScheduler.fireConditionReadback()
        occlusionController.panelVisibilityOverride = true
        occlusionController.panelOcclusionStateOverride = .visible
        occlusionController.handlePanelDidExposeForTesting()

        guard case .visibleConfirmed =
            occlusionController.panelVisibilityRecoveryState
        else {
            return XCTFail(
                "Occlusion recovery must complete from window evidence."
            )
        }
        XCTAssertNotNil(occlusionController.modelForTesting.session)
        XCTAssertFalse(occlusionController.suppressHotkeyReplayUntilReleaseForTesting)
    }

    @MainActor
    func testSwitcherPanelControllerDelayedAutoEnterAppliesSelectedProjectionCommittedAfterDirtySignal() {
        let currentApp = NSRunningApplication.current
        let appID = "com.example.deferred-selected-projection"
        let scheduler =
            ManualDelayedWindowLayerEntryScheduler()
        let windows = [
            WindowCandidate(id: "deferred-after-dirty-1", title: "Deferred One", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "deferred-after-dirty-2", title: "Deferred Two", isMinimized: false, lastActiveAt: 20)
        ]
        let appOnlyCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Deferred Projection",
            groupID: "deferred",
            lastActiveAt: 100,
            windows: []
        )
        let windowCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Deferred Projection",
            groupID: "deferred",
            lastActiveAt: 100,
            windows: windows
        )
        let emptyContext = makeRuntimeAppContext(appID: appID, runningApp: currentApp, windows: [])
        let repairedContext = makeRuntimeAppContext(appID: appID, runningApp: currentApp, windows: windows)
        let selectedCurrentAppWindowPayload = RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Deferred Projection",
                groupID: "deferred",
                lastActiveAt: 100,
                windowCount: windows.count,
                pid: currentApp.processIdentifier
            ),
            candidate: windowCandidate,
            context: repairedContext,
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: currentApp)]
        )
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 12,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [appOnlyCandidate],
                contextsByID: [appID: emptyContext],
                freshness: freshness
            )
        )
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: runtimeProjectionService
            ),
            delayedWindowLayerEntryScheduler: scheduler
        )
        controller.windowLayerPresentationDelayOverride = 0.05

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        XCTAssertEqual(controller.modelForTesting.session?.selectedApp.windows.count, 0)

        controller.scheduleDelayedWindowLayerEntryForTesting()

        XCTAssertEqual(
            runtimeProjectionService
                .selectedCurrentAppWindowChangeSignalsRecorded()
                .map(\.appID),
            [appID]
        )
        XCTAssertEqual(runtimeProjectionService.currentAppWindowProjectionReadCount(appID: appID), 1)
        runtimeProjectionService.setCurrentAppWindowProjection(
            RuntimeCurrentAppWindowProjection(
                appID: appID,
                currentAppWindowPayload: selectedCurrentAppWindowPayload,
                freshness: freshness
            ),
            appID: appID
        )
        XCTAssertTrue(
            controller.handleCurrentAppWindowProjectionDidUpdateForTesting(
                appID: appID
            )
        )
        XCTAssertGreaterThanOrEqual(
            runtimeProjectionService.currentAppWindowProjectionReadCount(appID: appID),
            2
        )
        XCTAssertEqual(
            controller.modelForTesting.session?.mode,
            .appCycle
        )
        XCTAssertEqual(
            controller.modelForTesting.session?.selectedApp.windows.map(\.id),
            ["deferred-after-dirty-1", "deferred-after-dirty-2"]
        )

        XCTAssertTrue(scheduler.fireNextDeadline())
        XCTAssertEqual(
            controller.modelForTesting.session?.mode,
            .windowCycle(appID: appID)
        )
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerCurrentAppProjectionCommitAppliesPendingManualWindowLayerEntry() {
        let currentApp = NSRunningApplication.current
        let appID = "com.example.manual-commit-projection"
        let windows = [
            WindowCandidate(id: "manual-commit-1", title: "Manual Commit One", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "manual-commit-2", title: "Manual Commit Two", isMinimized: false, lastActiveAt: 20)
        ]
        let appOnlyCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Manual Commit Projection",
            groupID: "manual-commit",
            lastActiveAt: 100,
            windows: []
        )
        let windowCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Manual Commit Projection",
            groupID: "manual-commit",
            lastActiveAt: 100,
            windows: windows
        )
        let emptyContext = makeRuntimeAppContext(appID: appID, runningApp: currentApp, windows: [])
        let repairedContext = makeRuntimeAppContext(appID: appID, runningApp: currentApp, windows: windows)
        let selectedCurrentAppWindowPayload = RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Manual Commit Projection",
                groupID: "manual-commit",
                lastActiveAt: 100,
                windowCount: windows.count,
                pid: currentApp.processIdentifier
            ),
            candidate: windowCandidate,
            context: repairedContext,
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: currentApp)]
        )
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 12,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [appOnlyCandidate],
                contextsByID: [appID: emptyContext],
                freshness: freshness
            )
        )
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: runtimeProjectionService
            )
        )
        controller.windowLayerPresentationDelayOverride = 30

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.advance(.downArrow)
        XCTAssertEqual(runtimeProjectionService.selectedCurrentAppWindowChangeSignalsRecorded().map(\.appID), [appID])
        XCTAssertEqual(runtimeProjectionService.currentAppWindowProjectionReadCount(appID: appID), 1)

        runtimeProjectionService.setCurrentAppWindowProjection(
            RuntimeCurrentAppWindowProjection(
                appID: appID,
                currentAppWindowPayload: selectedCurrentAppWindowPayload,
                freshness: freshness
            ),
            appID: appID
        )
        XCTAssertTrue(controller.handleCurrentAppWindowProjectionDidUpdateForTesting(appID: appID))

        XCTAssertEqual(runtimeProjectionService.currentAppWindowProjectionReadCount(appID: appID), 2)
        XCTAssertEqual(controller.modelForTesting.session?.mode, .windowCycle(appID: appID))
        XCTAssertEqual(
            controller.modelForTesting.session?.selectedApp.windows.map(\.id),
            ["manual-commit-1", "manual-commit-2"]
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
        let runtimeProjectionService = RecordingRuntimeProjectionService(
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
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))

        assertAppSwitcherProjectionRead(
            from: runtimeProjectionService,
            maintenanceRequests: [.switcherSessionStarted]
        )
        XCTAssertEqual(model.lastRuntimeProjectionMaintenanceDiagnostic?.result, "maintenanceRequested")
        XCTAssertEqual(model.lastRuntimeProjectionMaintenanceDiagnostic?.applyGeneration, nil)
    }

    @MainActor
    func testSwitcherPanelControllerShowSkipsHidingRegularWindowsWhileAppIsActive() {
        let controller = makeAppSwitcherProjectionPanelController()
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
        let controller = makeAppSwitcherProjectionPanelController()
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
        let controller = makeAppSwitcherProjectionPanelController(
            apps: layoutScenarioApps(count: 5)
        )

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
        let controller = makeAppSwitcherProjectionPanelController(
            apps: layoutScenarioApps(count: 20)
        )

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
        let app = manyWindowLayoutApp(windowCount: 100)
        let controller = makeAppSwitcherProjectionPanelController(apps: [app])

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
        let app = manyWindowLayoutApp(windowCount: 100)
        let controller = makeAppSwitcherProjectionPanelController(apps: [app])
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

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

    func makeCompleteCurrentSpaceFullscreenProjectionForTesting(
        currentSpaceID: Int = 7,
        spaceGeneration: UInt64 = 1,
        isCompleteForScope: Bool = true,
        pendingRepairScopes: Set<String> = []
    ) -> RuntimeSpaceTopologyProjection {
        let displays = NSScreen.screens.compactMap { screen -> RuntimeDisplaySpaceSignature? in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
            let displayID = CGDirectDisplayID(number.uint32Value)
            return RuntimeDisplaySpaceSignature(
                displayID: displayID,
                currentSpaceID: currentSpaceID,
                spaceIDs: [currentSpaceID],
                windowIDsBySpaceID: [
                    currentSpaceID: [240_001]
                ],
                fullscreenWindowIDBySpaceID: [
                    currentSpaceID: 240_001
                ]
            )
        }
        let fallbackDisplays = displays.isEmpty
            ? [
                RuntimeDisplaySpaceSignature(
                    displayID: nil,
                    currentSpaceID: currentSpaceID,
                    spaceIDs: [currentSpaceID],
                    windowIDsBySpaceID: [
                        currentSpaceID: [240_001]
                    ],
                    fullscreenWindowIDBySpaceID: [
                        currentSpaceID: 240_001
                    ]
                )
            ]
            : displays
        return RuntimeSpaceTopologyProjection(
            signature: RuntimeSpaceTopologySignature(displays: fallbackDisplays),
            affectedCGWindowIDs: [],
            freshness: RuntimeProjectionFreshness(
                generatedAt: 10,
                sourceGeneration:
                    RuntimeReadModelGeneration(space: spaceGeneration),
                dirtyAppIDs: [],
                dirtyPIDs: [],
                dirtyCGWindowIDs: [],
                pendingRepairScopes: pendingRepairScopes,
                isCompleteForScope: isCompleteForScope
            )
        )
    }

    private func assertAppSwitcherProjectionRead(
        from runtimeProjectionService: RecordingRuntimeProjectionService,
        readCount: Int = 1,
        maintenanceRequests: [RuntimeProjectionMaintenanceReason],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherProjectionReadCount(),
            readCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherMaintenanceRequestsRecorded(),
            maintenanceRequests,
            file: file,
            line: line
        )
    }

}
