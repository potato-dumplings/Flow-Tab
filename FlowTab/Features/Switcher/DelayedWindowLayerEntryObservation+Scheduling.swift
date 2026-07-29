import Foundation

@MainActor
protocol DelayedWindowLayerEntryCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol DelayedWindowLayerEntryScheduling: AnyObject {
    var nowMilliseconds: Double { get }

    func scheduleDeadline(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any DelayedWindowLayerEntryCancellable
}

@MainActor
private final class DelayedWindowLayerEntryToken:
    DelayedWindowLayerEntryCancellable
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
final class DelayedWindowLayerEntryScheduler:
    DelayedWindowLayerEntryScheduling
{
    var nowMilliseconds: Double {
        ProcessInfo.processInfo.systemUptime * 1_000
    }

    func scheduleDeadline(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any DelayedWindowLayerEntryCancellable {
        DelayedWindowLayerEntryToken(
            interval: interval,
            action: action
        )
    }
}
