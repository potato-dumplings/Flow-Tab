import AppKit
import Dispatch
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    func testRuntimeProjectionServiceYieldsReadyTopologyWorkAfterScopedRepairDefers() {
        let coordinator = RuntimeReconciliationCoordinator()
        let scheduler = ManualTransientRepairObservationScheduler()
        let pid = NSRunningApplication.current.processIdentifier
        let appRequest = coordinator.markAppDirty(
            appID: "com.example.deferred-scoped-repair",
            pid: pid,
            reason: .axNotification,
            affectedCGWindowIDs: [CGWindowID(251_201)],
            now: 1
        )
        let topologyRequest = coordinator.markSpaceTopologyDirty(
            affectedCGWindowIDs: [CGWindowID(251_202)],
            now: 2
        )
        var startedTargets: [RuntimeReconciliationTarget] = []
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.YieldAfterScopedDeferral",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: RuntimeWindowRecordStore(),
                reconciliationCoordinator: coordinator
            ),
            transientRepairObservationScheduler: scheduler,
            reconciliationExecutor: { request, _ in
                startedTargets.append(request.target)
                switch request.target {
                case .app:
                    return .waitingForEvidence([
                        .destroyedWindowResolution
                    ])
                case .spaceTopology, .fullRepair:
                    return .completed
                }
            }
        )

        let startedRequests = service
            .drainReadyReconciliationRequestsSynchronouslyForTesting(
                now: 3
            )

        XCTAssertEqual(startedRequests.map(\.id), [appRequest.id])
        XCTAssertEqual(startedTargets, [.app(pid)])
        XCTAssertEqual(
            coordinator.readyRequests().map(\.id),
            [topologyRequest.id]
        )
        XCTAssertEqual(scheduler.entries.map(\.interval), [30, 0.1])
    }

    func testRuntimeProjectionServiceCommitsScopedRepairBeforeNextReadyTopologyRequestCompletes()
        throws
    {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let appDirectoryEntry = RuntimeAppDirectoryEntry(app: runningApp)
        let survivingCGWindowID = CGWindowID(251_101)
        let closedCGWindowID = CGWindowID(251_102)
        let survivingWindow = WindowCandidate(
            id: "ordered-surviving-window",
            title: "Ordered Surviving Window",
            isMinimized: false,
            lastActiveAt: 20
        )
        let closedWindow = WindowCandidate(
            id: "ordered-closed-window",
            title: "Ordered Closed Window",
            isMinimized: false,
            lastActiveAt: 10
        )
        let laggingPayload = makeAuthoritativeWindowPayload(
            appID: appID,
            runningApp: runningApp,
            windows: [
                (survivingWindow, survivingCGWindowID),
                (closedWindow, closedCGWindowID)
            ],
            appDirectoryEntry: appDirectoryEntry
        )
        let repairedPayload = makeAuthoritativeWindowPayload(
            appID: appID,
            runningApp: runningApp,
            windows: [(survivingWindow, survivingCGWindowID)],
            appDirectoryEntry: appDirectoryEntry
        )
        let readModelStore = RuntimeReadModelStore()
        readModelStore.commitCurrentAppWindowProjection(
            laggingPayload,
            clearsDirtyState: true,
            generatedAt: 1
        )
        let coordinator = RuntimeReconciliationCoordinator()
        coordinator.markAppDirty(
            appID: appID,
            pid: pid,
            reason: .axNotification,
            affectedCGWindowIDs: [closedCGWindowID],
            now: 2
        )
        coordinator.markSpaceTopologyDirty(
            affectedCGWindowIDs: [CGWindowID(251_103)],
            now: 3
        )
        let topologyStarted = expectation(
            description: "unmetCondition=followingTopologyRepairStarted"
        )
        let drainFinished = expectation(
            description: "unmetCondition=reconciliationDrainFinished"
        )
        let releaseTopology = DispatchSemaphore(value: 0)
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.OrderedScopedRepairCommit",
            repairProvider: RuntimeProjectionRepairProvider(
                windowRecordStore: RuntimeWindowRecordStore(),
                reconciliationCoordinator: coordinator
            ),
            mainTableProjectionBuilder:
                FixedCurrentAppWindowProjectionBuilder(
                    payload: repairedPayload
                ),
            readModelStore: readModelStore,
            reconciliationExecutor: { request, _ in
                switch request.target {
                case .app:
                    return .completedWithCurrentAppRepairEvidence([
                        RuntimeCurrentAppRepairEvidence(
                            appID: appID,
                            pid: pid,
                            appDirectoryEntries: [appDirectoryEntry],
                            currentAppWindowPayloadWasEmpty: false,
                            authoritativeCGWindowIDs: [survivingCGWindowID]
                        )
                    ])
                case .spaceTopology:
                    topologyStarted.fulfill()
                    _ = releaseTopology.wait(
                        timeout: .now()
                            + FlowTabPriorityCoverageWatchdogPolicy
                                .runtimeMaintenanceExecution
                    )
                    return .completed
                case .fullRepair:
                    return .completed
                }
            }
        )

        DispatchQueue.global(qos: .userInitiated).async {
            _ = service
                .drainReadyReconciliationRequestsSynchronouslyForTesting(
                    now: 4
                )
            drainFinished.fulfill()
        }

        wait(
            for: [topologyStarted],
            timeout: FlowTabPriorityCoverageWatchdogPolicy
                .runtimeMaintenanceExecution
        )
        let projectedWindowIDs = try XCTUnwrap(
            readModelStore.readCurrentAppWindowProjection(appID: appID)
        ).currentAppWindowPayload.candidate.windows.map(\.id)
        releaseTopology.signal()
        wait(
            for: [drainFinished],
            timeout: FlowTabPriorityCoverageWatchdogPolicy
                .runtimeMaintenanceExecution
        )

        XCTAssertEqual(projectedWindowIDs, [survivingWindow.id])
    }

    func testRuntimeReadModelStoreAuthoritativeRepairRemovesClosedWindowFromLaggingPayload()
        throws
    {
        let runningApp = NSRunningApplication.current
        let appID = RuntimeAppIdentity.appID(for: runningApp)
        let pid = runningApp.processIdentifier
        let survivingCGWindowID = CGWindowID(251_001)
        let closedCGWindowID = CGWindowID(251_002)
        let survivingWindow = WindowCandidate(
            id: "authoritative-surviving-window",
            title: "Authoritative Surviving Window",
            isMinimized: false,
            lastActiveAt: 20
        )
        let closedWindow = WindowCandidate(
            id: "authoritative-closed-window",
            title: "Authoritative Closed Window",
            isMinimized: false,
            lastActiveAt: 10
        )
        let windows = [survivingWindow, closedWindow]
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: runningApp.localizedName ?? appID,
            groupID: appID,
            lastActiveAt: 20,
            windows: windows
        )
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: runningApp,
            windowsByID: [
                survivingWindow.id: RuntimeWindowContext(
                    id: survivingWindow.id,
                    title: survivingWindow.title,
                    isMinimized: false,
                    ownerPID: pid,
                    cgWindowID: survivingCGWindowID,
                    spaceIDs: [5]
                ),
                closedWindow.id: RuntimeWindowContext(
                    id: closedWindow.id,
                    title: closedWindow.title,
                    isMinimized: false,
                    ownerPID: pid,
                    cgWindowID: closedCGWindowID,
                    spaceIDs: [5]
                )
            ]
        )
        let laggingPayload = RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: candidate.displayName,
                groupID: candidate.groupID,
                lastActiveAt: candidate.lastActiveAt,
                windowCount: windows.count,
                pid: pid
            ),
            candidate: candidate,
            context: context,
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: runningApp)]
        )
        let store = RuntimeReadModelStore()
        store.commitCurrentAppWindowProjection(
            laggingPayload,
            clearsDirtyState: true,
            generatedAt: 1
        )

        store.commitCurrentAppWindowProjection(
            laggingPayload,
            clearsDirtyState: true,
            authoritativeCGWindowIDs: [survivingCGWindowID],
            generatedAt: 2
        )

        let projection = try XCTUnwrap(
            store.readCurrentAppWindowProjection(appID: appID)
        )
        XCTAssertEqual(
            projection.currentAppWindowPayload.candidate.windows.map(\.id),
            [survivingWindow.id]
        )
        XCTAssertEqual(
            projection.currentAppWindowPayload.candidate.windows.map(\.title),
            [survivingWindow.title]
        )
        XCTAssertEqual(
            projection.currentAppWindowPayload.summary.windowCount,
            1
        )
        XCTAssertNil(
            projection.currentAppWindowPayload.context.windowsByID[
                closedWindow.id
            ]
        )
    }

    @MainActor
    func testLiveSwitcherModelNextSessionReadsExpandedAndContractedWindowProjection() {
        struct Scenario {
            let appID: String
            let initialWindows: [WindowCandidate]
            let nextWindows: [WindowCandidate]
        }

        let scenarios = [
            Scenario(
                appID: "com.example.next-session-expanded",
                initialWindows: [
                    WindowCandidate(
                        id: "expanded-1",
                        title: "Expanded One",
                        isMinimized: false,
                        lastActiveAt: 20
                    )
                ],
                nextWindows: [
                    WindowCandidate(
                        id: "expanded-1",
                        title: "Expanded One",
                        isMinimized: false,
                        lastActiveAt: 20
                    ),
                    WindowCandidate(
                        id: "expanded-2",
                        title: "Expanded Two",
                        isMinimized: false,
                        lastActiveAt: 30
                    )
                ]
            ),
            Scenario(
                appID: "com.example.next-session-contracted",
                initialWindows: [
                    WindowCandidate(
                        id: "contracted-1",
                        title: "Contracted One",
                        isMinimized: false,
                        lastActiveAt: 20
                    ),
                    WindowCandidate(
                        id: "contracted-2",
                        title: "Contracted Two",
                        isMinimized: false,
                        lastActiveAt: 30
                    )
                ],
                nextWindows: [
                    WindowCandidate(
                        id: "contracted-1",
                        title: "Contracted One",
                        isMinimized: false,
                        lastActiveAt: 20
                    )
                ]
            )
        ]
        let runningApp = NSRunningApplication.current

        for scenario in scenarios {
            let initialContext = makeManualWindowLayerRuntimeContext(
                appID: scenario.appID,
                runningApp: runningApp,
                windows: scenario.initialWindows
            )
            let runtimeService = RecordingRuntimeProjectionService(
                appSwitcherProjection: RuntimeAppSwitcherProjection(
                    apps: [
                        AppSwitchCandidate(
                            id: scenario.appID,
                            displayName: scenario.appID,
                            groupID: scenario.appID,
                            lastActiveAt: 100,
                            windows: scenario.initialWindows
                        )
                    ],
                    contextsByID: [scenario.appID: initialContext],
                    freshness: RuntimeProjectionFreshness(
                        generatedAt: 1,
                        sourceGeneration: RuntimeReadModelGeneration(
                            projection: 1
                        ),
                        dirtyAppIDs: [],
                        dirtyPIDs: [],
                        dirtyCGWindowIDs: [],
                        pendingRepairScopes: [],
                        isCompleteForScope: true
                    )
                )
            )
            let model = LiveSwitcherModel(
                runtimeProjectionService: runtimeService
            )
            model.runtimeProjectionMaintenanceEnabled = false

            XCTAssertTrue(model.startSession(triggerDirection: .forward))
            XCTAssertEqual(
                model.session?.selectedApp.windows.map(\.id),
                scenario.initialWindows.map(\.id)
            )
            model.cancelSelection()

            let nextContext = makeManualWindowLayerRuntimeContext(
                appID: scenario.appID,
                runningApp: runningApp,
                windows: scenario.nextWindows
            )
            runtimeService.installAppSwitcherProjection(
                apps: [
                    AppSwitchCandidate(
                        id: scenario.appID,
                        displayName: scenario.appID,
                        groupID: scenario.appID,
                        lastActiveAt: 101,
                        windows: scenario.nextWindows
                    )
                ],
                contextsByID: [scenario.appID: nextContext],
                generatedAt: 2
            )

            XCTAssertTrue(model.startSession(triggerDirection: .forward))
            XCTAssertEqual(
                model.session?.selectedApp.windows.map(\.id),
                scenario.nextWindows.map(\.id)
            )
            XCTAssertEqual(
                model.session?.selectedApp.windows.map(\.title),
                scenario.nextWindows.map(\.title)
            )
            model.cancelSelection()
        }
    }

    @MainActor
    func testSwitcherPanelControllerKeepsWindowLayerSnapshotWhenUnselectedWindowCloses() {
        let initialWindows = [
            WindowCandidate(
                id: "open-layer-1",
                title: "Open Layer One",
                isMinimized: false,
                lastActiveAt: 30
            ),
            WindowCandidate(
                id: "open-layer-2",
                title: "Open Layer Two",
                isMinimized: false,
                lastActiveAt: 20
            )
        ]
        let fixture = makeManualWindowLayerProjectionRefreshFixture(
            appID: "com.example.open-layer-mutation",
            displayName: "Open Layer Mutation",
            initialWindows: initialWindows
        )

        XCTAssertTrue(
            fixture.controller.beginGlobalHotkeySessionForTesting()
        )
        fixture.controller.advance(.downArrow)
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .appCycle
        )
        XCTAssertTrue(
            fixture.controller.manualWindowLayerEntryObservationOwner
                .isObserving
        )

        XCTAssertTrue(
            fixture.publishCurrentProjection(
                windows: initialWindows,
                projectionGeneration: 2
            )
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .windowCycle(appID: fixture.appID)
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting
                .windowPreviewSnapshotForTesting().map(\.id),
            ["open-layer-1", "open-layer-2"]
        )

        XCTAssertFalse(
            fixture.publishCurrentProjection(
                windows: [initialWindows[0]],
                projectionGeneration: 3
            )
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?
                .selectedApp.windows.map(\.id),
            ["open-layer-1", "open-layer-2"]
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting
                .windowPreviewSnapshotForTesting().map(\.id),
            ["open-layer-1", "open-layer-2"]
        )
        fixture.controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerKeepsWindowLayerSnapshotWhenSelectedWindowCloses() {
        let initialWindows = [
            WindowCandidate(
                id: "open-layer-remaining",
                title: "Open Layer Remaining",
                isMinimized: false,
                lastActiveAt: 30
            ),
            WindowCandidate(
                id: "open-layer-removed",
                title: "Open Layer Removed",
                isMinimized: false,
                lastActiveAt: 20
            )
        ]
        let fixture = makeManualWindowLayerProjectionRefreshFixture(
            appID: "com.example.open-layer-selected-removed",
            displayName: "Open Layer Selected Removed",
            initialWindows: initialWindows
        )

        XCTAssertTrue(
            fixture.controller.beginGlobalHotkeySessionForTesting()
        )
        fixture.controller.advance(.downArrow)
        XCTAssertTrue(
            fixture.publishCurrentProjection(
                windows: initialWindows,
                projectionGeneration: 2
            )
        )
        fixture.controller.advance(.rightArrow)
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .windowCycle(appID: fixture.appID)
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?
                .selectedWindow?.id,
            "open-layer-removed"
        )

        XCTAssertFalse(
            fixture.publishCurrentProjection(
                windows: [initialWindows[0]],
                projectionGeneration: 3
            )
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?.mode,
            .windowCycle(appID: fixture.appID)
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?
                .selectedWindow?.id,
            "open-layer-removed"
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting.session?
                .selectedApp.windows.map(\.id),
            ["open-layer-remaining", "open-layer-removed"]
        )
        XCTAssertEqual(
            fixture.controller.modelForTesting
                .windowPreviewSnapshotForTesting().map(\.id),
            ["open-layer-remaining", "open-layer-removed"]
        )
        fixture.controller.cancelSelectionForTesting()
    }
}

