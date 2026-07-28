import Foundation
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testHomeAppDetailObservationAppliesCompleteBaselineWithoutClosing() {
        let notificationCenter = NotificationCenter()
        let appID = "com.example.home-detail-ready"
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeDetailProjectionsByAppID: [
                appID: makeObservedHomeDetailProjection(
                    appID: appID,
                    generation: 1,
                    isCompleteForScope: true
                )
            ]
        )
        let owner = HomeAppDetailProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        var evidence: [HomeAppDetailProjectionObservationEvidence] = []

        owner.request(
            appID: appID,
            reason: "test_complete_baseline",
            performRequest: {}
        ) {
            evidence.append($0)
        }

        XCTAssertTrue(evidence[0].shouldApply)
        XCTAssertTrue(evidence[0].isComplete)
        XCTAssertFalse(evidence[0].completesObservation)
        XCTAssertEqual(evidence[1].transition, .unchanged)
        XCTAssertTrue(owner.isObserving(appID: appID))
    }

    @MainActor
    func testHomeAppDetailObservationCancellationAndRapidRestart() {
        let notificationCenter = NotificationCenter()
        let appID = "com.example.home-detail-pressure"
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeDetailProjectionsByAppID: [
                appID: makeObservedHomeDetailProjection(
                    appID: appID,
                    generation: 1,
                    isCompleteForScope: false
                )
            ]
        )
        let owner = HomeAppDetailProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )

        for index in 0..<2_000 {
            owner.request(
                appID: appID,
                reason: "pressure_restart_\(index)",
                performRequest: {},
                onEvidence: { _ in }
            )
        }
        XCTAssertEqual(owner.observationCount, 1)
        let readCountBeforeNotification =
            runtimeProjectionService.homeDetailProjectionReadCount(
                appID: appID
            )
        postHomeDetailProjectionNotification(
            notificationCenter: notificationCenter,
            object: runtimeProjectionService,
            appID: appID
        )
        XCTAssertEqual(
            runtimeProjectionService.homeDetailProjectionReadCount(
                appID: appID
            ),
            readCountBeforeNotification + 1
        )

        owner.stopAll(reason: "pressure_complete")
        postHomeDetailProjectionNotification(
            notificationCenter: notificationCenter,
            object: runtimeProjectionService,
            appID: appID
        )
        XCTAssertEqual(
            runtimeProjectionService.homeDetailProjectionReadCount(
                appID: appID
            ),
            readCountBeforeNotification + 1
        )
        XCTAssertEqual(owner.observationCount, 0)
    }

    @MainActor
    func testHomeAppDetailObservationRetainsOnlyPresentedApps() {
        let notificationCenter = NotificationCenter()
        let removedAppID = "com.example.home-detail-removed"
        let retainedAppID = "com.example.home-detail-retained"
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeDetailProjectionsByAppID: [
                removedAppID: makeObservedHomeDetailProjection(
                    appID: removedAppID,
                    generation: 1,
                    isCompleteForScope: false
                ),
                retainedAppID: makeObservedHomeDetailProjection(
                    appID: retainedAppID,
                    generation: 1,
                    isCompleteForScope: false
                )
            ]
        )
        let owner = HomeAppDetailProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )

        for appID in [removedAppID, retainedAppID] {
            owner.request(
                appID: appID,
                reason: "test_presented_apps",
                performRequest: {},
                onEvidence: { _ in }
            )
        }
        owner.retainObservations(for: [retainedAppID])

        XCTAssertFalse(owner.isObserving(appID: removedAppID))
        XCTAssertTrue(owner.isObserving(appID: retainedAppID))
        XCTAssertEqual(owner.observationCount, 1)
        let removedReadCount =
            runtimeProjectionService.homeDetailProjectionReadCount(
                appID: removedAppID
            )
        postHomeDetailProjectionNotification(
            notificationCenter: notificationCenter,
            object: runtimeProjectionService,
            appID: removedAppID
        )
        XCTAssertEqual(
            runtimeProjectionService.homeDetailProjectionReadCount(
                appID: removedAppID
            ),
            removedReadCount
        )
    }

    @MainActor
    func testHomeAppDetailObservationDeliversBackgroundCommitOnMainActor()
        async
    {
        let notificationCenter = NotificationCenter()
        let appID = "com.example.home-detail-background"
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeDetailProjectionsByAppID: [
                appID: makeObservedHomeDetailProjection(
                    appID: appID,
                    generation: 1,
                    isCompleteForScope: false
                )
            ]
        )
        let owner = HomeAppDetailProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        let delivered = expectation(
            description:
                "Home receives exact committed detail projection evidence"
        )
        owner.request(
            appID: appID,
            reason: "test_background_commit",
            performRequest: {}
        ) { evidence in
            guard evidence.source
                    == .currentAppWindowProjectionNotification
            else {
                return
            }
            XCTAssertTrue(Thread.isMainThread)
            delivered.fulfill()
        }
        runtimeProjectionService.setHomeDetailProjection(
            makeObservedHomeDetailProjection(
                appID: appID,
                generation: 2,
                isCompleteForScope: true
            ),
            appID: appID
        )

        DispatchQueue.global(qos: .userInitiated).async {
            self.postHomeDetailProjectionNotification(
                notificationCenter: notificationCenter,
                object: runtimeProjectionService,
                appID: appID
            )
        }

        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertFalse(owner.isObserving(appID: appID))
    }
}
