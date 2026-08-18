import AppKit
import SwiftUI
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabTests {
    @MainActor
    func testHomeRequestsSelectedDetailAfterInstallingExactObserver() {
        let notificationCenter = NotificationCenter()
        let appID = "com.example.home-detail-behavior"
        let pid: pid_t = 18_421
        let initialDetail = makeHomeDetailBehaviorProjection(
            appID: appID,
            pid: pid,
            generation: 1,
            isCompleteForScope: false,
            windowID: "behavior-initial"
        )
        let committedDetail = makeHomeDetailBehaviorProjection(
            appID: appID,
            pid: pid,
            generation: 2,
            isCompleteForScope: true,
            windowID: "behavior-committed"
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeSummaryProjection: makeHomeDetailBehaviorSummaryProjection(
                detail: initialDetail
            ),
            homeDetailProjectionsByAppID: [appID: initialDetail]
        )
        let detailOwner = HomeAppDetailProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        var observerWasInstalledBeforeRequest = false
        runtimeProjectionService
            .setSelectedCurrentAppWindowChangeSignalHandler {
                requestedAppID,
                requestedPID in
                observerWasInstalledBeforeRequest =
                    detailOwner.isObserving(appID: requestedAppID)
                XCTAssertEqual(requestedAppID, appID)
                XCTAssertEqual(requestedPID, pid)
                runtimeProjectionService.setHomeDetailProjection(
                    committedDetail,
                    appID: appID
                )
                notificationCenter.post(
                    name: .runtimeCurrentAppWindowProjectionDidUpdate,
                    object: runtimeProjectionService,
                    userInfo: [
                        RuntimeProjectionNotificationUserInfoKey.appID:
                            appID
                    ]
                )
            }
        let hostedView = makeHomeDetailBehaviorHost(
            isActive: true,
            runtimeProjectionService: runtimeProjectionService,
            detailOwner: detailOwner,
            notificationCenter: notificationCenter
        )

        XCTAssertTrue(observerWasInstalledBeforeRequest)
        XCTAssertEqual(
            runtimeProjectionService
                .selectedCurrentAppWindowChangeSignalsRecorded()
                .map(\.appID),
            [appID]
        )
        XCTAssertEqual(
            runtimeProjectionService.homeDetailProjectionReadCount(
                appID: appID
            ),
            2
        )
        XCTAssertFalse(detailOwner.isObserving(appID: appID))
        withExtendedLifetime(hostedView) {}
    }

    @MainActor
    func testHomeInactiveCancelsPendingDetailObservation() {
        let notificationCenter = NotificationCenter()
        let appID = "com.example.home-detail-cancel"
        let pid: pid_t = 18_422
        let initialDetail = makeHomeDetailBehaviorProjection(
            appID: appID,
            pid: pid,
            generation: 1,
            isCompleteForScope: false,
            windowID: "cancel-initial"
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeSummaryProjection: makeHomeDetailBehaviorSummaryProjection(
                detail: initialDetail
            ),
            homeDetailProjectionsByAppID: [appID: initialDetail]
        )
        let detailOwner = HomeAppDetailProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        let hostedView = makeHomeDetailBehaviorHost(
            isActive: true,
            runtimeProjectionService: runtimeProjectionService,
            detailOwner: detailOwner,
            notificationCenter: notificationCenter
        )
        XCTAssertTrue(detailOwner.isObserving(appID: appID))

        hostedView.rootView = makeHomeDetailBehaviorView(
            isActive: false,
            runtimeProjectionService: runtimeProjectionService,
            detailOwner: detailOwner,
            notificationCenter: notificationCenter
        )
        hostedView.layoutSubtreeIfNeeded()
        XCTAssertFalse(detailOwner.isObserving(appID: appID))

        let readCountAfterInactive =
            runtimeProjectionService.homeDetailProjectionReadCount(
                appID: appID
            )
        runtimeProjectionService.setHomeDetailProjection(
            makeHomeDetailBehaviorProjection(
                appID: appID,
                pid: pid,
                generation: 2,
                isCompleteForScope: true,
                windowID: "cancel-late"
            ),
            appID: appID
        )
        notificationCenter.post(
            name: .runtimeCurrentAppWindowProjectionDidUpdate,
            object: runtimeProjectionService,
            userInfo: [
                RuntimeProjectionNotificationUserInfoKey.appID: appID
            ]
        )
        XCTAssertEqual(
            runtimeProjectionService.homeDetailProjectionReadCount(
                appID: appID
            ),
            readCountAfterInactive
        )
    }

    @MainActor
    private func makeHomeDetailBehaviorHost(
        isActive: Bool,
        runtimeProjectionService: RecordingRuntimeProjectionService,
        detailOwner: HomeAppDetailProjectionObservationOwner,
        notificationCenter: NotificationCenter
    ) -> NSHostingView<HomeLandingView> {
        let hostedView = NSHostingView(
            rootView: makeHomeDetailBehaviorView(
                isActive: isActive,
                runtimeProjectionService: runtimeProjectionService,
                detailOwner: detailOwner,
                notificationCenter: notificationCenter
            )
        )
        hostedView.frame = NSRect(x: 0, y: 0, width: 1_040, height: 720)
        hostedView.layoutSubtreeIfNeeded()
        return hostedView
    }

    @MainActor
    private func makeHomeDetailBehaviorView(
        isActive: Bool,
        runtimeProjectionService: RecordingRuntimeProjectionService,
        detailOwner: HomeAppDetailProjectionObservationOwner,
        notificationCenter: NotificationCenter
    ) -> HomeLandingView {
        HomeLandingView(
            isActive: isActive,
            appLanguage: .english,
            runtimeProjectionService: runtimeProjectionService,
            permissionObservationOwner: HomePermissionObservationOwner(
                accessibilityTrusted: true,
                screenCaptureTrusted: true,
                readAccessibilityPermission: { true },
                readScreenCapturePermission: { true }
            ),
            initialProjectionObservationOwner:
                HomeInitialProjectionObservationOwner(
                    runtimeProjectionService: runtimeProjectionService,
                    notificationCenter: notificationCenter
                ),
            appSummaryProjectionObservationOwner:
                HomeAppSummaryProjectionObservationOwner(
                    runtimeProjectionService: runtimeProjectionService,
                    notificationCenter: notificationCenter
                ),
            appDetailProjectionObservationOwner: detailOwner,
            openSettings: {}
        )
    }

    private func makeHomeDetailBehaviorSummaryProjection(
        detail: RuntimeHomeAppDetailProjection
    ) -> RuntimeHomeSummaryProjection {
        RuntimeHomeSummaryProjection(
            summaries: [detail.summary],
            freshness: RuntimeProjectionFreshness(
                generatedAt: 1,
                sourceGeneration:
                    RuntimeReadModelGeneration(projection: 1),
                dirtyAppIDs: [],
                dirtyPIDs: [],
                dirtyCGWindowIDs: [],
                pendingRepairScopes: [],
                isCompleteForScope: true
            )
        )
    }

    private func makeHomeDetailBehaviorProjection(
        appID: String,
        pid: pid_t,
        generation: UInt64,
        isCompleteForScope: Bool,
        windowID: String
    ) -> RuntimeHomeAppDetailProjection {
        let runningApp = NSRunningApplication.current
        let window = WindowCandidate(
            id: windowID,
            title: windowID,
            isMinimized: false,
            lastActiveAt: TimeInterval(generation)
        )
        return RuntimeHomeAppDetailProjection(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Home Detail Behavior",
                groupID: "home-detail-behavior",
                lastActiveAt: TimeInterval(generation),
                windowCount: 1,
                pid: pid
            ),
            candidate: AppSwitchCandidate(
                id: appID,
                displayName: "Home Detail Behavior",
                groupID: "home-detail-behavior",
                lastActiveAt: TimeInterval(generation),
                windows: [window]
            ),
            context: RuntimeAppContext(
                appID: appID,
                runningApp: runningApp,
                ownerPID: pid,
                windowsByID: [
                    windowID: RuntimeWindowContext(
                        id: windowID,
                        title: windowID,
                        isMinimized: false,
                        ownerPID: pid
                    )
                ]
            ),
            freshness: RuntimeProjectionFreshness(
                generatedAt: TimeInterval(generation),
                sourceGeneration:
                    RuntimeReadModelGeneration(projection: generation),
                dirtyAppIDs: isCompleteForScope ? [] : [appID],
                dirtyPIDs: isCompleteForScope ? [] : [pid],
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
