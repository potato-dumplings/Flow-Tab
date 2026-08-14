import AppKit
import SwiftUI
import XCTest
@testable import FlowTab

private enum HomeInitialProjectionObservationWatchdogPolicy {
    static let maintenanceRequestDelivery: TimeInterval = 1
}

extension FlowTabTests {
    func testHomeInitialProjectionObservationWatchdogPolicyPreservesMaintenanceRequestBound() {
        let maintenanceRequestDelivery =
            HomeInitialProjectionObservationWatchdogPolicy
                .maintenanceRequestDelivery

        XCTAssertEqual(maintenanceRequestDelivery, 1)
        XCTAssertTrue(maintenanceRequestDelivery.isFinite)
        XCTAssertGreaterThan(maintenanceRequestDelivery, 0)
    }

    func testHomeInitialProjectionApplicationRouteRequiresUITestSentinelAndName() {
        let argument =
            FlowTabTestLaunchOptions
                .homeInitialProjectionApplicationRouteArgument
        let readbackArgument =
            FlowTabTestLaunchOptions
                .homeInitialProjectionApplicationReadbackPathArgument
        withLaunchArgumentsForTesting([
            "FlowTab",
            argument,
            "  test.home-initial-projection  ",
            readbackArgument,
            "  /tmp/home-initial-projection.json  "
        ]) {
            XCTAssertEqual(
                FlowTabTestLaunchOptions
                    .homeInitialProjectionApplicationRoute,
                FlowTabUITestHomeInitialProjectionApplicationRoute(
                    notificationName:
                        Notification.Name(
                            "test.home-initial-projection"
                        ),
                    readbackURL:
                        URL(
                            fileURLWithPath:
                                "/tmp/home-initial-projection.json"
                        )
                )
            )
        }
        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                argument,
                "test.home-initial-projection",
                readbackArgument,
                "/tmp/home-initial-projection.json"
            ],
            environment: [:]
        ) {
            XCTAssertNil(
                FlowTabTestLaunchOptions
                    .homeInitialProjectionApplicationRoute
            )
        }
        withLaunchArgumentsForTesting([
            "FlowTab",
            argument,
            "test.home-initial-projection",
            readbackArgument,
            "relative/home-initial-projection.json"
        ]) {
            XCTAssertNil(
                FlowTabTestLaunchOptions
                    .homeInitialProjectionApplicationRoute
            )
        }
    }

    @MainActor
    func testUITestBootstrapperKeepsRequestedHomeProjectionDegraded() {
        let previousHooks = AppDelegate.testHooks
        defer {
            AppDelegate.testHooks = previousHooks
        }
        AppDelegate.testHooks.runtimeProjectionService = nil

        withLaunchArgumentsForTesting([
            "FlowTab",
            "--flowtab-ui-mock-runtime",
            "--flowtab-ui-mock-runtime-variant",
            "degraded-home",
            "--flowtab-ui-ax-trusted",
            "true"
        ]) {
            FlowTabUITestBootstrapper.prepareIfNeeded()
        }

        let projection = AppDelegate.testHooks
            .runtimeProjectionService?
            .readHomeSummaryProjection()
        XCTAssertFalse(
            projection?.freshness.isCompleteForScope == true
        )
        XCTAssertEqual(
            projection?.summaries.prefix(2).map(\.windowCount),
            [0, 0]
        )
    }

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
            description:
                "unmetCondition=homeInitialProjectionMaintenanceRequested expectedReason=homeProjectionMissing"
        )
        maintenanceRequested.assertForOverFulfill = true
        runtimeProjectionService.setAppSwitcherMaintenanceRequestHandler {
            reason in
            guard reason == .homeProjectionMissing else { return }
            maintenanceRequested.fulfill()
        }
        defer {
            runtimeProjectionService.setAppSwitcherMaintenanceRequestHandler(nil)
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

        await fulfillment(
            of: [maintenanceRequested],
            timeout:
                HomeInitialProjectionObservationWatchdogPolicy
                    .maintenanceRequestDelivery
        )
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherMaintenanceRequestsRecorded(),
            [.homeProjectionMissing]
        )
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
        var applicationWasPublishedAfterHandoff = false
        let applicationToken = notificationCenter.addObserver(
            forName:
                .homeInitialProjectionObservationDidApply,
            object: runtimeProjectionService,
            queue: nil
        ) { notification in
            guard
                HomeInitialProjectionObservationApplication(
                    notification: notification
                ) != nil
            else {
                return
            }
            applicationWasPublishedAfterHandoff =
                appSummaryProjectionOwner.isObserving
                && !initialProjectionOwner.isObserving
        }
        defer {
            notificationCenter.removeObserver(applicationToken)
        }
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
        XCTAssertTrue(applicationWasPublishedAfterHandoff)
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

    @MainActor
    func testHomeVisibilityHandsOffDegradedProjectionAfterMaintenanceCompletion() {
        let notificationCenter = NotificationCenter()
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeSummaryProjection:
                makeHomeVisibilityDegradedSummaryProjection()
        )
        let initialProjectionOwner =
            HomeInitialProjectionObservationOwner(
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
                initialProjectionObservationOwner:
                    initialProjectionOwner,
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

        XCTAssertTrue(initialProjectionOwner.isObserving)
        XCTAssertFalse(appSummaryProjectionOwner.isObserving)
        let completion =
            RuntimeAppSwitcherProjectionMaintenanceCompletion(
                reason: .homeProjectionMissing
            )
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionMaintenanceDidFinish,
            object: runtimeProjectionService,
            userInfo: completion.notificationUserInfo
        )
        hostedView.layoutSubtreeIfNeeded()

        XCTAssertFalse(initialProjectionOwner.isObserving)
        XCTAssertTrue(appSummaryProjectionOwner.isObserving)
        let readCountBeforeCommit =
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
            readCountBeforeCommit + 1
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

    private func makeHomeVisibilityDegradedSummaryProjection()
        -> RuntimeHomeSummaryProjection
    {
        RuntimeHomeSummaryProjection(
            summaries: [
                RuntimeHomeAppSummary(
                    appID: "com.example.home-visible",
                    displayName: "Home Visible",
                    groupID: "home-visible",
                    lastActiveAt: 100,
                    windowCount: 0,
                    pid: 18_414,
                    bundleIdentifier: "com.example.home-visible"
                )
            ],
            freshness: RuntimeProjectionFreshness(
                generatedAt: 2,
                sourceGeneration:
                    RuntimeReadModelGeneration(projection: 2),
                dirtyAppIDs: ["com.example.home-visible"],
                dirtyPIDs: [18_414],
                dirtyCGWindowIDs: [],
                pendingRepairScopes: [
                    "appWindows:com.example.home-visible"
                ],
                isCompleteForScope: false
            )
        )
    }
}
