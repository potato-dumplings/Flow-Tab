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

struct RuntimeAXWindowObserverInstallRequest: @unchecked Sendable {
    let pid: pid_t
    let expectedWindowCount: Int
    let notifications: [CFString]
    let callback: AXObserverCallback
    let context: RuntimeAXWindowChangeMonitor.ObserverContext
}

struct RuntimeAXWindowObserverInstallResult: @unchecked Sendable {
    let observer: AXObserver?
    let context: RuntimeAXWindowChangeMonitor.ObserverContext
    let registeredNotifications: [CFString]
    let lastResult: AXError
    let destroyedWindowElements: [AXUIElement]
    let initialReadback: RuntimeAXWindowInitialReadbackEvidence?

    var isInstalled: Bool {
        observer != nil && !registeredNotifications.isEmpty
    }
}

protocol RuntimeAXWindowObserverInstalling: AnyObject, Sendable {
    func install(
        _ request: RuntimeAXWindowObserverInstallRequest
    ) -> RuntimeAXWindowObserverInstallResult
}

final class RuntimeAXWindowObserverInstaller:
    RuntimeAXWindowObserverInstalling,
    @unchecked Sendable
{
    func install(
        _ request: RuntimeAXWindowObserverInstallRequest
    ) -> RuntimeAXWindowObserverInstallResult {
        var observerRef: AXObserver?
        let createResult = AXObserverCreate(
            request.pid,
            request.callback,
            &observerRef
        )
        guard createResult == .success, let observerRef else {
            return RuntimeAXWindowObserverInstallResult(
                observer: nil,
                context: request.context,
                registeredNotifications: [],
                lastResult: createResult == .success ? .failure : createResult,
                destroyedWindowElements: [],
                initialReadback: nil
            )
        }

        let contextPointer = UnsafeMutableRawPointer(
            Unmanaged.passUnretained(request.context).toOpaque()
        )
        let appElement = AXUIElementCreateApplication(request.pid)
        let registration = RuntimeAXWindowObservationRegistrationPolicy.register(
            element: appElement,
            notifications: request.notifications
        ) { element, notification in
            AXObserverAddNotification(
                observerRef,
                element,
                notification,
                contextPointer
            )
        }
        guard !registration.registeredNotifications.isEmpty else {
            return RuntimeAXWindowObserverInstallResult(
                observer: observerRef,
                context: request.context,
                registeredNotifications: [],
                lastResult: registration.lastResult,
                destroyedWindowElements: [],
                initialReadback: nil
            )
        }

        let knownWindowElements = AXLiveWindowRegistry.shared.windows(
            forPID: request.pid
        )
        let destroyedWindowElements =
            RuntimeAXWindowChangeMonitor.synchronizeDestroyedWindowRegistrations(
                observer: observerRef,
                context: request.context,
                currentWindows: Array(knownWindowElements.values),
                observedWindows: []
            )
        return RuntimeAXWindowObserverInstallResult(
            observer: observerRef,
            context: request.context,
            registeredNotifications: registration.registeredNotifications,
            lastResult: registration.lastResult,
            destroyedWindowElements: destroyedWindowElements,
            initialReadback: RuntimeAXWindowChangeMonitor.initialReadbackEvidence(
                pid: request.pid,
                expectedWindowCount: request.expectedWindowCount,
                knownWindowElements: Array(knownWindowElements.values)
            )
        )
    }
}

extension RuntimeAXWindowChangeMonitor {
    nonisolated static func currentDestroyedWindowElements(
        pid: pid_t
    ) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        RuntimeAXMessagingTimeoutPolicy.apply(to: appElement)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &rawWindows
        ) == .success,
        let windows = rawWindows as? [AXUIElement]
        else {
            return []
        }

        RuntimeAXMessagingTimeoutPolicy.apply(to: windows)
        return windows
    }
}

struct RuntimeAXWindowObservationRetryPolicy: Equatable {
    let initialInterval: TimeInterval
    let multiplier: Double
    let maximumInterval: TimeInterval

    static let standard = RuntimeAXWindowObservationRetryPolicy(
        initialInterval: 0.25,
        multiplier: 2,
        maximumInterval: 4
    )

    init(
        initialInterval: TimeInterval,
        multiplier: Double,
        maximumInterval: TimeInterval
    ) {
        precondition(initialInterval > 0)
        precondition(multiplier >= 1)
        precondition(maximumInterval >= initialInterval)
        self.initialInterval = initialInterval
        self.multiplier = multiplier
        self.maximumInterval = maximumInterval
    }

    func interval(forAttempt attempt: Int) -> TimeInterval {
        precondition(attempt > 0)
        return min(
            maximumInterval,
            initialInterval * pow(multiplier, Double(attempt - 1))
        )
    }

    func shouldRetry(_ error: AXError) -> Bool {
        switch error {
        case .failure, .cannotComplete, .invalidUIElement,
             .invalidUIElementObserver:
            true
        default:
            false
        }
    }
}

