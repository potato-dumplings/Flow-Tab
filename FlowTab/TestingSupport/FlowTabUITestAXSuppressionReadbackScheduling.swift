#if FLOWTAB_TESTING
import Foundation

@MainActor
protocol FlowTabUITestAXSuppressionReadbackCancellable:
    AnyObject
{
    func cancel()
}

@MainActor
protocol FlowTabUITestAXSuppressionReadbackScheduling:
    AnyObject
{
    func schedule(
        after interval: TimeInterval,
        _ action:
            @escaping @MainActor @Sendable () -> Void
    ) -> any FlowTabUITestAXSuppressionReadbackCancellable
}

@MainActor
private final class
    FlowTabUITestAXSuppressionReadbackTaskToken:
    FlowTabUITestAXSuppressionReadbackCancellable
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
final class FlowTabUITestAXSuppressionReadbackScheduler:
    FlowTabUITestAXSuppressionReadbackScheduling
{
    func schedule(
        after interval: TimeInterval,
        _ action:
            @escaping @MainActor @Sendable () -> Void
    ) -> any FlowTabUITestAXSuppressionReadbackCancellable {
        FlowTabUITestAXSuppressionReadbackTaskToken(
            interval: interval,
            action: action
        )
    }
}

@MainActor
final class FlowTabUITestAXSuppressionNotificationToken:
    FlowTabUITestAXSuppressionReadbackCancellable
{
    private let center: DistributedNotificationCenter
    private var token: NSObjectProtocol?

    init(
        center: DistributedNotificationCenter,
        token: NSObjectProtocol
    ) {
        self.center = center
        self.token = token
    }

    func cancel() {
        guard let token else { return }
        center.removeObserver(token)
        self.token = nil
    }

    deinit {
        if let token {
            center.removeObserver(token)
        }
    }
}

typealias FlowTabUITestAXSuppressionCompletionRegistration =
    @MainActor (
        FlowTabUITestAXSuppressionReadbackRoute,
        @escaping @MainActor (
            FlowTabUITestAXSuppressionCompletion
        ) -> Void
    ) -> any FlowTabUITestAXSuppressionReadbackCancellable
#endif
