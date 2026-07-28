import Foundation
import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testDiagnosticSessionDeadlinePolicyUsesExactMinuteTransitions() {
        let policy = RuntimeDiagnosticSessionDeadlinePolicy.standard
        let expiration = Date(timeIntervalSince1970: 900)

        XCTAssertEqual(
            policy.displayedMinuteCount(
                expiration: expiration,
                now: Date(timeIntervalSince1970: 0)
            ),
            15
        )
        XCTAssertEqual(
            policy.nextWakeDate(
                expiration: expiration,
                now: Date(timeIntervalSince1970: 0)
            ),
            Date(timeIntervalSince1970: 60)
        )
        XCTAssertEqual(
            policy.displayedMinuteCount(
                expiration: expiration,
                now: Date(timeIntervalSince1970: 60)
            ),
            14
        )
        XCTAssertEqual(
            policy.nextWakeDate(
                expiration: expiration,
                now: Date(timeIntervalSince1970: 839)
            ),
            Date(timeIntervalSince1970: 840)
        )
        XCTAssertEqual(
            policy.nextWakeDate(
                expiration: expiration,
                now: Date(timeIntervalSince1970: 840)
            ),
            expiration
        )
    }

    @MainActor
    func testDiagnosticSessionDeadlineExpiresFromInitialClockReadback() {
        let clock = ManualRuntimeDiagnosticSessionClock(
            now: Date(timeIntervalSince1970: 100)
        )
        let scheduler = ManualRuntimeDiagnosticSessionDeadlineScheduler()
        let coordinator = RuntimeDiagnosticSessionDeadlineCoordinator(
            clock: clock,
            scheduler: scheduler
        )
        var expirationCount = 0

        coordinator.start(expirationTimestamp: 99) {
            expirationCount += 1
        }

        XCTAssertEqual(expirationCount, 1)
        XCTAssertEqual(coordinator.observedNow, clock.now)
        XCTAssertTrue(scheduler.pendingIntervals.isEmpty)
    }

    @MainActor
    func testDiagnosticSessionDeadlineRequiresClockEvidenceAfterEarlyWake() {
        let clock = ManualRuntimeDiagnosticSessionClock(
            now: Date(timeIntervalSince1970: 0)
        )
        let scheduler = ManualRuntimeDiagnosticSessionDeadlineScheduler()
        let coordinator = RuntimeDiagnosticSessionDeadlineCoordinator(
            clock: clock,
            scheduler: scheduler
        )
        var expirationCount = 0

        coordinator.start(expirationTimestamp: 120) {
            expirationCount += 1
        }
        XCTAssertEqual(scheduler.pendingIntervals, [60])

        scheduler.invokeEntry(at: 0)
        XCTAssertEqual(expirationCount, 0)
        XCTAssertEqual(scheduler.pendingIntervals, [60])

        clock.now = Date(timeIntervalSince1970: 60)
        scheduler.invokeEntry(at: 1)
        XCTAssertEqual(expirationCount, 0)
        XCTAssertEqual(coordinator.observedNow, clock.now)
        XCTAssertEqual(scheduler.pendingIntervals, [60])

        clock.now = Date(timeIntervalSince1970: 145)
        scheduler.invokeEntry(at: 2)
        XCTAssertEqual(expirationCount, 1)
        XCTAssertEqual(coordinator.observedNow, clock.now)
        XCTAssertTrue(scheduler.pendingIntervals.isEmpty)
    }

    @MainActor
    func testDiagnosticSessionDeadlineCancelsAndRejectsSupersededWake() {
        let clock = ManualRuntimeDiagnosticSessionClock(
            now: Date(timeIntervalSince1970: 0)
        )
        let scheduler = ManualRuntimeDiagnosticSessionDeadlineScheduler()
        let coordinator = RuntimeDiagnosticSessionDeadlineCoordinator(
            clock: clock,
            scheduler: scheduler
        )
        var firstExpirationCount = 0
        var secondExpirationCount = 0

        coordinator.start(expirationTimestamp: 120) {
            firstExpirationCount += 1
        }
        coordinator.start(expirationTimestamp: 180) {
            secondExpirationCount += 1
        }

        XCTAssertTrue(scheduler.entries[0].token.isCancelled)
        scheduler.invokeEntry(at: 0)
        XCTAssertEqual(firstExpirationCount, 0)
        XCTAssertEqual(secondExpirationCount, 0)
        XCTAssertEqual(scheduler.entries.count, 2)

        coordinator.stop()
        XCTAssertTrue(scheduler.entries[1].token.isCancelled)
        clock.now = Date(timeIntervalSince1970: 200)
        scheduler.invokeEntry(at: 1)
        XCTAssertEqual(firstExpirationCount, 0)
        XCTAssertEqual(secondExpirationCount, 0)
        XCTAssertEqual(scheduler.entries.count, 2)
    }

    @MainActor
    func testDiagnosticSessionDeadlineStopsStoredSessionAfterSlowWake() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = ManualRuntimeDiagnosticSessionClock(now: startDate)
        let scheduler = ManualRuntimeDiagnosticSessionDeadlineScheduler()
        let coordinator = RuntimeDiagnosticSessionDeadlineCoordinator(
            clock: clock,
            scheduler: scheduler
        )
        var boundExpiration = RuntimeDiagnosticSessionStore.start(
            userDefaults: userDefaults,
            now: startDate
        ).timeIntervalSince1970

        coordinator.start(expirationTimestamp: boundExpiration) {
            RuntimeDiagnosticSessionStore.stop(userDefaults: userDefaults)
            boundExpiration = 0
        }
        clock.now = Date(
            timeIntervalSince1970:
                boundExpiration + 30
        )
        scheduler.invokeEntry(at: 0)

        XCTAssertEqual(boundExpiration, 0)
        XCTAssertNil(
            userDefaults.object(
                forKey: AppPreferenceKeys.diagnosticSessionExpiration
            )
        )
        XCTAssertFalse(
            RuntimeDiagnosticSessionStore.readIsActive(
                userDefaults: userDefaults,
                now: clock.now
            )
        )
    }

    @MainActor
    func testDiagnosticSessionDeadlineRapidRestartsKeepOneOwnedWake() {
        let clock = ManualRuntimeDiagnosticSessionClock(
            now: Date(timeIntervalSince1970: 0)
        )
        let scheduler = ManualRuntimeDiagnosticSessionDeadlineScheduler()
        let coordinator = RuntimeDiagnosticSessionDeadlineCoordinator(
            clock: clock,
            scheduler: scheduler
        )
        var expirationCount = 0
        let restartCount = 2_000

        for index in 0..<restartCount {
            coordinator.start(
                expirationTimestamp: Double(900 + index)
            ) {
                expirationCount += 1
            }
        }

        XCTAssertEqual(scheduler.entries.count, restartCount)
        XCTAssertEqual(scheduler.pendingIntervals.count, 1)
        XCTAssertTrue(
            scheduler.entries.dropLast().allSatisfy(\.token.isCancelled)
        )

        coordinator.stop()
        XCTAssertTrue(scheduler.pendingIntervals.isEmpty)
        for index in scheduler.entries.indices.reversed() {
            scheduler.invokeEntry(at: index)
        }

        XCTAssertEqual(expirationCount, 0)
        XCTAssertEqual(scheduler.entries.count, restartCount)
        XCTAssertTrue(scheduler.pendingIntervals.isEmpty)
    }
}

@MainActor
private final class ManualRuntimeDiagnosticSessionClock:
    RuntimeDiagnosticSessionClockReading
{
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

private final class ManualRuntimeDiagnosticSessionDeadlineToken:
    RuntimeDiagnosticSessionDeadlineCancellable
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
private final class ManualRuntimeDiagnosticSessionDeadlineScheduler:
    RuntimeDiagnosticSessionDeadlineScheduling
{
    struct Entry {
        let interval: TimeInterval
        let token: ManualRuntimeDiagnosticSessionDeadlineToken
        let action: @MainActor @Sendable () -> Void
    }

    private(set) var entries: [Entry] = []

    var pendingIntervals: [TimeInterval] {
        entries.compactMap {
            $0.token.isAvailable ? $0.interval : nil
        }
    }

    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimeDiagnosticSessionDeadlineCancellable {
        let token = ManualRuntimeDiagnosticSessionDeadlineToken()
        entries.append(
            Entry(
                interval: interval,
                token: token,
                action: action
            )
        )
        return token
    }

    func invokeEntry(at index: Int) {
        let entry = entries[index]
        entry.token.markFired()
        entry.action()
    }
}
