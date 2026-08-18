import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testSwitcherPanelControllerManualWindowLayerEntryAppliesProjectionBeforeLongAutoEnterDelay() {
        let currentApp = NSRunningApplication.current
        let appID = "com.example.manual-selected-projection"
        let scheduler =
            ManualDelayedWindowLayerEntryScheduler()
        let windows = [
            WindowCandidate(
                id: "manual-after-dirty-1",
                title: "Manual One",
                isMinimized: false,
                lastActiveAt: 30
            ),
            WindowCandidate(
                id: "manual-after-dirty-2",
                title: "Manual Two",
                isMinimized: false,
                lastActiveAt: 20
            ),
        ]
        let appOnlyCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Manual Projection",
            groupID: "manual",
            lastActiveAt: 100,
            windows: []
        )
        let windowCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Manual Projection",
            groupID: "manual",
            lastActiveAt: 100,
            windows: windows
        )
        let emptyContext = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: []
        )
        let repairedContext = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: windows
        )
        let selectedCurrentAppWindowPayload =
            RuntimeCurrentAppWindowPayload(
                summary: RuntimeHomeAppSummary(
                    appID: appID,
                    displayName: "Manual Projection",
                    groupID: "manual",
                    lastActiveAt: 100,
                    windowCount: windows.count,
                    pid: currentApp.processIdentifier
                ),
                candidate: windowCandidate,
                context: repairedContext,
                appDirectoryEntries: [
                    RuntimeAppDirectoryEntry(app: currentApp)
                ]
            )
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 12,
            sourceGeneration:
                RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let runtimeProjectionService =
            RecordingRuntimeProjectionService(
                appSwitcherProjection:
                    RuntimeAppSwitcherProjection(
                        apps: [appOnlyCandidate],
                        contextsByID: [appID: emptyContext],
                        freshness: freshness
                    )
            )
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService:
                    runtimeProjectionService
            ),
            delayedWindowLayerEntryScheduler: scheduler
        )
        controller.windowLayerPresentationDelayOverride = 30

        XCTAssertTrue(
            controller.beginGlobalHotkeySessionForTesting()
        )
        XCTAssertEqual(
            controller.modelForTesting.session?.mode,
            .appCycle
        )
        XCTAssertEqual(
            controller.modelForTesting.session?
                .selectedApp.windows,
            []
        )
        let projectionGenerationBaseline =
            controller.modelForTesting
                .selectedAppWindowProjectionGeneration
        let observationGenerationBaseline =
            controller.delayedWindowLayerEntryGenerationForTesting

        controller.advance(.downArrow)

        let maintenanceSignals =
            runtimeProjectionService
                .selectedCurrentAppWindowChangeSignalsRecorded()
        XCTAssertEqual(
            maintenanceSignals.map(\.appID),
            [appID]
        )
        XCTAssertEqual(
            maintenanceSignals.map(\.pid),
            [currentApp.processIdentifier]
        )
        XCTAssertEqual(
            runtimeProjectionService
                .currentAppWindowProjectionReadCount(
                    appID: appID
                ),
            1
        )
        XCTAssertEqual(
            controller.modelForTesting
                .selectedAppWindowProjectionGeneration,
            projectionGenerationBaseline + 1
        )
        XCTAssertEqual(
            controller.delayedWindowLayerEntryGenerationForTesting,
            observationGenerationBaseline + 1
        )
        XCTAssertEqual(scheduler.scheduledIntervals, [30])
        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertTrue(
            controller.hasPendingDelayedWindowLayerEntryForTesting
        )
        XCTAssertEqual(
            controller.modelForTesting.session?.mode,
            .appCycle
        )

        XCTAssertFalse(
            controller
                .handleCurrentAppWindowProjectionDidUpdateForTesting(
                    appID: "com.example.other"
                )
        )
        XCTAssertEqual(
            runtimeProjectionService
                .currentAppWindowProjectionReadCount(
                    appID: appID
                ),
            1
        )
        runtimeProjectionService.setCurrentAppWindowProjection(
            RuntimeCurrentAppWindowProjection(
                appID: appID,
                currentAppWindowPayload:
                    selectedCurrentAppWindowPayload,
                freshness: freshness
            ),
            appID: appID
        )

        XCTAssertTrue(
            controller
                .handleCurrentAppWindowProjectionDidUpdateForTesting(
                    appID: appID
                )
        )

        XCTAssertEqual(
            runtimeProjectionService
                .currentAppWindowProjectionReadCount(
                    appID: appID
                ),
            2
        )
        XCTAssertEqual(
            controller.modelForTesting
                .selectedAppWindowProjectionGeneration,
            projectionGenerationBaseline + 2
        )
        XCTAssertEqual(
            controller.modelForTesting.session?.mode,
            .windowCycle(appID: appID)
        )
        XCTAssertEqual(
            controller.modelForTesting.session?
                .selectedApp.windows.map(\.id),
            ["manual-after-dirty-1", "manual-after-dirty-2"]
        )
        XCTAssertFalse(
            controller.hasPendingDelayedWindowLayerEntryForTesting
        )
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertFalse(scheduler.fireNextDeadline())
        controller.cancelSelectionForTesting()
    }
}