private struct ManualWindowLayerProjectionRefreshFixture {
    let appID: String
    let displayName: String
    let runningApp: NSRunningApplication
    let runtimeService: RecordingRuntimeProjectionService
    let controller: SwitcherPanelController

    @MainActor
    func publishCurrentProjection(
        windows: [WindowCandidate],
        projectionGeneration: UInt64
    ) -> Bool {
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: displayName,
            groupID: "open-layer",
            lastActiveAt: 100,
            windows: windows
        )
        let projection = RuntimeCurrentAppWindowProjection(
            appID: appID,
            currentAppWindowPayload: RuntimeCurrentAppWindowPayload(
                summary: RuntimeHomeAppSummary(
                    appID: appID,
                    displayName: displayName,
                    groupID: "open-layer",
                    lastActiveAt: 100,
                    windowCount: windows.count,
                    pid: runningApp.processIdentifier
                ),
                candidate: candidate,
                context: makeManualWindowLayerRuntimeContext(
                    appID: appID,
                    runningApp: runningApp,
                    windows: windows
                ),
                appDirectoryEntries: [
                    RuntimeAppDirectoryEntry(app: runningApp)
                ]
            ),
            freshness: RuntimeProjectionFreshness(
                generatedAt: TimeInterval(projectionGeneration),
                sourceGeneration: RuntimeReadModelGeneration(
                    projection: projectionGeneration
                ),
                dirtyAppIDs: [],
                dirtyPIDs: [],
                dirtyCGWindowIDs: [],
                pendingRepairScopes: [],
                isCompleteForScope: true
            )
        )
        runtimeService.setCurrentAppWindowProjection(
            projection,
            appID: appID
        )
        return controller
            .handleCurrentAppWindowProjectionDidUpdateForTesting(
                appID: appID,
                evidence:
                    RuntimeCurrentAppWindowProjectionUpdateEvidence(
                        projection: projection
                    )
            )
    }
}

