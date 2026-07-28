import Foundation
import XCTest
@testable import FlowTab
extension FlowTabTests {
    func testPermissionObservationPolicyNamesFallbackAndWatchdogDurations() {
        let policy = RuntimePermissionObservationPolicy.standard

        XCTAssertEqual(policy.fallbackReadbackInterval, 0.5)
        XCTAssertEqual(policy.permissionRequestWatchdogInterval, 20)
        XCTAssertEqual(
            policy.permissionRequestMode,
            .untilGranted(watchdogInterval: 20)
        )
        XCTAssertEqual(policy.watchdogDescription, "20s")
    }
    @MainActor
    func testPermissionObservationInstallsActivationBeforeInitialReadback() {
        let activationObserver = ManualPermissionActivationObserver()
        let scheduler = ManualPermissionObservationScheduler()
        let coordinator = RuntimePermissionObservationCoordinator(
            scheduler: scheduler,
            activationObserver: activationObserver
        )
        var observerWasInstalledAtReadback = false
        var receivedEvidence: [RuntimePermissionObservationEvidence] = []

        let initialEvidence = coordinator.start(
            target: .accessibility,
            mode: .untilGranted(watchdogInterval: 20),
            readPermission: {
                observerWasInstalledAtReadback =
                    activationObserver.availableObservationCount == 1
                return true
            },
            onEvidence: { receivedEvidence.append($0) },
            onWatchdog: { _ in XCTFail("Granted initial state must not time out.") }
        )

        XCTAssertTrue(observerWasInstalledAtReadback)
        XCTAssertTrue(initialEvidence.isGranted)
        XCTAssertEqual(initialEvidence.source, .initialReadback)
        XCTAssertEqual(receivedEvidence, [initialEvidence])
        XCTAssertFalse(coordinator.isObserving(.accessibility))
        XCTAssertEqual(activationObserver.availableObservationCount, 0)
        XCTAssertTrue(scheduler.availableEntries.isEmpty)
    }

    @MainActor
    func testPermissionObservationCompletesFromActivationEvidence() {
        let activationObserver = ManualPermissionActivationObserver()
        let scheduler = ManualPermissionObservationScheduler()
        let coordinator = RuntimePermissionObservationCoordinator(
            scheduler: scheduler,
            activationObserver: activationObserver
        )
        var isGranted = false
        var sources: [RuntimePermissionObservationEvidence.Source] = []

        coordinator.start(
            target: .screenCapture,
            mode: .untilGranted(watchdogInterval: 20),
            readPermission: { isGranted },
            onEvidence: { sources.append($0.source) },
            onWatchdog: { _ in XCTFail("Activation readback should grant permission.") }
        )
        isGranted = true
        activationObserver.fireAvailable()
        activationObserver.fireAllIncludingCancelled()

        XCTAssertEqual(sources, [.initialReadback, .appActivation])
        XCTAssertFalse(coordinator.isObserving(.screenCapture))
        XCTAssertTrue(scheduler.availableEntries.isEmpty)
    }

    @MainActor
    func testPermissionObservationFallbackUsesReadbackAsOnlySuccessEvidence() {
        let clock = ManualPermissionObservationClock(milliseconds: 0)
        let scheduler = ManualPermissionObservationScheduler()
        let coordinator = RuntimePermissionObservationCoordinator(
            clock: clock,
            scheduler: scheduler,
            activationObserver: ManualPermissionActivationObserver()
        )
        var isGranted = false
        var evidence: [RuntimePermissionObservationEvidence] = []

        coordinator.start(
            target: .accessibility,
            mode: .untilGranted(watchdogInterval: 20),
            readPermission: { isGranted },
            onEvidence: { evidence.append($0) },
            onWatchdog: { _ in XCTFail("Fallback readback should grant permission.") }
        )
        XCTAssertEqual(scheduler.availableIntervals, [0.5, 20])

        clock.milliseconds = 8_000
        isGranted = true
        scheduler.fireEntry(at: 0)

        XCTAssertEqual(evidence.map(\.source), [.initialReadback, .fallbackReadback])
        XCTAssertEqual(evidence.last?.elapsedMs, 8_000)
        XCTAssertTrue(evidence.last?.isGranted == true)
        XCTAssertTrue(scheduler.availableEntries.isEmpty)
    }

