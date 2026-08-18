import AppKit
import Foundation

struct TerminateInterruptionProtectionPolicy: Equatable {
    var completionWatchdogInterval: TimeInterval

    static let `default` = TerminateInterruptionProtectionPolicy(
        completionWatchdogInterval: 5.0
    )
}

@MainActor
protocol TerminateInterruptionProtectionCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol TerminateInterruptionProtectionScheduling: AnyObject {
    func scheduleWatchdog(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any TerminateInterruptionProtectionCancellable
}

@MainActor
protocol TerminateTargetProcessStateReading: AnyObject {
    func state(forPID pid: pid_t) -> TerminateTargetProcessState
}

@MainActor
final class SystemTerminateTargetProcessStateReader:
    TerminateTargetProcessStateReading
{
    func state(forPID pid: pid_t) -> TerminateTargetProcessState {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return .terminated
        }
        return app.isTerminated ? .terminated : .running
    }
}

@MainActor
private final class TerminateInterruptionProtectionToken:
    TerminateInterruptionProtectionCancellable
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
final class TerminateInterruptionProtectionScheduler:
    TerminateInterruptionProtectionScheduling
{
    func scheduleWatchdog(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any TerminateInterruptionProtectionCancellable {
        TerminateInterruptionProtectionToken(
            interval: interval,
            action: action
        )
    }
}
