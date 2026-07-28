import Foundation
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testHomeInitialProjectionObservationCompletesFromInitialReadback() {
        let notificationCenter = NotificationCenter()
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeSummaryProjection: makeHomeInitialSummaryProjection(
                generation: 1,
                isCompleteForScope: true
            )
        )
        let owner = HomeInitialProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        var evidence: [HomeInitialProjectionObservationEvidence] = []

        owner.start(reason: "test_initial_ready") {
            evidence.append($0)
        }

        XCTAssertEqual(evidence.map(\.source), [.initialReadback])
        XCTAssertEqual(evidence.map(\.transition), [.baseline])
        XCTAssertTrue(evidence[0].isReady)
        XCTAssertFalse(owner.isObserving)
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherMaintenanceRequestsRecorded(),
            []
        )
        XCTAssertEqual(
            runtimeProjectionService.homeSummaryProjectionReadCount(),
            1
        )
    }

    @MainActor
    func testHomeInitialProjectionObservationClosesSynchronousMaintenanceRace() {
        let notificationCenter = NotificationCenter()
        let runtimeProjectionService = RecordingRuntimeProjectionService()
        runtimeProjectionService.setAppSwitcherMaintenanceRequestHandler {
            _ in
            runtimeProjectionService.setHomeSummaryProjection(
                self.makeHomeInitialSummaryProjection(
                    generation: 2,
                    isCompleteForScope: true
                )
            )
            notificationCenter.post(
                name: .runtimeAppSwitcherProjectionDidUpdate,
                object: runtimeProjectionService
            )
        }
        let owner = HomeInitialProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        var evidence: [HomeInitialProjectionObservationEvidence] = []

        owner.start(reason: "test_synchronous_maintenance") {
            evidence.append($0)
        }
        runtimeProjectionService.setAppSwitcherMaintenanceRequestHandler(nil)

        XCTAssertEqual(
            evidence.map(\.source),
            [.initialReadback, .appSwitcherProjectionNotification]
        )
        XCTAssertEqual(
            evidence.map(\.transition),
            [.baseline, .projectionBecameAvailable]
        )
        XCTAssertFalse(evidence[0].isReady)
        XCTAssertTrue(evidence[1].isReady)
        XCTAssertFalse(owner.isObserving)
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherMaintenanceRequestsRecorded(),
            [.homeProjectionMissing]
        )
        XCTAssertEqual(
            runtimeProjectionService.homeSummaryProjectionReadCount(),
            2
        )
    }

    @MainActor
    func testHomeInitialProjectionObservationUsesRequestReturnReadback() {
        let notificationCenter = NotificationCenter()
        let runtimeProjectionService = RecordingRuntimeProjectionService()
        runtimeProjectionService.setAppSwitcherMaintenanceRequestHandler {
            _ in
            runtimeProjectionService.setHomeSummaryProjection(
                self.makeHomeInitialSummaryProjection(
                    generation: 2,
                    isCompleteForScope: true
                )
            )
        }
        let owner = HomeInitialProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        var evidence: [HomeInitialProjectionObservationEvidence] = []

        owner.start(reason: "test_request_return_readback") {
            evidence.append($0)
        }
        runtimeProjectionService.setAppSwitcherMaintenanceRequestHandler(nil)

        XCTAssertEqual(
            evidence.map(\.source),
            [.initialReadback, .maintenanceRequestReadback]
        )
        XCTAssertEqual(
            evidence.map(\.transition),
            [.baseline, .projectionBecameAvailable]
        )
        XCTAssertTrue(evidence.last?.isReady == true)
        XCTAssertFalse(owner.isObserving)
        XCTAssertEqual(
            runtimeProjectionService.homeSummaryProjectionReadCount(),
            2
        )
    }

    @MainActor
    func testHomeInitialProjectionObservationUsesGenerationAndCompletenessEvidence() {
        let notificationCenter = NotificationCenter()
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeSummaryProjection: makeHomeInitialSummaryProjection(
                generation: 2,
                isCompleteForScope: false
            )
        )
        let owner = HomeInitialProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        var evidence: [HomeInitialProjectionObservationEvidence] = []
        owner.start(reason: "test_generation_transition") {
            evidence.append($0)
        }

        for _ in 0..<64 {
            notificationCenter.post(
                name: .runtimeAppSwitcherProjectionDidUpdate,
                object: runtimeProjectionService
            )
        }
        runtimeProjectionService.setHomeSummaryProjection(
            makeHomeInitialSummaryProjection(
                generation: 1,
                isCompleteForScope: true
            )
        )
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )
        runtimeProjectionService.setHomeSummaryProjection(
            makeHomeInitialSummaryProjection(
                generation: 3,
                isCompleteForScope: false
            )
        )
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )
        runtimeProjectionService.setHomeSummaryProjection(
            makeHomeInitialSummaryProjection(
                generation: 3,
                isCompleteForScope: true
            )
        )
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )
        let countAfterCompletion = evidence.count
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )

        XCTAssertEqual(
            evidence.prefix(2).map(\.source),
            [.initialReadback, .maintenanceRequestReadback]
        )
        XCTAssertEqual(
            evidence.filter(\.shouldApply).map(\.transition),
            [
                .baseline,
                .sourceGenerationAdvanced,
                .completenessSatisfied
            ]
        )
        XCTAssertEqual(
            evidence.filter { $0.transition == .unchanged }.count,
            65
        )
        XCTAssertEqual(
            evidence.filter { $0.transition == .regressed }.count,
            1
        )
        XCTAssertTrue(evidence.last?.isReady == true)
        XCTAssertEqual(evidence.count, countAfterCompletion)
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testHomeInitialProjectionObservationCancellationRejectsLateEvidence() {
        let notificationCenter = NotificationCenter()
        let runtimeProjectionService = RecordingRuntimeProjectionService()
        let owner = HomeInitialProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        var evidence: [HomeInitialProjectionObservationEvidence] = []
        owner.start(reason: "test_cancellation") {
            evidence.append($0)
        }
        let countBeforeCancellation = evidence.count

        owner.stop(reason: "test")
        runtimeProjectionService.setHomeSummaryProjection(
            makeHomeInitialSummaryProjection(
                generation: 1,
                isCompleteForScope: true
            )
        )
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )

        XCTAssertEqual(evidence.count, countBeforeCancellation)
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testHomeInitialProjectionObservationRapidRestartKeepsOneSubscription() {
        let notificationCenter = NotificationCenter()
        let runtimeProjectionService = RecordingRuntimeProjectionService()
        let owner = HomeInitialProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )

        for index in 0..<2_000 {
            owner.start(reason: "pressure_restart_\(index)") { _ in }
        }
        let readCountBeforeNotifications =
            runtimeProjectionService.homeSummaryProjectionReadCount()

        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: NSObject()
        )
        XCTAssertEqual(
            runtimeProjectionService.homeSummaryProjectionReadCount(),
            readCountBeforeNotifications
        )

        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )
        XCTAssertEqual(
            runtimeProjectionService.homeSummaryProjectionReadCount(),
            readCountBeforeNotifications + 1
        )

        owner.stop(reason: "pressure_complete")
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )
        XCTAssertEqual(
            runtimeProjectionService.homeSummaryProjectionReadCount(),
            readCountBeforeNotifications + 1
        )
    }

    private func makeHomeInitialSummaryProjection(
        generation: UInt64,
        isCompleteForScope: Bool
    ) -> RuntimeHomeSummaryProjection {
        RuntimeHomeSummaryProjection(
            summaries: [
                RuntimeHomeAppSummary(
                    appID: "com.example.home-initial",
                    displayName: "Home Initial",
                    groupID: "home-initial",
                    lastActiveAt: 100,
                    windowCount: isCompleteForScope ? 2 : 0,
                    pid: 18_413,
                    bundleIdentifier: "com.example.home-initial"
                )
            ],
            freshness: RuntimeProjectionFreshness(
                generatedAt: TimeInterval(generation),
                sourceGeneration: RuntimeReadModelGeneration(
                    projection: generation
                ),
                dirtyAppIDs:
                    isCompleteForScope
                    ? []
                    : ["com.example.home-initial"],
                dirtyPIDs: [],
                dirtyCGWindowIDs: [],
                pendingRepairScopes:
                    isCompleteForScope
                    ? []
                    : ["fullRepair"],
                isCompleteForScope: isCompleteForScope
            )
        )
    }

    func testRuntimeProjectionServiceDoesNotDrainQueuedRepairsWithoutAccessibility() {
        let coordinator = RuntimeReconciliationCoordinator()
        let repairProvider = RuntimeProjectionRepairProvider(
            reconciliationCoordinator: coordinator
        )
        let lock = NSLock()
        var executionCount = 0
        let service = RuntimeProjectionService(
            label: "FlowTabTests.RuntimeProjectionService.AXUnavailableCentralGate",
            repairProvider: repairProvider,
            axWindowRepairAvailability: { false },
            reconciliationExecutor: { _, _ in
                lock.lock()
                executionCount += 1
                lock.unlock()
                return .completed
            }
        )
        let request = coordinator.markAppDirty(
            appID: "com.example.editor",
            pid: 18_405,
            reason: .appLaunched,
            now: 10
        )

        let startedRequests = service.drainReadyReconciliationRequestsSynchronouslyForTesting(
            now: 10
        )

        lock.lock()
        let finalExecutionCount = executionCount
        lock.unlock()
        XCTAssertTrue(startedRequests.isEmpty)
        XCTAssertEqual(finalExecutionCount, 0)
        XCTAssertEqual(coordinator.readyRequests().map(\.id), [request.id])
    }
}
