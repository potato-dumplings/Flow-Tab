import AppKit
import SwiftUI
import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testHomeVisibilityOwnsInitialProjectionObservationLifecycle() async {
        let notificationCenter = NotificationCenter()
        let runtimeProjectionService = RecordingRuntimeProjectionService()
        let projectionOwner = HomeInitialProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        let permissionOwner = HomePermissionObservationOwner(
            accessibilityTrusted: true,
            screenCaptureTrusted: true,
            readAccessibilityPermission: { true },
            readScreenCapturePermission: { true }
        )
        let maintenanceRequested = expectation(
            description: "Home requested initial projection maintenance."
        )
        runtimeProjectionService.setAppSwitcherMaintenanceRequestHandler {
            _ in
            maintenanceRequested.fulfill()
        }
        let hostedView = NSHostingView(
            rootView: HomeLandingView(
                isActive: true,
                appLanguage: .english,
                runtimeProjectionService: runtimeProjectionService,
                permissionObservationOwner: permissionOwner,
                initialProjectionObservationOwner: projectionOwner,
                openSettings: {}
            )
        )
        hostedView.frame = NSRect(
            x: 0,
            y: 0,
            width: 1_040,
            height: 720
        )
        hostedView.layoutSubtreeIfNeeded()

        await fulfillment(of: [maintenanceRequested], timeout: 1)
        runtimeProjectionService.setAppSwitcherMaintenanceRequestHandler(nil)
        XCTAssertTrue(projectionOwner.isObserving)

        hostedView.rootView = HomeLandingView(
            isActive: false,
            appLanguage: .english,
            runtimeProjectionService: runtimeProjectionService,
            permissionObservationOwner: permissionOwner,
            initialProjectionObservationOwner: projectionOwner,
            openSettings: {}
        )
        hostedView.layoutSubtreeIfNeeded()

        XCTAssertFalse(projectionOwner.isObserving)
        let readCountAfterInactive =
            runtimeProjectionService.homeSummaryProjectionReadCount()
        runtimeProjectionService.setHomeSummaryProjection(
            makeHomeVisibilitySummaryProjection()
        )
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )
        XCTAssertEqual(
            runtimeProjectionService.homeSummaryProjectionReadCount(),
            readCountAfterInactive
        )
    }

    @MainActor
    func testHomeVisibilityHandsOffToAppSummaryProjectionObservation() {
        let notificationCenter = NotificationCenter()
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeSummaryProjection: makeHomeVisibilitySummaryProjection(
                generation: 1
            )
        )
        let initialProjectionOwner = HomeInitialProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        let appSummaryProjectionOwner =
            HomeAppSummaryProjectionObservationOwner(
                runtimeProjectionService: runtimeProjectionService,
                notificationCenter: notificationCenter
            )
        let permissionOwner = HomePermissionObservationOwner(
            accessibilityTrusted: true,
            screenCaptureTrusted: true,
            readAccessibilityPermission: { true },
            readScreenCapturePermission: { true }
        )
        let hostedView = NSHostingView(
            rootView: HomeLandingView(
                isActive: true,
                appLanguage: .english,
                runtimeProjectionService: runtimeProjectionService,
                permissionObservationOwner: permissionOwner,
                initialProjectionObservationOwner: initialProjectionOwner,
                appSummaryProjectionObservationOwner:
                    appSummaryProjectionOwner,
                openSettings: {}
            )
        )
        hostedView.frame = NSRect(
            x: 0,
            y: 0,
            width: 1_040,
            height: 720
        )
        hostedView.layoutSubtreeIfNeeded()

        XCTAssertFalse(initialProjectionOwner.isObserving)
        XCTAssertTrue(appSummaryProjectionOwner.isObserving)
        let readCountBeforeCommit =
            runtimeProjectionService.homeSummaryProjectionReadCount()
        runtimeProjectionService.setHomeSummaryProjection(
            makeHomeVisibilitySummaryProjection(generation: 2)
        )
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )
        XCTAssertEqual(
            runtimeProjectionService.homeSummaryProjectionReadCount(),
            readCountBeforeCommit + 1
        )

        hostedView.rootView = HomeLandingView(
            isActive: false,
            appLanguage: .english,
            runtimeProjectionService: runtimeProjectionService,
            permissionObservationOwner: permissionOwner,
            initialProjectionObservationOwner: initialProjectionOwner,
            appSummaryProjectionObservationOwner:
                appSummaryProjectionOwner,
            openSettings: {}
        )
        hostedView.layoutSubtreeIfNeeded()
        XCTAssertFalse(appSummaryProjectionOwner.isObserving)

        let readCountAfterInactive =
            runtimeProjectionService.homeSummaryProjectionReadCount()
        runtimeProjectionService.setHomeSummaryProjection(
            makeHomeVisibilitySummaryProjection(generation: 3)
        )
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )
        XCTAssertEqual(
            runtimeProjectionService.homeSummaryProjectionReadCount(),
            readCountAfterInactive
        )
    }

    private func makeHomeVisibilitySummaryProjection()
        -> RuntimeHomeSummaryProjection
    {
        makeHomeVisibilitySummaryProjection(generation: 1)
    }

    private func makeHomeVisibilitySummaryProjection(
        generation: UInt64
    ) -> RuntimeHomeSummaryProjection {
        RuntimeHomeSummaryProjection(
            summaries: [
                RuntimeHomeAppSummary(
                    appID: "com.example.home-visible",
                    displayName: "Home Visible",
                    groupID: "home-visible",
                    lastActiveAt: 100,
                    windowCount: 1,
                    pid: 18_414,
                    bundleIdentifier: "com.example.home-visible"
                )
            ],
            freshness: RuntimeProjectionFreshness(
                generatedAt: TimeInterval(generation),
                sourceGeneration:
                    RuntimeReadModelGeneration(projection: generation),
                dirtyAppIDs: [],
                dirtyPIDs: [],
                dirtyCGWindowIDs: [],
                pendingRepairScopes: [],
                isCompleteForScope: true
            )
        )
    }
}