    @MainActor
    func testPermissionObservationWatchdogUsesFinalReadbackAndDiagnostic() {
        let clock = ManualPermissionObservationClock(milliseconds: 0)
        let scheduler = ManualPermissionObservationScheduler()
        let coordinator = RuntimePermissionObservationCoordinator(
            clock: clock,
            scheduler: scheduler,
            activationObserver: ManualPermissionActivationObserver()
        )
        var diagnostic: RuntimePermissionObservationDiagnostic?

        coordinator.start(
            target: .screenCapture,
            mode: .untilGranted(watchdogInterval: 20),
            identity: RuntimePermissionObservationIdentity(
                bundleIdentifier: "io.github.flowtab.tests",
                bundlePath: "/Applications/FlowTab.app"
            ),
            readPermission: { false },
            onEvidence: { _ in },
            onWatchdog: { diagnostic = $0 }
        )
        scheduler.fireEntry(at: 1)
        XCTAssertNil(diagnostic)
        XCTAssertEqual(scheduler.availableIntervals, [0.5, 20])

        clock.milliseconds = 25_000
        scheduler.fireEntry(at: 2)

        let resolvedDiagnostic = diagnostic
        XCTAssertEqual(resolvedDiagnostic?.target, .screenCapture)
        XCTAssertEqual(resolvedDiagnostic?.readbackCount, 2)
        XCTAssertEqual(resolvedDiagnostic?.elapsedMs, 25_000)
        XCTAssertEqual(resolvedDiagnostic?.finalPermissionGranted, false)
        XCTAssertEqual(resolvedDiagnostic?.finalEvidenceSource, .watchdogReadback)
        XCTAssertEqual(resolvedDiagnostic?.bundleIdentifier, "io.github.flowtab.tests")
        XCTAssertTrue(
            resolvedDiagnostic?.logMessage.contains(
                "path=/Applications/FlowTab.app"
            ) == true
        )
        XCTAssertFalse(coordinator.isObserving(.screenCapture))
    }

    @MainActor
    func testPermissionObservationDelayedWatchdogStillAcceptsGrantReadback() {
        let clock = ManualPermissionObservationClock(milliseconds: 0)
        let scheduler = ManualPermissionObservationScheduler()
        let coordinator = RuntimePermissionObservationCoordinator(
            clock: clock,
            scheduler: scheduler,
            activationObserver: ManualPermissionActivationObserver()
        )
        var isGranted = false
        var watchdogCount = 0
        var finalEvidence: RuntimePermissionObservationEvidence?

        coordinator.start(
            target: .accessibility,
            mode: .untilGranted(watchdogInterval: 20),
            readPermission: { isGranted },
            onEvidence: { finalEvidence = $0 },
            onWatchdog: { _ in watchdogCount += 1 }
        )
        clock.milliseconds = 90_000
        isGranted = true
        scheduler.fireEntry(at: 1)

        XCTAssertEqual(finalEvidence?.source, .watchdogReadback)
        XCTAssertTrue(finalEvidence?.isGranted == true)
        XCTAssertEqual(watchdogCount, 0)
        XCTAssertFalse(coordinator.isObserving(.accessibility))
    }

    @MainActor
    func testPermissionObservationCancellationRejectsSupersededCallbacks() {
        let scheduler = ManualPermissionObservationScheduler()
        let activationObserver = ManualPermissionActivationObserver()
        let coordinator = RuntimePermissionObservationCoordinator(
            scheduler: scheduler,
            activationObserver: activationObserver
        )
        var firstEvidenceCount = 0
        var secondEvidenceCount = 0
        var isGranted = false

        coordinator.start(
            target: .accessibility,
            mode: .untilGranted(watchdogInterval: 20),
            readPermission: { isGranted },
            onEvidence: { _ in firstEvidenceCount += 1 },
            onWatchdog: { _ in XCTFail("Superseded observation timed out.") }
        )
        coordinator.start(
            target: .accessibility,
            mode: .untilGranted(watchdogInterval: 20),
            readPermission: { isGranted },
            onEvidence: { _ in secondEvidenceCount += 1 },
            onWatchdog: { _ in XCTFail("Current observation timed out.") }
        )

        isGranted = true
        scheduler.fireEntry(at: 0)
        scheduler.fireEntry(at: 1)
        activationObserver.fireEntry(at: 0)
        XCTAssertEqual(firstEvidenceCount, 1)
        XCTAssertEqual(secondEvidenceCount, 1)

        scheduler.fireEntry(at: 2)
        XCTAssertEqual(secondEvidenceCount, 2)
        XCTAssertFalse(coordinator.isObserving(.accessibility))
    }