private extension FlowTabPriorityCoverageTests {
    @MainActor
    func makeManualWindowLayerProjectionRefreshFixture(
        appID: String,
        displayName: String,
        initialWindows: [WindowCandidate]
    ) -> ManualWindowLayerProjectionRefreshFixture {
        let runningApp = NSRunningApplication.current
        let initialCandidate = AppSwitchCandidate(
            id: appID,
            displayName: displayName,
            groupID: "open-layer",
            lastActiveAt: 100,
            windows: initialWindows
        )
        let runtimeService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [initialCandidate],
                contextsByID: [
                    appID: makeManualWindowLayerRuntimeContext(
                        appID: appID,
                        runningApp: runningApp,
                        windows: initialWindows
                    )
                ],
                freshness: RuntimeProjectionFreshness(
                    generatedAt: 1,
                    sourceGeneration: RuntimeReadModelGeneration(
                        projection: 1
                    ),
                    dirtyAppIDs: [],
                    dirtyPIDs: [],
                    dirtyCGWindowIDs: [],
                    pendingRepairScopes: [],
                    isCompleteForScope: true
                )
            )
        )
        return ManualWindowLayerProjectionRefreshFixture(
            appID: appID,
            displayName: displayName,
            runningApp: runningApp,
            runtimeService: runtimeService,
            controller: SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService: runtimeService
                )
            )
        )
    }
}

