import AppKit
import FlowTabCore
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testLiveSwitcherModelPreservesActiveWindowCycleAcrossDegradedAppProjectionRefresh() {
        let appID = "com.example.degraded-window-cycle-refresh"
        let runningApp = NSRunningApplication.current
        let windows = [
            WindowCandidate(
                id: "window-one",
                title: "Window One",
                isMinimized: false,
                lastActiveAt: 20
            ),
            WindowCandidate(
                id: "window-two",
                title: "Window Two",
                isMinimized: false,
                lastActiveAt: 10
            )
        ]
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: "Degraded Window Cycle",
            groupID: "degraded-window-cycle",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: runningApp,
            windows: windows
        )
        let completeFreshness = RuntimeProjectionFreshness(
            generatedAt: 10,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let degradedFreshness = RuntimeProjectionFreshness(
            generatedAt: 11,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [appID],
            dirtyPIDs: [runningApp.processIdentifier],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: ["spaceTopology"],
            isCompleteForScope: false
        )
        let currentProjection = RuntimeCurrentAppWindowProjection(
            appID: appID,
            currentAppWindowPayload: RuntimeCurrentAppWindowPayload(
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
            ),
            freshness: degradedFreshness
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [candidate],
                contextsByID: [appID: context],
                freshness: completeFreshness
            ),
            currentAppWindowProjectionsByAppID: [appID: currentProjection]
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
        model.runtimeProjectionMaintenanceEnabled = false

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        model.handle(.downArrow)
        model.handle(.rightArrow)
        XCTAssertEqual(model.session?.selectedWindow?.id, "window-two")

        runtimeProjectionService.installAppSwitcherProjection(
            apps: [
                AppSwitchCandidate(
                    id: candidate.id,
                    displayName: candidate.displayName,
                    groupID: candidate.groupID,
                    lastActiveAt: candidate.lastActiveAt,
                    windows: []
                )
            ],
            contextsByID: [
                appID: makeRuntimeAppContext(
                    appID: appID,
                    runningApp: runningApp,
                    windows: []
                )
            ],
            generatedAt: 12
        )

        XCTAssertTrue(model.handleAppSwitcherProjectionDidUpdate())
        XCTAssertEqual(model.session?.selectedApp.windows.map(\.id), ["window-one", "window-two"])
        XCTAssertEqual(model.session?.selectedWindow?.id, "window-two")
        XCTAssertEqual(
            Set(model.runtimeContextsByID[appID]?.windowsByID.keys.map { $0 } ?? []),
            Set(windows.map(\.id))
        )
    }

    @MainActor
    func testLiveSwitcherModelFiltersTerminatedAppFromDegradedRuntimeProjection() {
        let apps = terminateScenarioApps()
        let terminatedApp = apps[1]
        let runningApp = NSRunningApplication.current
        let context = makeRuntimeAppContext(
            appID: terminatedApp.id,
            runningApp: runningApp,
            windows: terminatedApp.windows
        )
        let recordingService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: apps,
                contextsByID: [terminatedApp.id: context],
                freshness: RuntimeProjectionFreshness(
                    generatedAt: 10,
                    sourceGeneration: RuntimeReadModelGeneration(projection: 1),
                    dirtyAppIDs: [terminatedApp.id],
                    dirtyPIDs: [runningApp.processIdentifier],
                    dirtyCGWindowIDs: [],
                    pendingRepairScopes: ["appTerminated:\(terminatedApp.id)"],
                    isCompleteForScope: false
                )
            )
        )
        let runtimeProjectionService = RetainingTerminatedAppRuntimeProjectionService(
            recording: recordingService
        )
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertEqual(model.selectedApp?.id, terminatedApp.id)

        XCTAssertTrue(
            model.handleApplicationTerminated(
                appID: terminatedApp.id,
                pid: runningApp.processIdentifier
            )
        )

        XCTAssertTrue(
            runtimeProjectionService.readAppSwitcherProjection()?.apps.contains {
                $0.id == terminatedApp.id
            } ?? false,
            "The degraded committed projection must remain available to non-Switcher consumers."
        )
        XCTAssertFalse(
            model.session?.apps.contains { $0.id == terminatedApp.id } ?? true,
            "A confirmed process termination must not be reintroduced into the active Switcher session by a degraded projection."
        )
        XCTAssertEqual(
            runtimeProjectionService.appTerminationSignalsRecorded().map(\.appID),
            [terminatedApp.id]
        )
        model.cancelSelection()
    }

    @MainActor
    func testSwitcherPanelControllerTerminationRefreshProtectionEndsOnProjectionEvidence() {
        let targetPID =
            NSRunningApplication.current.processIdentifier
        let apps = terminateScenarioApps()
        let contextsByID = Dictionary(
            uniqueKeysWithValues: apps.map { app in
                (
                    app.id,
                    RuntimeAppContext(
                        appID: app.id,
                        runningApp: NSRunningApplication.current,
                        ownerPID: targetPID,
                        windowsByID: [:]
                    )
                )
            }
        )
        let recordingService = RecordingRuntimeProjectionService(
            appSwitcherApps: apps,
            contextsByID: contextsByID
        )
        let runtimeProjectionService =
            RetainingTerminatedAppRuntimeProjectionService(
                recording: recordingService
            )
        let scheduler =
            ManualTerminateInterruptionProtectionScheduler()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: runtimeProjectionService
            ),
            terminateInterruptionProtectionScheduler: scheduler,
            terminateTargetProcessStateReader:
                MutableTerminateTargetProcessStateReader()
        )
        controller.appIsActiveOverride = true

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        guard let terminatedAppID =
            controller.modelForTesting.selectedApp?.id
        else {
            XCTFail("Expected selected app before termination refresh.")
            return
        }
        controller.handleWorkspaceApplicationTerminatedForTesting(
            appID: terminatedAppID,
            pid: targetPID
        )

        XCTAssertTrue(controller.shouldProtectTerminateSystemInterruption())
        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertFalse(
            controller.modelForTesting.session?.apps.contains { $0.id == terminatedAppID } ?? true
        )

        let remainingApps = apps.filter { $0.id != terminatedAppID }
        recordingService.installAppSwitcherProjection(
            apps: remainingApps,
            contextsByID: contextsByID.filter {
                $0.key != terminatedAppID
            },
            generatedAt: 11,
            projectionGeneration: 2
        )
        _ = controller.handleAppSwitcherProjectionDidUpdateForTesting()

        XCTAssertTrue(controller.shouldProtectTerminateSystemInterruption())
        XCTAssertEqual(scheduler.pendingCount, 0)
        controller.handlePanelDidBecomeKeyForTesting()
        XCTAssertFalse(controller.shouldProtectTerminateSystemInterruption())
        XCTAssertNil(
            controller
                .lastTerminateInterruptionProtectionWatchdogFailure
        )
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerConsumesPostTerminationPanelInterruptionBeforeEndingProtection() {
        let targetPID =
            NSRunningApplication.current.processIdentifier
        let apps = terminateScenarioApps()
        let contextsByID = Dictionary(
            uniqueKeysWithValues: apps.map { app in
                (
                    app.id,
                    RuntimeAppContext(
                        appID: app.id,
                        runningApp: NSRunningApplication.current,
                        ownerPID: targetPID,
                        windowsByID: [:]
                    )
                )
            }
        )
        let recordingService = RecordingRuntimeProjectionService(
            appSwitcherApps: apps,
            contextsByID: contextsByID
        )
        let scheduler =
            ManualTerminateInterruptionProtectionScheduler()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService:
                    RetainingTerminatedAppRuntimeProjectionService(
                        recording: recordingService
                    )
            ),
            terminateInterruptionProtectionScheduler: scheduler,
            terminateTargetProcessStateReader:
                MutableTerminateTargetProcessStateReader()
        )
        controller.globalHotkeyHoldSetPressedOverride = false
        controller.globalMainKeySetPressedOverride = false
        controller.appIsActiveOverride = false

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        guard let terminatedAppID =
            controller.modelForTesting.selectedApp?.id
        else {
            return XCTFail("Expected selected app before termination.")
        }
        controller.handleWorkspaceApplicationTerminatedForTesting(
            appID: terminatedAppID,
            pid: targetPID
        )

        recordingService.installAppSwitcherProjection(
            apps: apps.filter { $0.id != terminatedAppID },
            contextsByID: contextsByID.filter {
                $0.key != terminatedAppID
            },
            generatedAt: 11,
            projectionGeneration: 2
        )
        controller.panel.orderOut(nil)
        controller.panelVisibilityOverride = true
        _ = controller.handleAppSwitcherProjectionDidUpdateForTesting()

        XCTAssertTrue(controller.shouldProtectTerminateSystemInterruption())
        controller.handlePanelDidResignKeyForTesting()

        XCTAssertTrue(controller.shouldProtectTerminateSystemInterruption())
        XCTAssertNotNil(controller.modelForTesting.session)
        controller.appIsActiveOverride = true
        controller.handlePanelDidBecomeKeyForTesting()

        XCTAssertFalse(controller.shouldProtectTerminateSystemInterruption())
        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertNil(
            controller
                .lastTerminateInterruptionProtectionWatchdogFailure
        )
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerTerminationProtectionWatchdogReportsUnmetProjectionEvidence() {
        let apps = terminateScenarioApps()
        let recordingService = RecordingRuntimeProjectionService(
            appSwitcherApps: apps
        )
        let runtimeProjectionService =
            RetainingTerminatedAppRuntimeProjectionService(
                recording: recordingService
            )
        let scheduler =
            ManualTerminateInterruptionProtectionScheduler()
        let processStateReader =
            MutableTerminateTargetProcessStateReader()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: runtimeProjectionService
            ),
            terminateInterruptionProtectionScheduler: scheduler,
            terminateTargetProcessStateReader: processStateReader
        )
        controller.globalHotkeyHoldSetPressedOverride = false
        controller.globalMainKeySetPressedOverride = false
        controller.appIsActiveOverride = false

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        guard let terminatedAppID =
            controller.modelForTesting.selectedApp?.id
        else {
            return XCTFail(
                "Expected selected app before termination watchdog."
            )
        }
        controller.handleWorkspaceApplicationTerminatedForTesting(
            appID: terminatedAppID,
            pid: 42_303
        )
        XCTAssertTrue(controller.shouldProtectTerminateSystemInterruption())

        processStateReader.resolvedState = .terminated
        scheduler.fireNextAvailable()

        XCTAssertFalse(controller.shouldProtectTerminateSystemInterruption())
        let failure =
            controller
                .lastTerminateInterruptionProtectionWatchdogFailure
        XCTAssertEqual(
            failure?.lastEvidence.source,
            .workspaceTerminationReadback
        )
        XCTAssertEqual(
            failure?.finalEvidence.snapshot.processState,
            .terminated
        )
        XCTAssertEqual(
            failure?.finalEvidence.snapshot.projectionState,
            .identityUnavailable
        )

        controller.handlePanelDidResignKeyForTesting()
        XCTAssertNil(controller.modelForTesting.session)
    }
}
