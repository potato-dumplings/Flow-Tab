#if FLOWTAB_TESTING
import Foundation

@MainActor
protocol FlowTabUITestInitialPresentationCancellable:
    AnyObject
{
    func cancel()
}

@MainActor
protocol FlowTabUITestInitialPresentationScheduling:
    AnyObject
{
    func schedule(
        after interval: TimeInterval,
        _ action:
            @escaping @MainActor @Sendable () -> Void
    ) -> any FlowTabUITestInitialPresentationCancellable
}

@MainActor
private final class FlowTabUITestInitialPresentationToken:
    FlowTabUITestInitialPresentationCancellable
{
    private let task: Task<Void, Never>

    init(
        interval: TimeInterval,
        action:
            @escaping @MainActor @Sendable () -> Void
    ) {
        let nanoseconds = UInt64(
            (interval * 1_000_000_000).rounded()
        )
        task = Task { @MainActor in
            do {
                try await Task.sleep(
                    nanoseconds: nanoseconds
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
final class FlowTabUITestInitialPresentationScheduler:
    FlowTabUITestInitialPresentationScheduling
{
    func schedule(
        after interval: TimeInterval,
        _ action:
            @escaping @MainActor @Sendable () -> Void
    ) -> any FlowTabUITestInitialPresentationCancellable {
        FlowTabUITestInitialPresentationToken(
            interval: interval,
            action: action
        )
    }
}
#endif
