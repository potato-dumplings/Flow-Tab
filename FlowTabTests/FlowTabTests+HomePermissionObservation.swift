import AppKit
import Combine
import Foundation
import SwiftUI
import XCTest
@testable import FlowTab

private enum HomePermissionObservationLifecycleWatchdogPolicy {
    static let eventDelivery: TimeInterval = 1
}

extension FlowTabTests {
    func testHomePermissionObservationLifecycleWatchdogPolicyPreservesEventDeliveryBound() {
        let eventDelivery =
            HomePermissionObservationLifecycleWatchdogPolicy.eventDelivery

        XCTAssertEqual(eventDelivery, 1)
        XCTAssertTrue(eventDelivery.isFinite)
        XCTAssertGreaterThan(eventDelivery, 0)
    }

    @MainActor
    func testHomeLandingVisibilityOwnsPermissionObservationLifecycle() async {
        let scheduler = HomePermissionManualScheduler()
        let activationObserver = HomePermissionManualActivationObserver()
        let coordinator = RuntimePermissionObservationCoordinator(
            scheduler: scheduler,
            activationObserver: activationObserver,
            policy: RuntimePermissionObservationPolicy(
                fallbackReadbackInterval:
                    HomePermissionObservationOwner
                        .fallbackReadbackInterval,
                permissionRequestWatchdogInterval: 20
            )
        )
        let owner = HomePermissionObservationOwner(
            accessibilityTrusted: true,
            screenCaptureTrusted: true,
            coordinator: coordinator,
            readAccessibilityPermission: { false },
            readScreenCapturePermission: { false }
        )
        let initialReadbackApplied = expectation(
            description:
                "unmetCondition=bothHomePermissionInitialReadbacksPublished"
        )
        initialReadbackApplied.expectedFulfillmentCount = 2
        initialReadbackApplied.assertForOverFulfill = true
        let stateObservation = owner.objectWillChange.sink {
            initialReadbackApplied.fulfill()
        }
        let observationStopped = expectation(
            description:
                "unmetCondition=bothHomePermissionFallbackTokensCancelled"
        )
        observationStopped.expectedFulfillmentCount = 2
        observationStopped.assertForOverFulfill = true
        scheduler.onTokenCancelled = {
            observationStopped.fulfill()
        }
        defer {
            scheduler.onTokenCancelled = nil
            stateObservation.cancel()
            owner.stop()
        }
        let runtimeProjectionService =
            RecordingRuntimeProjectionService()
        let lifecycle = HomeRetainedTabLifecycle(state: .active)
        let hostedView = NSHostingView(
            rootView: HomeLandingView(
                lifecycle: lifecycle,
                appLanguage: .english,
                runtimeProjectionService: runtimeProjectionService,
                permissionObservationOwner: owner,
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
            of: [initialReadbackApplied],
            timeout:
                HomePermissionObservationLifecycleWatchdogPolicy
                    .eventDelivery
        )
        XCTAssertFalse(owner.accessibilityTrusted)
        XCTAssertFalse(owner.screenCaptureTrusted)
        XCTAssertTrue(owner.isObserving(.accessibility))
        XCTAssertTrue(owner.isObserving(.screenCapture))
        XCTAssertEqual(scheduler.availableEntries.count, 2)
        XCTAssertEqual(activationObserver.availableObservationCount, 1)

        XCTAssertTrue(lifecycle.transition(to: .inactive))
        hostedView.layoutSubtreeIfNeeded()

        await fulfillment(
            of: [observationStopped],
            timeout:
                HomePermissionObservationLifecycleWatchdogPolicy
                    .eventDelivery
        )
        XCTAssertFalse(owner.isObserving(.accessibility))
        XCTAssertFalse(owner.isObserving(.screenCapture))
        XCTAssertTrue(scheduler.availableEntries.isEmpty)
        XCTAssertEqual(activationObserver.availableObservationCount, 0)
    }

    @MainActor
    func testHomePermissionOwnerUsesInitialActivationAndDelayedReadbackEvidence() {
        let clock = HomePermissionManualClock(milliseconds: 0)
        let scheduler = HomePermissionManualScheduler()
        let activationObserver = HomePermissionManualActivationObserver()
        let coordinator = RuntimePermissionObservationCoordinator(
            clock: clock,
            scheduler: scheduler,
            activationObserver: activationObserver,
            policy: RuntimePermissionObservationPolicy(
                fallbackReadbackInterval:
                    HomePermissionObservationOwner
                        .fallbackReadbackInterval,
                permissionRequestWatchdogInterval: 20
            )
        )
        var accessibilityTrusted = true
        var screenCaptureTrusted = false
        var changes: [RuntimePermissionObservationEvidence] = []
        let owner = HomePermissionObservationOwner(
            accessibilityTrusted: false,
            screenCaptureTrusted: false,
            coordinator: coordinator,
            readAccessibilityPermission: {
                accessibilityTrusted
            },
            readScreenCapturePermission: {
                screenCaptureTrusted
            }
        )

        owner.start { changes.append($0) }

        XCTAssertTrue(owner.accessibilityTrusted)
        XCTAssertFalse(owner.screenCaptureTrusted)
        XCTAssertEqual(changes.map(\.source), [.initialReadback])
        XCTAssertEqual(changes.map(\.target), [.accessibility])
        XCTAssertTrue(owner.isObserving(.accessibility))
        XCTAssertTrue(owner.isObserving(.screenCapture))
        XCTAssertEqual(
            scheduler.availableIntervals,
            [
                HomePermissionObservationOwner
                    .fallbackReadbackInterval,
                HomePermissionObservationOwner
                    .fallbackReadbackInterval
            ]
        )
        XCTAssertEqual(activationObserver.availableObservationCount, 1)

        screenCaptureTrusted = true
        activationObserver.fireAvailable()

        XCTAssertTrue(owner.screenCaptureTrusted)
        XCTAssertEqual(changes.last?.target, .screenCapture)
        XCTAssertEqual(changes.last?.source, .appActivation)

        clock.milliseconds = 60_000
        accessibilityTrusted = false
        scheduler.fireEntry(at: 0)

        XCTAssertFalse(owner.accessibilityTrusted)
        XCTAssertEqual(changes.last?.target, .accessibility)
        XCTAssertEqual(changes.last?.source, .fallbackReadback)
        XCTAssertEqual(changes.last?.elapsedMs, 60_000)

        let changeCountBeforeStop = changes.count
        owner.stop()
        scheduler.fireAllIncludingCancelled()
        activationObserver.fireAllIncludingCancelled()

        XCTAssertFalse(owner.isObserving(.accessibility))
        XCTAssertFalse(owner.isObserving(.screenCapture))
        XCTAssertTrue(scheduler.availableEntries.isEmpty)
        XCTAssertEqual(activationObserver.availableObservationCount, 0)
        XCTAssertEqual(changes.count, changeCountBeforeStop)
    }

    @MainActor
    func testHomePermissionOwnerRapidLifecycleKeepsOneOwnedObservationSet() {
        let scheduler = HomePermissionManualScheduler()
        let activationObserver = HomePermissionManualActivationObserver()
        let coordinator = RuntimePermissionObservationCoordinator(
            scheduler: scheduler,
            activationObserver: activationObserver,
            policy: RuntimePermissionObservationPolicy(
                fallbackReadbackInterval:
                    HomePermissionObservationOwner
                        .fallbackReadbackInterval,
                permissionRequestWatchdogInterval: 20
            )
        )
        var changeCount = 0
        let owner = HomePermissionObservationOwner(
            accessibilityTrusted: false,
            screenCaptureTrusted: false,
            coordinator: coordinator,
            readAccessibilityPermission: { false },
            readScreenCapturePermission: { false }
        )

        owner.start { _ in changeCount += 1 }
        owner.start { _ in changeCount += 1 }
        XCTAssertEqual(scheduler.availableEntries.count, 2)
        XCTAssertEqual(activationObserver.availableObservationCount, 1)
        owner.stop()

        for _ in 0..<2_000 {
            owner.start { _ in changeCount += 1 }
            owner.stop()
        }
        scheduler.fireAllIncludingCancelled()
        activationObserver.fireAllIncludingCancelled()

        XCTAssertEqual(changeCount, 0)
        XCTAssertTrue(scheduler.availableEntries.isEmpty)
        XCTAssertEqual(activationObserver.availableObservationCount, 0)

        owner.start { _ in changeCount += 1 }

        XCTAssertEqual(scheduler.availableEntries.count, 2)
        XCTAssertEqual(activationObserver.availableObservationCount, 1)
        owner.stop()
    }

    @MainActor
    func testHomeAccessibilityTransitionsRefreshOnlyAfterPermissionEvidence() {
        let notificationCenter = NotificationCenter()
        let scheduler = HomePermissionManualScheduler()
        let activationObserver = HomePermissionManualActivationObserver()
        let coordinator = RuntimePermissionObservationCoordinator(
            scheduler: scheduler,
            activationObserver: activationObserver,
            policy: RuntimePermissionObservationPolicy(
                fallbackReadbackInterval:
                    HomePermissionObservationOwner
                        .fallbackReadbackInterval,
                permissionRequestWatchdogInterval: 20
            )
        )
        let appID = "com.example.permission-transition"
        let pid: pid_t = 18_419
        var accessibilityGranted = false

        func summaryProjection(
            generation: UInt64,
            isComplete: Bool
        ) -> RuntimeHomeSummaryProjection {
            RuntimeHomeSummaryProjection(
                summaries: [
                    RuntimeHomeAppSummary(
                        appID: appID,
                        displayName: "Permission Transition",
                        groupID: "permission-transition",
                        lastActiveAt: TimeInterval(generation),
                        windowCount: 1,
                        pid: pid
                    )
                ],
                freshness: RuntimeProjectionFreshness(
                    generatedAt: TimeInterval(generation),
                    sourceGeneration:
                        RuntimeReadModelGeneration(
                            projection: generation
                        ),
                    dirtyAppIDs: isComplete ? [] : [appID],
                    dirtyPIDs: isComplete ? [] : [pid],
                    dirtyCGWindowIDs: [],
                    pendingRepairScopes:
                        isComplete ? [] : ["appDirectory"],
                    isCompleteForScope: isComplete
                )
            )
        }

        let runtimeProjectionService = RecordingRuntimeProjectionService(
            homeSummaryProjection: summaryProjection(
                generation: 1,
                isComplete: false
            )
        )
        let detailOwner = HomeAppDetailProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        let summaryOwner = HomeAppSummaryProjectionObservationOwner(
            runtimeProjectionService: runtimeProjectionService,
            notificationCenter: notificationCenter
        )
        let lifecycle = HomeRetainedTabLifecycle(state: .active)
        let hostedView = NSHostingView(
            rootView: HomeLandingView(
                lifecycle: lifecycle,
                appLanguage: .english,
                runtimeProjectionService: runtimeProjectionService,
                permissionObservationOwner:
                    HomePermissionObservationOwner(
                        accessibilityTrusted: false,
                        screenCaptureTrusted: true,
                        coordinator: coordinator,
                        readAccessibilityPermission: {
                            accessibilityGranted
                        },
                        readScreenCapturePermission: { true }
                    ),
                initialProjectionObservationOwner:
                    HomeInitialProjectionObservationOwner(
                        runtimeProjectionService:
                            runtimeProjectionService,
                        notificationCenter: notificationCenter
                    ),
                appSummaryProjectionObservationOwner: summaryOwner,
                appDetailProjectionObservationOwner: detailOwner,
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
        notificationCenter.post(
            name: .runtimeAppSwitcherProjectionMaintenanceDidFinish,
            object: runtimeProjectionService,
            userInfo:
                RuntimeAppSwitcherProjectionMaintenanceCompletion(
                    reason: .homeProjectionMissing
                ).notificationUserInfo
        )
        hostedView.layoutSubtreeIfNeeded()

        XCTAssertTrue(summaryOwner.hasResolvedProjection)
        XCTAssertEqual(
            runtimeProjectionService.homeDetailProjectionReadCount(
                appID: appID
            ),
            0
        )
        XCTAssertTrue(
            runtimeProjectionService
                .selectedCurrentAppWindowChangeSignalsRecorded()
                .isEmpty
        )

        var generation: UInt64 = 1
        runtimeProjectionService
            .setAppSwitcherMaintenanceRequestHandler { _ in
                generation += 1
                runtimeProjectionService.setHomeSummaryProjection(
                    summaryProjection(
                        generation: generation,
                        isComplete: true
                    )
                )
            }

        accessibilityGranted = true
        activationObserver.fireAvailable()
        hostedView.layoutSubtreeIfNeeded()

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
        XCTAssertTrue(detailOwner.isObserving(appID: appID))

        accessibilityGranted = false
        activationObserver.fireAvailable()
        hostedView.layoutSubtreeIfNeeded()

        XCTAssertFalse(detailOwner.isObserving(appID: appID))
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
        XCTAssertEqual(
            runtimeProjectionService
                .appSwitcherMaintenanceRequestsRecorded(),
            [
                .homeProjectionMissing,
                .homeProjectionMissing,
                .homeProjectionMissing
            ]
        )

        XCTAssertTrue(lifecycle.transition(to: .inactive))
        hostedView.layoutSubtreeIfNeeded()
    }
}

@MainActor
private final class HomePermissionManualClock:
    RuntimePermissionObservationClockReading
{
    var milliseconds: Double

    init(milliseconds: Double) {
        self.milliseconds = milliseconds
    }

    var monotonicMilliseconds: Double {
        milliseconds
    }
}

private final class HomePermissionManualToken:
    RuntimePermissionObservationCancellable
{
    private(set) var isCancelled = false
    private(set) var didFire = false
    private let onCancel: () -> Void

    init(onCancel: @escaping () -> Void = {}) {
        self.onCancel = onCancel
    }

    var isAvailable: Bool {
        !isCancelled && !didFire
    }

    func markFired() {
        didFire = true
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel()
    }
}

@MainActor
private final class HomePermissionManualScheduler:
    RuntimePermissionObservationScheduling
{
    struct Entry {
        let interval: TimeInterval
        let token: HomePermissionManualToken
        let action: @MainActor @Sendable () -> Void
    }

    private(set) var entries: [Entry] = []
    var onTokenCancelled: (() -> Void)?

    var availableEntries: [Entry] {
        entries.filter(\.token.isAvailable)
    }

    var availableIntervals: [TimeInterval] {
        availableEntries.map(\.interval)
    }

    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimePermissionObservationCancellable {
        let cancellation = onTokenCancelled
        let token = HomePermissionManualToken {
            cancellation?()
        }
        entries.append(
            Entry(interval: interval, token: token, action: action)
        )
        return token
    }

    func fireEntry(at index: Int) {
        let entry = entries[index]
        entry.token.markFired()
        entry.action()
    }

    func fireAllIncludingCancelled() {
        for entry in entries {
            entry.token.markFired()
            entry.action()
        }
    }
}

@MainActor
private final class HomePermissionManualActivationObserver:
    RuntimePermissionActivationObserving
{
    struct Entry {
        let token: HomePermissionManualToken
        let action: @MainActor @Sendable () -> Void
    }

    private(set) var entries: [Entry] = []

    var availableObservationCount: Int {
        entries.filter(\.token.isAvailable).count
    }

    func observeActivations(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimePermissionObservationCancellable {
        let token = HomePermissionManualToken()
        entries.append(Entry(token: token, action: action))
        return token
    }

    func fireAvailable() {
        for entry in entries where entry.token.isAvailable {
            entry.action()
        }
    }

    func fireAllIncludingCancelled() {
        for entry in entries {
            entry.action()
        }
    }
}
