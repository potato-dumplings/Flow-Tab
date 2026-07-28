import AppKit
import Foundation
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testHomeAppDetailObservationAcceptsOnlyExactMonotonicEvidence() {
        let notificationCenter = NotificationCenter()
        let appID = "com.example.home-detail"
        let otherAppID = "com.example.home-detail-other"
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeDetailProjectionsByAppID: [
                appID: makeObservedHomeDetailProjection(
                    appID: appID,
                    generation: 2,
                    isCompleteForScope: false
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
            reason: "test_monotonic_evidence",
            performRequest: {}
        ) {
            evidence.append($0)
        }
        let readCountAfterRequest =
            runtimeProjectionService.homeDetailProjectionReadCount(
                appID: appID
            )

        postHomeDetailProjectionNotification(
            notificationCenter: notificationCenter,
            object: NSObject(),
            appID: appID
        )
        postHomeDetailProjectionNotification(
            notificationCenter: notificationCenter,
            object: runtimeProjectionService,
            appID: otherAppID
        )
        notificationCenter.post(
            name: .runtimeCurrentAppWindowProjectionDidUpdate,
            object: runtimeProjectionService
        )
        XCTAssertEqual(
            runtimeProjectionService.homeDetailProjectionReadCount(
                appID: appID
            ),
            readCountAfterRequest
        )

        for _ in 0..<64 {
            postHomeDetailProjectionNotification(
                notificationCenter: notificationCenter,
                object: runtimeProjectionService,
                appID: appID
            )
        }
        runtimeProjectionService.setHomeDetailProjection(
            makeObservedHomeDetailProjection(
                appID: otherAppID,
                generation: 3,
                isCompleteForScope: true
            ),
            appID: appID
        )
        postHomeDetailProjectionNotification(
            notificationCenter: notificationCenter,
            object: runtimeProjectionService,
            appID: appID
        )
        runtimeProjectionService.setHomeDetailProjection(
            makeObservedHomeDetailProjection(
                appID: appID,
                generation: 1,
                isCompleteForScope: true
            ),
            appID: appID
        )
        postHomeDetailProjectionNotification(
            notificationCenter: notificationCenter,
            object: runtimeProjectionService,
            appID: appID
        )
        runtimeProjectionService.setHomeDetailProjection(
            makeObservedHomeDetailProjection(
                appID: appID,
                generation: 3,
                isCompleteForScope: false,
                windowIDs: ["detail-later"]
            ),
            appID: appID
        )
        postHomeDetailProjectionNotification(
            notificationCenter: notificationCenter,
            object: runtimeProjectionService,
            appID: appID
        )
        runtimeProjectionService.setHomeDetailProjection(
            makeObservedHomeDetailProjection(
                appID: appID,
                generation: 3,
                isCompleteForScope: true,
                windowIDs: ["detail-complete"]
            ),
            appID: appID
        )
        postHomeDetailProjectionNotification(
            notificationCenter: notificationCenter,
            object: runtimeProjectionService,
            appID: appID
        )

        XCTAssertEqual(
            evidence.filter(\.shouldApply).map(\.transition),
            [.baseline, .sourceGenerationAdvanced, .completenessSatisfied]
        )
        XCTAssertEqual(
            evidence.filter { $0.transition == .unchanged }.count,
            65
        )
        XCTAssertEqual(
            evidence.filter { $0.transition == .regressed }.count,
            2
        )
        XCTAssertEqual(
            evidence.filter(\.shouldApply).compactMap {
                $0.projection?.candidate.windows.first?.id
            },
            ["detail-2", "detail-later", "detail-complete"]
        )
        XCTAssertFalse(owner.isObserving(appID: appID))

        let readCountAfterCompletion =
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
            readCountAfterCompletion
        )
    }

    @MainActor
    func testHomeAppDetailObservationUsesRequestReturnReadback() {
        let notificationCenter = NotificationCenter()
        let appID = "com.example.home-detail-return"
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
        var observerWasInstalledBeforeRequest = false
        var evidence: [HomeAppDetailProjectionObservationEvidence] = []

        owner.request(
            appID: appID,
            reason: "test_request_return",
            performRequest: {
                observerWasInstalledBeforeRequest =
                    owner.isObserving(appID: appID)
                runtimeProjectionService.setHomeDetailProjection(
                    makeObservedHomeDetailProjection(
                        appID: appID,
                        generation: 2,
                        isCompleteForScope: true
                    ),
                    appID: appID
                )
            }
        ) {
            evidence.append($0)
        }

        XCTAssertTrue(observerWasInstalledBeforeRequest)
        XCTAssertEqual(
            evidence.map(\.source),
            [.initialReadback, .requestReturnReadback]
        )
        XCTAssertEqual(
            evidence.map(\.transition),
            [.baseline, .sourceGenerationAdvanced]
        )
        XCTAssertFalse(owner.isObserving(appID: appID))
    }

    @MainActor
    func testHomeAppDetailObservationCapturesSynchronousNotification() {
        let notificationCenter = NotificationCenter()
        let appID = "com.example.home-detail-synchronous"
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
        var evidence: [HomeAppDetailProjectionObservationEvidence] = []

        owner.request(
            appID: appID,
            reason: "test_synchronous_notification",
            performRequest: {
                runtimeProjectionService.setHomeDetailProjection(
                    makeObservedHomeDetailProjection(
                        appID: appID,
                        generation: 2,
                        isCompleteForScope: true
                    ),
                    appID: appID
                )
                postHomeDetailProjectionNotification(
                    notificationCenter: notificationCenter,
                    object: runtimeProjectionService,
                    appID: appID
                )
            }
        ) {
            evidence.append($0)
        }

        XCTAssertEqual(
            evidence.map(\.source),
            [
                .initialReadback,
                .currentAppWindowProjectionNotification
            ]
        )
        XCTAssertEqual(
            runtimeProjectionService.homeDetailProjectionReadCount(
                appID: appID
            ),
            2
        )
        XCTAssertFalse(owner.isObserving(appID: appID))
    }

    func postHomeDetailProjectionNotification(
        notificationCenter: NotificationCenter,
        object: Any,
        appID: String
    ) {
        notificationCenter.post(
            name: .runtimeCurrentAppWindowProjectionDidUpdate,
            object: object,
            userInfo: [
                RuntimeProjectionNotificationUserInfoKey.appID: appID
            ]
        )
    }

    func makeObservedHomeDetailProjection(
        appID: String,
        generation: UInt64,
        isCompleteForScope: Bool,
        windowIDs: [String]? = nil
    ) -> RuntimeHomeAppDetailProjection {
        let runningApp = NSRunningApplication.current
        let ids = windowIDs ?? ["detail-\(generation)"]
        let windows = ids.enumerated().map { index, id in
            WindowCandidate(
                id: id,
                title: "Detail \(index)",
                isMinimized: false,
                lastActiveAt: TimeInterval(generation)
            )
        }
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: "Home Detail",
            groupID: "home-detail",
            lastActiveAt: TimeInterval(generation),
            windows: windows
        )
        let contexts = Dictionary(
            uniqueKeysWithValues: windows.map {
                (
                    $0.id,
                    RuntimeWindowContext(
                        id: $0.id,
                        title: $0.title,
                        isMinimized: $0.isMinimized,
                        ownerPID: runningApp.processIdentifier
                    )
                )
            }
        )
        return RuntimeHomeAppDetailProjection(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Home Detail",
                groupID: "home-detail",
                lastActiveAt: TimeInterval(generation),
                windowCount: windows.count,
                pid: runningApp.processIdentifier
            ),
            candidate: candidate,
            context: RuntimeAppContext(
                appID: appID,
                runningApp: runningApp,
                windowsByID: contexts
            ),
            freshness: RuntimeProjectionFreshness(
                generatedAt: TimeInterval(generation),
                sourceGeneration:
                    RuntimeReadModelGeneration(projection: generation),
                dirtyAppIDs: isCompleteForScope ? [] : [appID],
                dirtyPIDs:
                    isCompleteForScope
                    ? []
                    : [runningApp.processIdentifier],
                dirtyCGWindowIDs: [],
                pendingRepairScopes:
                    isCompleteForScope
                    ? []
                    : ["currentApp:\(appID)"],
                isCompleteForScope: isCompleteForScope
            )
        )
    }
}
