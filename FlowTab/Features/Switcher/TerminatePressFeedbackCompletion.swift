import Foundation

struct TerminatePressFeedbackPolicy: Equatable {
    let completionInterval: TimeInterval

    static let `default` = TerminatePressFeedbackPolicy(
        completionInterval: 0.12
    )
}

struct TerminatePressFeedbackCompletion: Equatable {
    let generation: Int
    let interval: TimeInterval
}

@MainActor
protocol TerminatePressFeedbackCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol TerminatePressFeedbackScheduling: AnyObject {
    func scheduleCompletion(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any TerminatePressFeedbackCancellable
}

@MainActor
private final class TerminatePressFeedbackToken:
    TerminatePressFeedbackCancellable
{
    private let task: Task<Void, Never>

    init(
        interval: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        task = Task { @MainActor in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(
                        (interval * 1_000_000_000).rounded()
                    )
                )
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
final class TerminatePressFeedbackScheduler:
    TerminatePressFeedbackScheduling
{
    func scheduleCompletion(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any TerminatePressFeedbackCancellable {
        TerminatePressFeedbackToken(
            interval: interval,
            action: action
        )
    }
}

@MainActor
final class TerminatePressFeedbackCompletionOwner {
    private struct PendingCompletion {
        let generation: Int
        let interval: TimeInterval
        let onCompletion:
            @MainActor (TerminatePressFeedbackCompletion) -> Void
        var token: (any TerminatePressFeedbackCancellable)?
    }

    private let scheduler: any TerminatePressFeedbackScheduling
    private var pending: PendingCompletion?

    private(set) var generation = 0

    init(
        scheduler:
            (any TerminatePressFeedbackScheduling)? = nil
    ) {
        self.scheduler = scheduler
            ?? TerminatePressFeedbackScheduler()
    }

    var isPending: Bool {
        pending != nil
    }

    @discardableResult
    func start(
        after interval: TimeInterval,
        onCompletion:
            @escaping @MainActor (TerminatePressFeedbackCompletion) -> Void
    ) -> Int {
        precondition(
            interval.isFinite && interval >= 0,
            "Terminate press feedback interval must be finite and nonnegative."
        )
        cancel(invalidate: false)
        generation += 1
        let completionGeneration = generation
        pending = PendingCompletion(
            generation: completionGeneration,
            interval: interval,
            onCompletion: onCompletion
        )

        let token = scheduler.scheduleCompletion(
            after: interval
        ) { [weak self] in
            self?.complete(generation: completionGeneration)
        }
        guard var current = pending,
              current.generation == completionGeneration
        else {
            token.cancel()
            return completionGeneration
        }
        current.token = token
        pending = current
        return completionGeneration
    }

    func cancel(invalidate: Bool = true) {
        pending?.token?.cancel()
        pending = nil
        if invalidate {
            generation += 1
        }
    }

    private func complete(generation: Int) {
        guard let current = pending,
              current.generation == generation
        else {
            return
        }
        pending = nil
        current.token?.cancel()
        current.onCompletion(
            TerminatePressFeedbackCompletion(
                generation: generation,
                interval: current.interval
            )
        )
    }
}
