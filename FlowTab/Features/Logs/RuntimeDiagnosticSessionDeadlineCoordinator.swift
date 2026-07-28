import Combine
import Foundation

struct RuntimeDiagnosticSessionDeadlinePolicy: Equatable {
    let displayedMinuteDuration: TimeInterval

    static let standard = RuntimeDiagnosticSessionDeadlinePolicy(
        displayedMinuteDuration: 60
    )

    init(displayedMinuteDuration: TimeInterval) {
        precondition(
            displayedMinuteDuration > 0,
            "Diagnostic-session display minute duration must be positive."
        )
        self.displayedMinuteDuration = displayedMinuteDuration
    }

    func displayedMinuteCount(expiration: Date, now: Date) -> Int {
        let remaining = max(0, expiration.timeIntervalSince(now))
        return max(1, Int(ceil(remaining / displayedMinuteDuration)))
    }

    func nextWakeDate(expiration: Date, now: Date) -> Date {
        let displayedMinutes = displayedMinuteCount(
            expiration: expiration,
            now: now
        )
        guard displayedMinutes > 1 else {
            return expiration
        }
        return expiration.addingTimeInterval(
            -Double(displayedMinutes - 1) * displayedMinuteDuration
        )
    }
}

@MainActor
protocol RuntimeDiagnosticSessionClockReading: AnyObject {
    var now: Date { get }
}

@MainActor
final class SystemRuntimeDiagnosticSessionClock:
    RuntimeDiagnosticSessionClockReading
{
    var now: Date {
        Date()
    }
}

protocol RuntimeDiagnosticSessionDeadlineCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol RuntimeDiagnosticSessionDeadlineScheduling: AnyObject {
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimeDiagnosticSessionDeadlineCancellable
}

private final class RuntimeDiagnosticSessionDeadlineToken:
    RuntimeDiagnosticSessionDeadlineCancellable
{
    private let task: Task<Void, Never>

    @MainActor
    init(
        interval: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        let nanoseconds = UInt64(
            (max(0, interval) * 1_000_000_000).rounded(.up)
        )
        task = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task.cancel()
    }

    deinit {
        task.cancel()
    }
}

@MainActor
final class RuntimeDiagnosticSessionDeadlineScheduler:
    RuntimeDiagnosticSessionDeadlineScheduling
{
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimeDiagnosticSessionDeadlineCancellable {
        RuntimeDiagnosticSessionDeadlineToken(
            interval: interval,
            action: action
        )
    }
}

@MainActor
final class RuntimeDiagnosticSessionDeadlineCoordinator: ObservableObject {
    @Published private(set) var observedNow: Date

    private let clock: any RuntimeDiagnosticSessionClockReading
    private let scheduler: any RuntimeDiagnosticSessionDeadlineScheduling
    private let policy: RuntimeDiagnosticSessionDeadlinePolicy
    private var scheduledToken:
        (any RuntimeDiagnosticSessionDeadlineCancellable)?
    private var observationGeneration: UInt64 = 0
    private var expirationTimestamp: Double = 0
    private var onExpired: (@MainActor () -> Void)?

    init(
        clock: (any RuntimeDiagnosticSessionClockReading)? = nil,
        scheduler:
            (any RuntimeDiagnosticSessionDeadlineScheduling)? = nil,
        policy: RuntimeDiagnosticSessionDeadlinePolicy = .standard
    ) {
        let resolvedClock =
            clock ?? SystemRuntimeDiagnosticSessionClock()
        self.clock = resolvedClock
        self.scheduler =
            scheduler ?? RuntimeDiagnosticSessionDeadlineScheduler()
        self.policy = policy
        observedNow = resolvedClock.now
    }

    @discardableResult
    func readNow() -> Date {
        let nextNow = clock.now
        observedNow = nextNow
        return nextNow
    }

    func start(
        expirationTimestamp: Double,
        onExpired: @escaping @MainActor () -> Void
    ) {
        scheduledToken?.cancel()
        scheduledToken = nil
        observationGeneration &+= 1
        self.expirationTimestamp = expirationTimestamp
        self.onExpired = expirationTimestamp > 0 ? onExpired : nil
        guard expirationTimestamp > 0 else { return }
        evaluate(generation: observationGeneration)
    }

    func stop() {
        observationGeneration &+= 1
        scheduledToken?.cancel()
        scheduledToken = nil
        expirationTimestamp = 0
        onExpired = nil
    }

    func displayedMinuteCount(expirationTimestamp: Double) -> Int {
        policy.displayedMinuteCount(
            expiration: Date(timeIntervalSince1970: expirationTimestamp),
            now: observedNow
        )
    }

    deinit {
        scheduledToken?.cancel()
    }

    private func evaluate(generation: UInt64) {
        guard generation == observationGeneration else { return }
        let now = readNow()
        let expiration = Date(
            timeIntervalSince1970: expirationTimestamp
        )
        guard now < expiration else {
            completeExpiration(generation: generation)
            return
        }

        let nextWakeDate = policy.nextWakeDate(
            expiration: expiration,
            now: now
        )
        scheduledToken = scheduler.schedule(
            after: nextWakeDate.timeIntervalSince(now)
        ) { [weak self] in
            self?.handleScheduledWake(generation: generation)
        }
    }

    private func handleScheduledWake(generation: UInt64) {
        guard generation == observationGeneration else { return }
        scheduledToken = nil
        evaluate(generation: generation)
    }

    private func completeExpiration(generation: UInt64) {
        guard generation == observationGeneration else { return }
        let completion = onExpired
        observationGeneration &+= 1
        scheduledToken = nil
        expirationTimestamp = 0
        onExpired = nil
        completion?()
    }
}
