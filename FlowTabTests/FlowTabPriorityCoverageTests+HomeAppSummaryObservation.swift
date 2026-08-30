import Foundation
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testHomeAppSummaryObservationAcceptsOnlyExactMonotonicEvidence() {
        let notificationCenter = NotificationCenter()
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeSummaryProjection: makeObservedHomeSummaryProjection(
                generation: 2,
                isCompleteForScope: false
            )
        )
        let owner = HomeAppSummaryProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        var evidence: [HomeAppSummaryProjectionObservationEvidence] = []

        owner.start(reason: "test_monotonic_evidence") {
            evidence.append($0)
        }
        let readCountBeforeUnrelatedNotification =
            runtimeProjectionService.homeSummaryProjectionReadCount()
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: NSObject()
        )

        for _ in 0..<64 {
            notificationCenter.post(
                name: .runtimeAppSwitcherProjectionDidUpdate,
                object: runtimeProjectionService
            )
        }
        runtimeProjectionService.setHomeSummaryProjection(
            makeObservedHomeSummaryProjection(
                generation: 1,
                isCompleteForScope: true
            )
        )
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )
        runtimeProjectionService.setHomeSummaryProjection(
            makeObservedHomeSummaryProjection(
                generation: 3,
                isCompleteForScope: false
            )
        )
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )
        runtimeProjectionService.setHomeSummaryProjection(
            makeObservedHomeSummaryProjection(
                generation: 3,
                isCompleteForScope: true
            )
        )
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )

        XCTAssertEqual(
            runtimeProjectionService.homeSummaryProjectionReadCount(),
            readCountBeforeUnrelatedNotification + 67
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
            64
        )
        XCTAssertEqual(
            evidence.filter { $0.transition == .regressed }.count,
            1
        )
        XCTAssertTrue(owner.isObserving)
    }

    @MainActor
    func testHomeAppSummaryObservationUsesMaintenanceReturnReadback() {
        let notificationCenter = NotificationCenter()
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeSummaryProjection: makeObservedHomeSummaryProjection(
                generation: 1,
                isCompleteForScope: true
            )
        )
        let owner = HomeAppSummaryProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        var evidence: [HomeAppSummaryProjectionObservationEvidence] = []
        owner.start(reason: "test_request_return") {
            evidence.append($0)
        }
        runtimeProjectionService.setAppSwitcherMaintenanceRequestHandler {
            _ in
            runtimeProjectionService.setHomeSummaryProjection(
                self.makeObservedHomeSummaryProjection(
                    generation: 2,
                    isCompleteForScope: true
                )
            )
        }

        owner.requestMaintenance(reason: "test_permission_change")
        runtimeProjectionService.setAppSwitcherMaintenanceRequestHandler(nil)

        XCTAssertEqual(
            evidence.map(\.source),
            [.initialReadback, .maintenanceRequestReadback]
        )
        XCTAssertEqual(
            evidence.map(\.transition),
            [.baseline, .sourceGenerationAdvanced]
        )
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherMaintenanceRequestsRecorded(),
            [.homeProjectionMissing]
        )
        XCTAssertTrue(owner.isObserving)
    }

    @MainActor
    func testHomeAppSummaryObservationInstallsObserverBeforeMaintenance() {
        let notificationCenter = NotificationCenter()
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeSummaryProjection: makeObservedHomeSummaryProjection(
                generation: 1,
                isCompleteForScope: true
            )
        )
        let owner = HomeAppSummaryProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        var evidence: [HomeAppSummaryProjectionObservationEvidence] = []
        owner.start(reason: "test_synchronous_notification") {
            evidence.append($0)
        }
        runtimeProjectionService.setAppSwitcherMaintenanceRequestHandler {
            _ in
            runtimeProjectionService.setHomeSummaryProjection(
                self.makeObservedHomeSummaryProjection(
                    generation: 2,
                    isCompleteForScope: true
                )
            )
            notificationCenter.post(
                name: .runtimeAppSwitcherProjectionDidUpdate,
                object: runtimeProjectionService
            )
        }

        owner.requestMaintenance(reason: "test_synchronous_notification")
        runtimeProjectionService.setAppSwitcherMaintenanceRequestHandler(nil)

        XCTAssertEqual(
            evidence.map(\.source),
            [
                .initialReadback,
                .appSwitcherProjectionNotification,
                .maintenanceRequestReadback
            ]
        )
        XCTAssertEqual(
            evidence.map(\.transition),
            [.baseline, .sourceGenerationAdvanced, .unchanged]
        )
    }

    @MainActor
    func testHomeAppSummaryObservationCancellationAndRapidRestart() {
        let notificationCenter = NotificationCenter()
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeSummaryProjection: makeObservedHomeSummaryProjection(
                generation: 1,
                isCompleteForScope: true
            )
        )
        let owner = HomeAppSummaryProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )

        for index in 0..<2_000 {
            owner.start(reason: "pressure_restart_\(index)") { _ in }
        }
        let readCountBeforeNotification =
            runtimeProjectionService.homeSummaryProjectionReadCount()
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )
        XCTAssertEqual(
            runtimeProjectionService.homeSummaryProjectionReadCount(),
            readCountBeforeNotification + 1
        )

        owner.stop(reason: "pressure_complete")
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )
        XCTAssertEqual(
            runtimeProjectionService.homeSummaryProjectionReadCount(),
            readCountBeforeNotification + 1
        )
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testHomeAppSummaryObservationRetainsAcceptedEvidenceAcrossRestart() {
        let notificationCenter = NotificationCenter()
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeSummaryProjection: makeObservedHomeSummaryProjection(
                generation: 1,
                isCompleteForScope: true
            )
        )
        let owner = HomeAppSummaryProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        var resumedEvidence: [HomeAppSummaryProjectionObservationEvidence] = []

        owner.start(reason: "initial") { _ in }
        owner.stop(reason: "inactive")
        owner.start(reason: "resume") {
            resumedEvidence.append($0)
        }

        XCTAssertEqual(resumedEvidence.map(\.transition), [.unchanged])
        XCTAssertFalse(resumedEvidence[0].shouldApply)

        runtimeProjectionService.setHomeSummaryProjection(
            makeObservedHomeSummaryProjection(
                generation: 2,
                isCompleteForScope: true
            )
        )
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )

        XCTAssertEqual(
            resumedEvidence.map(\.transition),
            [.unchanged, .sourceGenerationAdvanced]
        )
        XCTAssertTrue(resumedEvidence[1].shouldApply)
    }

    @MainActor
    func testHomeAppSummaryObservationResolvesProjectionBackedEmptyDirectory() {
        let projection = RuntimeHomeSummaryProjection(
            summaries: [],
            freshness: RuntimeProjectionFreshness(
                generatedAt: 1,
                sourceGeneration: RuntimeReadModelGeneration(projection: 1),
                dirtyAppIDs: [],
                dirtyPIDs: [],
                dirtyCGWindowIDs: [],
                pendingRepairScopes: ["appDirectory"],
                isCompleteForScope: false
            )
        )
        let owner = HomeAppSummaryProjectionObservationOwner(
            runtimeProjectionService: RecordingRuntimeProjectionService(
                homeSummaryProjection: projection
            )
        )

        let evidence = owner.start(reason: "empty_directory") { _ in }

        XCTAssertTrue(evidence.projectionRead.isProjectionBacked)
        XCTAssertTrue(owner.hasResolvedProjection)
        XCTAssertEqual(
            HomeApplicationLayerLifecyclePolicy.activationDecision(
                hasResolvedProjection: owner.hasResolvedProjection
            ),
            .resumeObservation
        )
    }

    func testHomeAccessibilityUnavailableStateOnlyInvalidatesPermissionDerivedEntries() {
        let permissionDerivedAppID = "com.example.permission-derived"
        let authorizedEmptyAppID = "com.example.authorized-empty"
        let summaries = [
            RuntimeHomeAppSummary(
                appID: permissionDerivedAppID,
                displayName: "Permission Derived",
                groupID: "permission-derived",
                lastActiveAt: 2,
                windowCount: 3,
                pid: 18_415
            ),
            RuntimeHomeAppSummary(
                appID: authorizedEmptyAppID,
                displayName: "Authorized Empty",
                groupID: "authorized-empty",
                lastActiveAt: 1,
                windowCount: 0,
                pid: 18_416
            )
        ]
        var state = HomeAccessibilityUnavailableWindowState()

        state.markUnavailable(appIDs: [permissionDerivedAppID])
        let resolved = state.resolvingWindowCounts(in: summaries)

        XCTAssertEqual(resolved.map(\.windowCount), [0, 0])
        XCTAssertEqual(state.invalidateAll(), [permissionDerivedAppID])
        XCTAssertTrue(state.isEmpty)
        XCTAssertFalse(
            state.appIDs.contains(authorizedEmptyAppID),
            "An authorized empty window result has its own runtime evidence."
        )
    }

    @MainActor
    func testHomeAppSummaryObservationDeliversBackgroundCommitOnMainActor() async {
        let notificationCenter = NotificationCenter()
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeSummaryProjection: makeObservedHomeSummaryProjection(
                generation: 1,
                isCompleteForScope: true
            )
        )
        let owner = HomeAppSummaryProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        defer {
            owner.stop(reason: "test_teardown")
        }
        let expectedSourceGeneration =
            RuntimeReadModelGeneration(projection: 2)
        let delivered = expectation(
            description:
                "unmetCondition=exactHomeSummaryProjectionEvidenceDeliveredOnMainActor"
        )
        delivered.assertForOverFulfill = true
        var deliveredEvidence: HomeAppSummaryProjectionObservationEvidence?
        owner.start(reason: "test_background_commit") { evidence in
            guard
                evidence.observationGeneration == 1,
                evidence.readbackCount == 2,
                evidence.source == .appSwitcherProjectionNotification,
                evidence.transition == .sourceGenerationAdvanced,
                evidence.projectionRead.isProjectionBacked,
                evidence.projectionRead.freshness?.sourceGeneration
                    == expectedSourceGeneration,
                evidence.projectionRead.freshness?.isCompleteForScope == true,
                evidence.projectionRead.summaries.map(\.appID)
                    == ["com.example.home-observed"],
                evidence.projectionRead.summaries.map(\.windowCount) == [2]
            else {
                return
            }
            XCTAssertTrue(Thread.isMainThread)
            deliveredEvidence = evidence
            delivered.fulfill()
        }
        runtimeProjectionService.setHomeSummaryProjection(
            makeObservedHomeSummaryProjection(
                generation: 2,
                isCompleteForScope: true
            )
        )

        DispatchQueue.global(qos: .userInitiated).async {
            notificationCenter.post(
                name: .runtimeAppSwitcherProjectionDidUpdate,
                object: runtimeProjectionService
            )
        }

        await fulfillment(
            of: [delivered],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .homeProjectionEvidenceDelivery
        )
        XCTAssertEqual(deliveredEvidence?.observationGeneration, 1)
        XCTAssertEqual(deliveredEvidence?.readbackCount, 2)
        XCTAssertEqual(
            deliveredEvidence?.source,
            .appSwitcherProjectionNotification
        )
        XCTAssertEqual(
            deliveredEvidence?.transition,
            .sourceGenerationAdvanced
        )
        XCTAssertEqual(
            deliveredEvidence?.projectionRead.freshness?.sourceGeneration,
            expectedSourceGeneration
        )
        XCTAssertEqual(
            deliveredEvidence?.projectionRead.summaries.map(\.appID),
            ["com.example.home-observed"]
        )
        XCTAssertEqual(
            deliveredEvidence?.projectionRead.summaries.map(\.windowCount),
            [2]
        )
        XCTAssertTrue(owner.isObserving)
        owner.stop(reason: "test_complete")
        XCTAssertFalse(owner.isObserving)
    }

    func testHomeSelectedAppSummaryRefreshPolicyBoundsEachExpectedTargetToOneRequest() {
        let expectation = HomeSelectedAppRefreshExpectation(
            processIdentifier: 83_885,
            windowCount: 2
        )

        XCTAssertEqual(
            HomeSelectedAppSummaryRefreshPolicy.decision(
                summaryProcessIdentifier: expectation.processIdentifier,
                summaryWindowCount: expectation.windowCount,
                cachedWindowCount: 1,
                outstandingExpectation: nil
            ),
            .request(expectation)
        )
        XCTAssertEqual(
            HomeSelectedAppSummaryRefreshPolicy.decision(
                summaryProcessIdentifier: expectation.processIdentifier,
                summaryWindowCount: expectation.windowCount,
                cachedWindowCount: 0,
                outstandingExpectation: expectation
            ),
            .noRequest
        )
        XCTAssertEqual(
            HomeSelectedAppSummaryRefreshPolicy.decision(
                summaryProcessIdentifier: 6_520,
                summaryWindowCount: 2,
                cachedWindowCount: 0,
                outstandingExpectation: expectation
            ),
            .request(
                HomeSelectedAppRefreshExpectation(
                    processIdentifier: 6_520,
                    windowCount: 2
                )
            )
        )
        XCTAssertEqual(
            HomeSelectedAppSummaryRefreshPolicy.decision(
                summaryProcessIdentifier: expectation.processIdentifier,
                summaryWindowCount: expectation.windowCount,
                cachedWindowCount: expectation.windowCount,
                outstandingExpectation: expectation
            ),
            .clearOutstanding
        )
    }

    private func makeObservedHomeSummaryProjection(
        generation: UInt64,
        isCompleteForScope: Bool
    ) -> RuntimeHomeSummaryProjection {
        RuntimeHomeSummaryProjection(
            summaries: [
                RuntimeHomeAppSummary(
                    appID: "com.example.home-observed",
                    displayName: "Home Observed",
                    groupID: "home-observed",
                    lastActiveAt: 100,
                    windowCount: isCompleteForScope ? 2 : 0,
                    pid: 18_415,
                    bundleIdentifier: "com.example.home-observed"
                )
            ],
            freshness: RuntimeProjectionFreshness(
                generatedAt: TimeInterval(generation),
                sourceGeneration:
                    RuntimeReadModelGeneration(projection: generation),
                dirtyAppIDs:
                    isCompleteForScope
                    ? []
                    : ["com.example.home-observed"],
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
}
