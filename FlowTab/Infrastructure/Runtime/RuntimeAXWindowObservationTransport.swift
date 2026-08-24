import ApplicationServices
import Foundation

protocol RuntimeAXWindowObservationWorkScheduling: AnyObject {
    func schedule(_ work: @escaping @Sendable () -> Void)
}

final class RuntimeAXWindowObservationWorkScheduler:
    RuntimeAXWindowObservationWorkScheduling,
    @unchecked Sendable
{
    private let queue: OperationQueue

    init(maxConcurrentOperationCount: Int = 4) {
        precondition(
            maxConcurrentOperationCount > 0,
            "AX observation worker concurrency must be positive."
        )
        queue = OperationQueue()
        queue.name = "FlowTab.RuntimeAXWindowObservation"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = maxConcurrentOperationCount
    }

    func schedule(_ work: @escaping @Sendable () -> Void) {
        queue.addOperation(work)
    }
}

struct RuntimeAXWindowObservationRegistrationEvidence {
    let registeredNotifications: [CFString]
    let lastResult: AXError
}

enum RuntimeAXWindowObservationRegistrationPolicy {
    static func register(
        element: AXUIElement,
        notifications: [CFString],
        applyMessagingTimeout: (AXUIElement) -> Void = {
            RuntimeAXMessagingTimeoutPolicy.apply(to: $0)
        },
        addNotification: (AXUIElement, CFString) -> AXError
    ) -> RuntimeAXWindowObservationRegistrationEvidence {
        applyMessagingTimeout(element)
        var registeredNotifications: [CFString] = []
        var lastResult: AXError = .notificationUnsupported

        for notification in notifications {
            let result = addNotification(element, notification)
            lastResult = result
            if result == .success || result == .notificationAlreadyRegistered {
                registeredNotifications.append(notification)
            }
            if isTerminalRemoteFailure(result) {
                break
            }
        }

        return RuntimeAXWindowObservationRegistrationEvidence(
            registeredNotifications: registeredNotifications,
            lastResult: lastResult
        )
    }

    static func isTerminalRemoteFailure(_ error: AXError) -> Bool {
        switch error {
        case .failure, .invalidUIElement, .invalidUIElementObserver,
             .cannotComplete, .apiDisabled:
            true
        default:
            false
        }
    }
}