private func makeManualWindowLayerRuntimeContext(
    appID: String,
    runningApp: NSRunningApplication,
    windows: [WindowCandidate]
) -> RuntimeAppContext {
    RuntimeAppContext(
        appID: appID,
        runningApp: runningApp,
        windowsByID: Dictionary(
            uniqueKeysWithValues: windows.map { window in
                (
                    window.id,
                    RuntimeWindowContext(
                        id: window.id,
                        title: window.title,
                        isMinimized: window.isMinimized,
                        ownerPID: runningApp.processIdentifier,
                        cgWindowID: nil,
                        inferredTitleBarStyle: nil
                    )
                )
            }
        )
    )
}

private func makeAuthoritativeWindowPayload(
    appID: String,
    runningApp: NSRunningApplication,
    windows: [(candidate: WindowCandidate, cgWindowID: CGWindowID)],
    appDirectoryEntry: RuntimeAppDirectoryEntry
) -> RuntimeCurrentAppWindowPayload {
    let candidates = windows.map(\.candidate)
    let displayName = runningApp.localizedName ?? appID
    return RuntimeCurrentAppWindowPayload(
        summary: RuntimeHomeAppSummary(
            appID: appID,
            displayName: displayName,
            groupID: appID,
            lastActiveAt: candidates.map(\.lastActiveAt).max() ?? 0,
            windowCount: candidates.count,
            pid: runningApp.processIdentifier
        ),
        candidate: AppSwitchCandidate(
            id: appID,
            displayName: displayName,
            groupID: appID,
            lastActiveAt: candidates.map(\.lastActiveAt).max() ?? 0,
            windows: candidates
        ),
        context: RuntimeAppContext(
            appID: appID,
            runningApp: runningApp,
            windowsByID: Dictionary(
                uniqueKeysWithValues: windows.map { window in
                    (
                        window.candidate.id,
                        RuntimeWindowContext(
                            id: window.candidate.id,
                            title: window.candidate.title,
                            isMinimized: window.candidate.isMinimized,
                            ownerPID: runningApp.processIdentifier,
                            cgWindowID: window.cgWindowID,
                            spaceIDs: [5]
                        )
                    )
                }
            )
        ),
        appDirectoryEntries: [appDirectoryEntry]
    )
}

private final class FixedCurrentAppWindowProjectionBuilder:
    RuntimeMainTableProjectionBuilding
{
    private let payload: RuntimeCurrentAppWindowPayload

    init(payload: RuntimeCurrentAppWindowPayload) {
        self.payload = payload
    }

    func currentAppWindowPayloadFromMainTables(
        appID: String,
        pid: pid_t,
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeCurrentAppWindowPayload? {
        payload
    }

    func appSwitcherProjectionPayloadFromMainTables(
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeAppSwitcherProjectionPayload? {
        nil
    }

    func searchIndexPayloadFromMainTables(
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeSearchIndexPayload? {
        nil
    }
}