    @MainActor
    func testPermissionObservationWhileOwnedTracksBothStateTransitions() {
        let activationObserver = ManualPermissionActivationObserver()
        let scheduler = ManualPermissionObservationScheduler()
        let coordinator = RuntimePermissionObservationCoordinator(
            scheduler: scheduler,
            activationObserver: activationObserver
        )
        var isGranted = true
        var states: [Bool] = []

        coordinator.start(
            target: .accessibility,
            mode: .whileOwned,
            readPermission: { isGranted },
            onEvidence: { states.append($0.isGranted) },
            onWatchdog: { _ in XCTFail("Owned observations have no watchdog.") }
        )
        isGranted = false
        activationObserver.fireAvailable()
        isGranted = true
        scheduler.fireFirstAvailable()
        coordinator.cancelAll()

        XCTAssertEqual(states, [true, false, true])
        XCTAssertTrue(scheduler.availableEntries.isEmpty)
        XCTAssertEqual(activationObserver.availableObservationCount, 0)
    }

    @MainActor
    func testPermissionObservationRapidReplacementKeepsOneOwnedBinding() {
        let scheduler = ManualPermissionObservationScheduler()
        let activationObserver = ManualPermissionActivationObserver()
        let coordinator = RuntimePermissionObservationCoordinator(
            scheduler: scheduler,
            activationObserver: activationObserver
        )
        var evidenceCount = 0

        for _ in 0..<2_000 {
            coordinator.start(
                target: .accessibility,
                mode: .untilGranted(watchdogInterval: 20),
                readPermission: { false },
                onEvidence: { _ in evidenceCount += 1 },
                onWatchdog: { _ in XCTFail("Pressure replacement timed out.") }
            )
        }

        XCTAssertEqual(evidenceCount, 2_000)
        XCTAssertEqual(scheduler.availableEntries.count, 2)
        XCTAssertEqual(activationObserver.availableObservationCount, 1)
        coordinator.cancelAll()
        scheduler.fireAllIncludingCancelledInReverseOrder()
        activationObserver.fireAllIncludingCancelled()

        XCTAssertEqual(evidenceCount, 2_000)
        XCTAssertTrue(scheduler.availableEntries.isEmpty)
        XCTAssertEqual(activationObserver.availableObservationCount, 0)
    }
}

@MainActor
private final class ManualPermissionObservationClock:
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

private final class ManualPermissionObservationToken:
    RuntimePermissionObservationCancellable
{
    private(set) var isCancelled = false
    private(set) var didFire = false

    var isAvailable: Bool {
        !isCancelled && !didFire
    }

    func markFired() {
        didFire = true
    }

    func cancel() {
        isCancelled = true
    }
}

@MainActor
private final class ManualPermissionObservationScheduler:
    RuntimePermissionObservationScheduling
{
    struct Entry {
        let interval: TimeInterval
        let token: ManualPermissionObservationToken
        let action: @MainActor @Sendable () -> Void
    }

    private(set) var entries: [Entry] = []

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
        let token = ManualPermissionObservationToken()
        entries.append(Entry(interval: interval, token: token, action: action))
        return token
    }

    func fireEntry(at index: Int) {
        let entry = entries[index]
        entry.token.markFired()
        entry.action()
    }

    func fireFirstAvailable() {
        guard let index = entries.firstIndex(where: \.token.isAvailable) else {
            XCTFail("Expected an available scheduled permission observation.")
            return
        }
        fireEntry(at: index)
    }

    func fireAllIncludingCancelledInReverseOrder() {
        for entry in entries.reversed() {
            entry.token.markFired()
            entry.action()
        }
    }
}

@MainActor
private final class ManualPermissionActivationObserver:
    RuntimePermissionActivationObserving
{
    struct Entry {
        let token: ManualPermissionObservationToken
        let action: @MainActor @Sendable () -> Void
    }

    private(set) var entries: [Entry] = []

    var availableObservationCount: Int { entries.filter(\.token.isAvailable).count }

    func observeActivations(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimePermissionObservationCancellable {
        let token = ManualPermissionObservationToken()
        entries.append(Entry(token: token, action: action))
        return token
    }

    func fireAvailable() {
        for entry in entries where entry.token.isAvailable {
            entry.action()
        }
    }

    func fireEntry(at index: Int) { entries[index].action() }

    func fireAllIncludingCancelled() {
        for entry in entries {
            entry.action()
        }
    }
}