@MainActor
protocol RuntimeAXWindowObservationRetryCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol RuntimeAXWindowObservationRetryScheduling: AnyObject {
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimeAXWindowObservationRetryCancellable
}

@MainActor
private final class RuntimeAXWindowObservationRetryToken:
    RuntimeAXWindowObservationRetryCancellable
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

    deinit {
        task?.cancel()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

@MainActor
final class RuntimeAXWindowObservationRetryScheduler:
    RuntimeAXWindowObservationRetryScheduling
{
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimeAXWindowObservationRetryCancellable {
        RuntimeAXWindowObservationRetryToken(
            interval: interval,
            action: action
        )
    }
}

struct RuntimeAXWindowObservationScheduledRetry: Equatable {
    let appID: String
    let pid: pid_t
    let installGeneration: UInt64
    let attempt: Int
    let interval: TimeInterval
    let error: AXError
}

@MainActor
final class RuntimeAXWindowObservationRetryCoordinator {
    private struct PendingRetry {
        let evidence: RuntimeAXWindowObservationScheduledRetry
        var token: (any RuntimeAXWindowObservationRetryCancellable)?
    }

    private let policy: RuntimeAXWindowObservationRetryPolicy
    private let scheduler: any RuntimeAXWindowObservationRetryScheduling
    private var pendingByPID: [pid_t: PendingRetry] = [:]

    init(
        policy: RuntimeAXWindowObservationRetryPolicy,
        scheduler: (any RuntimeAXWindowObservationRetryScheduling)? = nil
    ) {
        self.policy = policy
        self.scheduler = scheduler ?? RuntimeAXWindowObservationRetryScheduler()
    }

    func hasPending(appID: String, pid: pid_t) -> Bool {
        pendingByPID[pid]?.evidence.appID == appID
    }

    @discardableResult
    func schedule(
        appID: String,
        pid: pid_t,
        installGeneration: UInt64,
        error: AXError,
        action: @escaping @MainActor @Sendable (Int) -> Void
    ) -> RuntimeAXWindowObservationScheduledRetry? {
        guard policy.shouldRetry(error) else { return nil }

        if let pending = pendingByPID[pid], pending.token != nil,
           pending.evidence.appID == appID {
            return pending.evidence
        }
        if pendingByPID[pid]?.evidence.appID != appID {
            cancel(pid: pid, reason: "bindingChanged")
        }

        let attempt = (pendingByPID[pid]?.evidence.attempt ?? 0) + 1
        let interval = policy.interval(forAttempt: attempt)
        let evidence = RuntimeAXWindowObservationScheduledRetry(
            appID: appID,
            pid: pid,
            installGeneration: installGeneration,
            attempt: attempt,
            interval: interval,
            error: error
        )
        let token = scheduler.schedule(after: interval) { [weak self] in
            self?.fire(evidence: evidence, action: action)
        }
        pendingByPID[pid] = PendingRetry(
            evidence: evidence,
            token: token
        )
        RuntimeLog.debug(
            .axObserver,
            "runtimeAXObserverRetry result=scheduled appID=\(appID) pid=\(pid) installGeneration=\(installGeneration) attempt=\(attempt) axError=\(error.rawValue) delaySeconds=\(interval)"
        )
        return evidence
    }

    @discardableResult
    func complete(pid: pid_t, appID: String) -> Int? {
        guard let pending = pendingByPID[pid],
              pending.evidence.appID == appID
        else { return nil }
        pendingByPID.removeValue(forKey: pid)
        pending.token?.cancel()
        RuntimeLog.debug(
            .axObserver,
            "runtimeAXObserverRetry result=succeeded appID=\(appID) pid=\(pid) installGeneration=\(pending.evidence.installGeneration) attempt=\(pending.evidence.attempt)"
        )
        return pending.evidence.attempt
    }

    func retainBindings(_ expectedAppIDsByPID: [pid_t: String]) {
        for pid in Array(pendingByPID.keys) {
            guard let pending = pendingByPID[pid],
                  expectedAppIDsByPID[pid] != pending.evidence.appID
            else { continue }
            cancel(pid: pid, reason: "bindingChanged")
        }
    }

    func cancel(pid: pid_t, reason: String) {
        guard let pending = pendingByPID.removeValue(forKey: pid) else { return }
        pending.token?.cancel()
        RuntimeLog.debug(
            .axObserver,
            "runtimeAXObserverRetry result=cancelled appID=\(pending.evidence.appID) pid=\(pid) installGeneration=\(pending.evidence.installGeneration) attempt=\(pending.evidence.attempt) reason=\(reason)"
        )
    }

    func stop() {
        for pid in Array(pendingByPID.keys) {
            cancel(pid: pid, reason: "monitorStopped")
        }
    }

    private func fire(
        evidence: RuntimeAXWindowObservationScheduledRetry,
        action: @escaping @MainActor @Sendable (Int) -> Void
    ) {
        guard var pending = pendingByPID[evidence.pid],
              pending.evidence == evidence
        else { return }
        pending.token = nil
        pendingByPID[evidence.pid] = pending
        action(evidence.attempt)
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
