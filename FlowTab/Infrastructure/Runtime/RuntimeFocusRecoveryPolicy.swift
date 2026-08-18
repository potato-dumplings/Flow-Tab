import CoreGraphics
import Foundation

struct RuntimeFocusRecoveryPolicy: Equatable {
    let pollingIntervals: [TimeInterval]
    let watchdogInterval: TimeInterval

    static let standard = RuntimeFocusRecoveryPolicy(
        pollingIntervals: [0.05, 0.15, 0.5],
        watchdogInterval: 5
    )
    static let disabled = RuntimeFocusRecoveryPolicy(
        pollingIntervals: [],
        watchdogInterval: 5
    )

    init(
        pollingIntervals: [TimeInterval],
        watchdogInterval: TimeInterval
    ) {
        precondition(
            pollingIntervals.allSatisfy { $0 > 0 },
            "Focus recovery polling intervals must be positive."
        )
        precondition(
            watchdogInterval > 0,
            "Focus recovery watchdog interval must be positive."
        )
        self.pollingIntervals = pollingIntervals
        self.watchdogInterval = watchdogInterval
    }

    var isEnabled: Bool {
        !pollingIntervals.isEmpty
    }

    func pollingInterval(forAttempt attempt: Int) -> TimeInterval {
        let index = max(0, attempt - 1)
        return pollingIntervals[min(index, pollingIntervals.count - 1)]
    }
}

enum RuntimeFocusRecoveryTrigger: Equatable {
    case initialReadback
    case targetApplicationActivated
    case activeSpaceChanged
    case appSwitcherProjectionUpdated
    case currentAppWindowProjectionUpdated
    case polling(attempt: Int)
    case watchdogReadback
    case targetApplicationTerminated

    var logValue: String {
        switch self {
        case .initialReadback:
            "initialReadback"
        case .targetApplicationActivated:
            "targetApplicationActivated"
        case .activeSpaceChanged:
            "activeSpaceChanged"
        case .appSwitcherProjectionUpdated:
            "appSwitcherProjectionUpdated"
        case .currentAppWindowProjectionUpdated:
            "currentAppWindowProjectionUpdated"
        case let .polling(attempt):
            "polling:\(attempt)"
        case .watchdogReadback:
            "watchdogReadback"
        case .targetApplicationTerminated:
            "targetApplicationTerminated"
        }
    }

    var permitsRecoveryAction: Bool {
        if case .polling = self {
            return true
        }
        return false
    }
}

struct RuntimeFocusRecoveryTarget: Equatable {
    let appID: String
    let pid: pid_t
    let windowID: String
    let targetCGWindowID: CGWindowID?
}

struct RuntimeFocusRecoveryObservation: Equatable {
    let conditionSatisfied: Bool
    let processIsTerminated: Bool
    let targetIsVisible: Bool
    let focusedCGWindowID: CGWindowID?
    let frontmostCGWindowID: CGWindowID?
    let visibleCGWindowIDs: [CGWindowID]
}

struct RuntimeFocusRecoveryReadback {
    let completed: Bool
    let observation: RuntimeFocusRecoveryObservation
}

struct RuntimeFocusRecoveryFailure: Equatable {
    enum Reason: String, Equatable {
        case watchdogExpired
        case targetApplicationTerminated
    }

    let reason: Reason
    let generation: UInt64
    let target: RuntimeFocusRecoveryTarget
    let pollingAttempt: Int
    let lastTrigger: RuntimeFocusRecoveryTrigger
    let lastObservation: RuntimeFocusRecoveryObservation
}

protocol RuntimeFocusRecoveryCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol RuntimeFocusRecoveryScheduling: AnyObject {
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimeFocusRecoveryCancellable
}

private final class RuntimeFocusRecoveryToken: RuntimeFocusRecoveryCancellable {
    private let task: Task<Void, Never>

    @MainActor
    init(
        interval: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        let nanoseconds = UInt64((interval * 1_000_000_000).rounded())
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
}

@MainActor
final class RuntimeFocusRecoveryScheduler: RuntimeFocusRecoveryScheduling {
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimeFocusRecoveryCancellable {
        RuntimeFocusRecoveryToken(interval: interval, action: action)
    }
}
