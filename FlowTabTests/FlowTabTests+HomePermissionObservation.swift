import AppKit
import Combine
import Foundation
import SwiftUI
import XCTest
@testable import FlowTab

extension FlowTabTests {
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
            description: "Home applied initial permission readback."
        )
        initialReadbackApplied.expectedFulfillmentCount = 2
        let stateObservation = owner.objectWillChange.sink {
            initialReadbackApplied.fulfill()
        }
        let observationStopped = expectation(
            description: "Home cancelled both fallback readbacks."
        )
        observationStopped.expectedFulfillmentCount = 2
        scheduler.onTokenCancelled = {
            observationStopped.fulfill()
        }
        let runtimeProjectionService =
            RecordingRuntimeProjectionService()
        let hostedView = NSHostingView(
            rootView: HomeLandingView(
                isActive: true,
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

        await fulfillment(of: [initialReadbackApplied], timeout: 1)
        XCTAssertTrue(owner.isObserving(.accessibility))
        XCTAssertTrue(owner.isObserving(.screenCapture))

        hostedView.rootView = HomeLandingView(
            isActive: false,
            appLanguage: .english,
            runtimeProjectionService: runtimeProjectionService,
            permissionObservationOwner: owner,
            openSettings: {}
        )
        hostedView.layoutSubtreeIfNeeded()

        await fulfillment(of: [observationStopped], timeout: 1)
        XCTAssertFalse(owner.isObserving(.accessibility))
        XCTAssertFalse(owner.isObserving(.screenCapture))
        XCTAssertEqual(activationObserver.availableObservationCount, 0)
        withExtendedLifetime(stateObservation) {}
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
