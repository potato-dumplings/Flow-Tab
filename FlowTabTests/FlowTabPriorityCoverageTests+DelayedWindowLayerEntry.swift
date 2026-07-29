import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testDelayedWindowLayerEntryUsesConfiguredDeadlineAndCancelsWithSession() {
        let scheduler =
            ManualDelayedWindowLayerEntryScheduler()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService:
                    RecordingRuntimeProjectionService(
                        appSwitcherApps: searchScenarioApps()
                    )
            ),
            delayedWindowLayerEntryScheduler: scheduler
        )
        controller.windowLayerPresentationDelayOverride = 0.75

        XCTAssertTrue(
            controller.beginGlobalHotkeySessionForTesting()
        )
        controller.scheduleDelayedWindowLayerEntryForTesting()

        XCTAssertEqual(
            controller.modelForTesting.session?.mode,
            .appCycle
        )
        XCTAssertTrue(
            controller.hasPendingDelayedWindowLayerEntryForTesting
        )
        XCTAssertEqual(scheduler.scheduledIntervals, [0.75])
        XCTAssertEqual(scheduler.pendingCount, 1)

        controller.cancelSelectionForTesting()

        XCTAssertFalse(
            controller.hasPendingDelayedWindowLayerEntryForTesting
        )
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertFalse(scheduler.fireNextDeadline())
    }

    @MainActor
    func testDelayedWindowLayerEntryObserverExistsBeforeProjectionRequest() {
        let scheduler =
            ManualDelayedWindowLayerEntryScheduler()
        let fixture = makeDelayedWindowLayerFixture(
            scheduler: scheduler
        )
        let targetAppID = fixture.appID
        var observationEstablishedBeforeRequest = false
        fixture.service
            .setSelectedCurrentAppWindowChangeSignalHandler {
                [weak controller = fixture.controller]
                appID,
                _ in
                observationEstablishedBeforeRequest =
                    appID == targetAppID
                    && controller?
                        .hasPendingDelayedWindowLayerEntryForTesting
                        == true
            }

        XCTAssertTrue(
            fixture.controller
                .beginGlobalHotkeySessionForTesting()
        )
        fixture.controller
            .scheduleDelayedWindowLayerEntryForTesting()

        XCTAssertTrue(observationEstablishedBeforeRequest)
        XCTAssertEqual(
            fixture.service
                .selectedCurrentAppWindowChangeSignalsRecorded()
                .map(\.appID),
            [fixture.appID]
        )
        XCTAssertEqual(
            fixture.service.currentAppWindowProjectionReadCount(
                appID: fixture.appID
            ),
            1
        )
        fixture.controller.cancelSelectionForTesting()
    }

    @MainActor
    func testDelayedWindowLayerEntryRequestReturnReadbackUsesInitialCompleteProjection() {
        let scheduler =
            ManualDelayedWindowLayerEntryScheduler()
        let fixture = makeDelayedWindowLayerFixture(
            scheduler: scheduler
        )
        fixture.service.setCurrentAppWindowProjection(
            makeDelayedWindowLayerProjection(
                appID: fixture.appID,
                windows: fixture.windows,
                projectionGeneration: 3
            ),
            appID: fixture.appID
        )
        fixture.controller.windowLayerPresentationDelayOverride =
            0.5

        XCTAssertTrue(
            fixture.controller
                .beginGlobalHotkeySessionForTesting()
        )
        fixture.controller
            .scheduleDelayedWindowLayerEntryForTesting()

        XCTAssertEqual(
            fixture.controller.modelForTesting.session?
                .selectedApp.windows.map(\.id),
            fixture.windows.map(\.id)
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .appCycle
        )
        XCTAssertTrue(scheduler.fireNextDeadline())
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .windowCycle(appID: fixture.appID)
        )
        XCTAssertTrue(
            fixture.service
                .selectedCurrentAppWindowChangeSignalsRecorded()
                .isEmpty
        )
        fixture.controller.cancelSelectionForTesting()
    }

    @MainActor
    func testDelayedWindowLayerEntryDeadlineThenExactProjectionEventEnters() {
        let scheduler =
            ManualDelayedWindowLayerEntryScheduler()
        let fixture = makeDelayedWindowLayerFixture(
            scheduler: scheduler
        )
        fixture.controller.windowLayerPresentationDelayOverride =
            0.3

        XCTAssertTrue(
            fixture.controller
                .beginGlobalHotkeySessionForTesting()
        )
        fixture.controller
            .scheduleDelayedWindowLayerEntryForTesting()
        XCTAssertTrue(scheduler.fireNextDeadline())
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .appCycle
        )
        XCTAssertTrue(
            fixture.controller
                .hasPendingDelayedWindowLayerEntryForTesting
        )

        XCTAssertFalse(
            fixture.controller
                .handleCurrentAppWindowProjectionDidUpdateForTesting(
                    appID: "com.example.other"
                )
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .appCycle
        )

        fixture.service.setCurrentAppWindowProjection(
            makeDelayedWindowLayerProjection(
                appID: fixture.appID,
                windows: fixture.windows,
                projectionGeneration: 5
            ),
            appID: fixture.appID
        )
        XCTAssertTrue(
            fixture.controller
                .handleCurrentAppWindowProjectionDidUpdateForTesting(
                    appID: fixture.appID
                )
        )

        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .windowCycle(appID: fixture.appID)
        )
        XCTAssertFalse(
            fixture.controller
                .hasPendingDelayedWindowLayerEntryForTesting
        )
        XCTAssertEqual(scheduler.pendingCount, 0)
        fixture.controller.cancelSelectionForTesting()
    }

    @MainActor
    func testManualWindowLayerProjectionEventDoesNotScheduleReadinessProbe() {
        let scheduler =
            ManualDelayedWindowLayerEntryScheduler()
        let fixture = makeDelayedWindowLayerFixture(
            scheduler: scheduler
        )
        fixture.controller.windowLayerPresentationDelayOverride =
            30

        XCTAssertTrue(
            fixture.controller
                .beginGlobalHotkeySessionForTesting()
        )
        fixture.controller.advance(.downArrow)

        XCTAssertEqual(
            scheduler.scheduledIntervals,
            [30]
        )
        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertEqual(
            fixture.service
                .selectedCurrentAppWindowChangeSignalsRecorded()
                .map(\.appID),
            [fixture.appID]
        )

        fixture.service.setCurrentAppWindowProjection(
            makeDelayedWindowLayerProjection(
                appID: fixture.appID,
                windows: fixture.windows,
                projectionGeneration: 7
            ),
            appID: fixture.appID
        )
        XCTAssertTrue(
            fixture.controller
                .handleCurrentAppWindowProjectionDidUpdateForTesting(
                    appID: fixture.appID
                )
        )

        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .windowCycle(appID: fixture.appID)
        )
        XCTAssertEqual(scheduler.scheduledIntervals, [30])
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertFalse(scheduler.fireNextDeadline())
        fixture.controller.cancelSelectionForTesting()
    }

    @MainActor
    private func makeDelayedWindowLayerFixture(
        scheduler: ManualDelayedWindowLayerEntryScheduler
    ) -> (
        appID: String,
        windows: [WindowCandidate],
        service: RecordingRuntimeProjectionService,
        controller: SwitcherPanelController
    ) {
        let appID = "com.example.delayed-window-layer"
        let windows = [
            WindowCandidate(
                id: "delayed-1",
                title: "Delayed One",
                isMinimized: false,
                lastActiveAt: 30
            ),
            WindowCandidate(
                id: "delayed-2",
                title: "Delayed Two",
                isMinimized: false,
                lastActiveAt: 20
            ),
        ]
        let appOnlyCandidate = AppSwitchCandidate(
            id: appID,
            displayName: "Delayed Window Layer",
            groupID: "delayed",
            lastActiveAt: 100,
            windows: []
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: .current,
            windows: []
        )
        let freshness = RuntimeProjectionFreshness(
            generatedAt: 10,
            sourceGeneration:
                RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let service = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [appOnlyCandidate],
                contextsByID: [appID: context],
                freshness: freshness
            )
        )
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: service
            ),
            delayedWindowLayerEntryScheduler: scheduler
        )
        return (appID, windows, service, controller)
    }

    @MainActor
    private func makeDelayedWindowLayerProjection(
        appID: String,
        windows: [WindowCandidate],
        projectionGeneration: UInt64
    ) -> RuntimeCurrentAppWindowProjection {
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: "Delayed Window Layer",
            groupID: "delayed",
            lastActiveAt: 100,
            windows: windows
        )
        let context = makeRuntimeAppContext(
            appID: appID,
            runningApp: .current,
            windows: windows
        )
        return RuntimeCurrentAppWindowProjection(
            appID: appID,
            currentAppWindowPayload:
                RuntimeCurrentAppWindowPayload(
                    summary: RuntimeHomeAppSummary(
                        appID: appID,
                        displayName: candidate.displayName,
                        groupID: candidate.groupID,
                        lastActiveAt: candidate.lastActiveAt,
                        windowCount: windows.count,
                        pid: NSRunningApplication.current
                            .processIdentifier
                    ),
                    candidate: candidate,
                    context: context,
                    appDirectoryEntries: [
                        RuntimeAppDirectoryEntry(
                            app: .current
                        )
                    ]
                ),
            freshness: RuntimeProjectionFreshness(
                generatedAt: 20,
                sourceGeneration:
                    RuntimeReadModelGeneration(
                        projection: projectionGeneration
                    ),
                dirtyAppIDs: [],
                dirtyPIDs: [],
                dirtyCGWindowIDs: [],
                pendingRepairScopes: [],
                isCompleteForScope: true
            )
        )
    }
}
