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
        let lifecycle = HomeRetainedTabLifecycle(state: .active)
        let hostedView = makeHomeDetailBehaviorHost(
            lifecycle: lifecycle,
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
    func testHomeDoesNotRepeatSelectedDetailRepairFromIncompleteSummaryCommit() {
        let notificationCenter = NotificationCenter()
        let appID = "com.example.home-detail-feedback"
        let mainPID: pid_t = 6_520
        let transientPID: pid_t = 83_885

        func makeFreshness(
            pid: pid_t,
            generation: UInt64,
            isCompleteForScope: Bool
        ) -> RuntimeProjectionFreshness {
            RuntimeProjectionFreshness(
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
        }

        func makeDetailProjection(
            pid: pid_t,
            generation: UInt64,
            windowIDs: [String],
            isCompleteForScope: Bool
        ) -> RuntimeHomeAppDetailProjection {
            let windows = windowIDs.map { windowID in
                WindowCandidate(
                    id: windowID,
                    title: windowID,
                    isMinimized: false,
                    lastActiveAt: TimeInterval(generation)
                )
            }
            let contextsByID = Dictionary(
                uniqueKeysWithValues: windows.map { window in
                    (
                        window.id,
                        RuntimeWindowContext(
                            id: window.id,
                            title: window.title,
                            isMinimized: false,
                            ownerPID: pid
                        )
                    )
                }
            )
            let summary = RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Home Detail Feedback",
                groupID: "home-detail-feedback",
                lastActiveAt: TimeInterval(generation),
                windowCount: windows.count,
                pid: pid
            )
            return RuntimeHomeAppDetailProjection(
                summary: summary,
                candidate: AppSwitchCandidate(
                    id: appID,
                    displayName: summary.displayName,
                    groupID: summary.groupID,
                    lastActiveAt: summary.lastActiveAt,
                    windows: windows
                ),
                context: RuntimeAppContext(
                    appID: appID,
                    runningApp: .current,
                    ownerPID: pid,
                    windowsByID: contextsByID
                ),
                freshness: makeFreshness(
                    pid: pid,
                    generation: generation,
                    isCompleteForScope: isCompleteForScope
                )
            )
        }

        func makeSummaryProjection(
            pid: pid_t,
            generation: UInt64,
            windowCount: Int,
            isCompleteForScope: Bool
        ) -> RuntimeHomeSummaryProjection {
            RuntimeHomeSummaryProjection(
                summaries: [
                    RuntimeHomeAppSummary(
                        appID: appID,
                        displayName: "Home Detail Feedback",
                        groupID: "home-detail-feedback",
                        lastActiveAt: TimeInterval(generation),
                        windowCount: windowCount,
                        pid: pid
                    )
                ],
                freshness: makeFreshness(
                    pid: pid,
                    generation: generation,
                    isCompleteForScope: isCompleteForScope
                )
            )
        }

        let initialDetail = makeDetailProjection(
            pid: mainPID,
            generation: 1,
            windowIDs: ["feedback-main"],
            isCompleteForScope: true
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeSummaryProjection: makeSummaryProjection(
                pid: mainPID,
                generation: 1,
                windowCount: 1,
                isCompleteForScope: true
            ),
            homeDetailProjectionsByAppID: [appID: initialDetail]
        )
        let detailOwner = HomeAppDetailProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        let lifecycle = HomeRetainedTabLifecycle(state: .active)
        let hostedView = makeHomeDetailBehaviorHost(
            lifecycle: lifecycle,
            runtimeProjectionService: runtimeProjectionService,
            detailOwner: detailOwner,
            notificationCenter: notificationCenter
        )
        let baselineSignalCount = runtimeProjectionService
            .selectedCurrentAppWindowChangeSignalsRecorded()
            .count
        runtimeProjectionService
            .setSelectedCurrentAppWindowChangeSignalHandler { _, _ in
                guard runtimeProjectionService
                    .selectedCurrentAppWindowChangeSignalsRecorded()
                    .count == baselineSignalCount + 1
                else {
                    return
                }
                runtimeProjectionService.setHomeDetailProjection(
                    makeDetailProjection(
                        pid: transientPID,
                        generation: 3,
                        windowIDs: [],
                        isCompleteForScope: true
                    ),
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
                runtimeProjectionService.setHomeSummaryProjection(
                    makeSummaryProjection(
                        pid: transientPID,
                        generation: 3,
                        windowCount: 2,
                        isCompleteForScope: false
                    )
                )
                notificationCenter.post(
                    name: .runtimeAppSwitcherProjectionDidUpdate,
                    object: runtimeProjectionService
                )
            }
        runtimeProjectionService.setHomeSummaryProjection(
            makeSummaryProjection(
                pid: transientPID,
                generation: 2,
                windowCount: 2,
                isCompleteForScope: false
            )
        )
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )

        let signals = Array(runtimeProjectionService
            .selectedCurrentAppWindowChangeSignalsRecorded()
            .dropFirst(baselineSignalCount))
        XCTAssertEqual(signals.first?.appID, appID)
        XCTAssertEqual(signals.first?.pid, transientPID)
        XCTAssertEqual(
            signals.count,
            1,
            "A selected-app repair must not retrigger itself from its own incomplete summary commit"
        )

        XCTAssertTrue(lifecycle.transition(to: .inactive))
        hostedView.layoutSubtreeIfNeeded()
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
        let lifecycle = HomeRetainedTabLifecycle(state: .active)
        let hostedView = makeHomeDetailBehaviorHost(
            lifecycle: lifecycle,
            runtimeProjectionService: runtimeProjectionService,
            detailOwner: detailOwner,
            notificationCenter: notificationCenter
        )
        XCTAssertTrue(detailOwner.isObserving(appID: appID))

        XCTAssertTrue(lifecycle.transition(to: .inactive))
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
        lifecycle: HomeRetainedTabLifecycle,
        runtimeProjectionService: RecordingRuntimeProjectionService,
        detailOwner: HomeAppDetailProjectionObservationOwner,
        notificationCenter: NotificationCenter
    ) -> NSHostingView<HomeLandingView> {
        let hostedView = NSHostingView(
            rootView: makeHomeDetailBehaviorView(
                lifecycle: lifecycle,
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
        lifecycle: HomeRetainedTabLifecycle,
        runtimeProjectionService: RecordingRuntimeProjectionService,
        detailOwner: HomeAppDetailProjectionObservationOwner,
        notificationCenter: NotificationCenter
    ) -> HomeLandingView {
        HomeLandingView(
            lifecycle: lifecycle,
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
