import Foundation

@MainActor
protocol FocusedWindowSessionFreshnessScheduling: AnyObject {
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any FocusedWindowSessionFreshnessCancellable
}

@MainActor
protocol FocusedWindowSessionFreshnessCancellable: AnyObject {
    func cancel()
}

@MainActor
private final class FocusedWindowSessionFreshnessToken:
    FocusedWindowSessionFreshnessCancellable
{
    private var task: Task<Void, Never>?

    init(
        interval: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        let nanoseconds = UInt64((interval * 1_000_000_000).rounded())
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            task = nil
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

@MainActor
final class FocusedWindowSessionFreshnessScheduler:
    FocusedWindowSessionFreshnessScheduling
{
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any FocusedWindowSessionFreshnessCancellable {
        FocusedWindowSessionFreshnessToken(
            interval: interval,
            action: action
        )
    }
}

@MainActor
final class FocusedWindowSessionFreshnessObservationOwner {
    static let watchdogInterval: TimeInterval = 2

    private let scheduler: any FocusedWindowSessionFreshnessScheduling
    private var watchdogToken:
        (any FocusedWindowSessionFreshnessCancellable)?
    private(set) var generation = 0
    private(set) var isObserving = false

    init(
        scheduler:
            (any FocusedWindowSessionFreshnessScheduling)? = nil
    ) {
        self.scheduler = scheduler
            ?? FocusedWindowSessionFreshnessScheduler()
    }

    @discardableResult
    func start(
        after interval: TimeInterval = watchdogInterval,
        onExpired: @escaping @MainActor (Int) -> Void
    ) -> Int {
        precondition(
            interval.isFinite && interval > 0,
            "Focused-window freshness watchdog must be finite and positive."
        )
        cancel(invalidate: false)
        generation += 1
        let observationGeneration = generation
        isObserving = true
        watchdogToken = scheduler.schedule(after: interval) {
            [weak self] in
            guard let self,
                  self.isObserving,
                  self.generation == observationGeneration
            else {
                return
            }
            self.watchdogToken = nil
            self.isObserving = false
            onExpired(observationGeneration)
        }
        return observationGeneration
    }

    @discardableResult
    func resolve(generation: Int) -> Bool {
        guard isObserving, self.generation == generation else {
            return false
        }
        watchdogToken?.cancel()
        watchdogToken = nil
        isObserving = false
        return true
    }

    func cancel(invalidate: Bool = true) {
        watchdogToken?.cancel()
        watchdogToken = nil
        isObserving = false
        if invalidate {
            generation += 1
        }
    }
}
