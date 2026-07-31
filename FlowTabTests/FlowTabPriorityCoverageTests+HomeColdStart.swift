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
        var application:
            HomeInitialProjectionObservationApplication?
        var callbackHadReturnedWhenPublished = false
        var callbackApplied = false
        let applicationToken = notificationCenter.addObserver(
            forName:
                .homeInitialProjectionObservationDidApply,
            object: runtimeProjectionService,
            queue: nil
        ) { notification in
            callbackHadReturnedWhenPublished = callbackApplied
            application =
                HomeInitialProjectionObservationApplication(
                    notification: notification
                )
        }
        defer {
            notificationCenter.removeObserver(applicationToken)
        }

        owner.start(reason: "test_initial_ready") {
            evidence.append($0)
            callbackApplied = true
        }

        XCTAssertEqual(evidence.map(\.source), [.initialReadback])
        XCTAssertEqual(evidence.map(\.transition), [.baseline])
        XCTAssertTrue(evidence[0].isReady)
        XCTAssertTrue(callbackHadReturnedWhenPublished)
        XCTAssertEqual(application?.evidence, evidence[0])
        XCTAssertEqual(
            application?.requestReason,
            "test_initial_ready"
        )
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
    func testHomeInitialProjectionApplicationForwarderPublishesExactEvidenceAndCancels() throws {
        let notificationCenter = NotificationCenter()
        let runtimeProjectionService =
            RecordingRuntimeProjectionService(
                homeSummaryProjection:
                    makeHomeInitialSummaryProjection(
                        generation: 5,
                        isCompleteForScope: false
                    )
            )
        let route =
            FlowTabUITestHomeInitialProjectionApplicationRoute(
                notificationName:
                    Notification.Name(
                        "test.home-initial-projection"
                    ),
                readbackURL:
                    FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "flowtab-home-initial-\(UUID().uuidString).json",
                            isDirectory: false
                        )
            )
        defer {
            try? FileManager.default.removeItem(
                at: route.readbackURL
            )
        }
        var forwarded:
            [
                FlowTabUITestHomeInitialProjectionApplicationEvidence
            ] = []
        let forwarder =
            FlowTabUITestHomeInitialProjectionApplicationForwarder(
                route: route,
                notificationObject:
                    runtimeProjectionService,
                notificationCenter: notificationCenter
            ) {
                forwarded.append($0)
            }
        let owner = HomeInitialProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        forwarder.start()

        owner.start(reason: "initial_load") { _ in }

        XCTAssertEqual(forwarded.count, 1)
        XCTAssertEqual(
            forwarded.first?.observationGeneration,
            1
        )
        XCTAssertEqual(
            forwarded.first?.source,
            HomeInitialProjectionObservationSource
                .initialReadback.rawValue
        )
        XCTAssertEqual(
            forwarded.first?.transition,
            HomeProjectionEvidenceTransition
                .baseline.rawValue
        )
        XCTAssertEqual(
            forwarded.first?.requestReason,
            "initial_load"
        )
        XCTAssertEqual(
            forwarded.first?.projectionGeneration,
            5
        )
        XCTAssertEqual(
            forwarded.first?.appSummaries,
            [
                FlowTabUITestHomeInitialProjectionApplicationEvidence
                    .AppSummary(
                        appID: "com.example.home-initial",
                        windowCount: 0
                    )
            ]
        )
        XCTAssertEqual(
            forwarded.first?.isCompleteForScope,
            false
        )
        XCTAssertTrue(forwarder.isObserving)

        runtimeProjectionService.setHomeSummaryProjection(
            makeHomeInitialSummaryProjection(
                generation: 6,
                isCompleteForScope: false
            )
        )
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )

        XCTAssertEqual(forwarded.count, 2)
        let exactEvidence = try XCTUnwrap(forwarded.last)
        XCTAssertEqual(
            exactEvidence.source,
            HomeInitialProjectionObservationSource
                .appSwitcherProjectionNotification.rawValue
        )
        XCTAssertEqual(
            exactEvidence.transition,
            HomeProjectionEvidenceTransition
                .sourceGenerationAdvanced.rawValue
        )
        XCTAssertEqual(
            exactEvidence.projectionGeneration,
            6
        )
        try FlowTabUITestHomeInitialProjectionApplicationTransport
            .writeReadback(
                exactEvidence,
                to: route.readbackURL
            )
        let readbackEvidence = try JSONDecoder().decode(
            FlowTabUITestHomeInitialProjectionApplicationEvidence
                .self,
            from: Data(contentsOf: route.readbackURL)
        )
        XCTAssertEqual(readbackEvidence, exactEvidence)

        forwarder.cancel()
        runtimeProjectionService.setHomeSummaryProjection(
            makeHomeInitialSummaryProjection(
                generation: 7,
                isCompleteForScope: false
            )
        )
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )

        XCTAssertEqual(forwarded.count, 2)
        XCTAssertFalse(forwarder.isObserving)
        owner.stop(reason: "test_complete")
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
        var applications:
            [HomeInitialProjectionObservationApplication] = []
        let applicationToken = notificationCenter.addObserver(
            forName:
                .homeInitialProjectionObservationDidApply,
            object: runtimeProjectionService,
            queue: nil
        ) { notification in
            if let application =
                HomeInitialProjectionObservationApplication(
                    notification: notification
                )
            {
                applications.append(application)
            }
        }
        defer {
            notificationCenter.removeObserver(applicationToken)
        }
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
            applications.map(\.evidence.transition),
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
