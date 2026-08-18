import AppKit
import Foundation

@MainActor
final class RuntimeFocusRecoveryCoordinator {
    private struct ObserverRegistration {
        let center: NotificationCenter
        let token: NSObjectProtocol
    }

    private struct PendingRecovery {
        let generation: UInt64
        let target: RuntimeFocusRecoveryTarget
        let policy: RuntimeFocusRecoveryPolicy
        let readback: (RuntimeFocusRecoveryTrigger) -> RuntimeFocusRecoveryReadback
        var pollingAttempt: Int
        var pollingToken: (any RuntimeFocusRecoveryCancellable)?
        var watchdogToken: (any RuntimeFocusRecoveryCancellable)?
        var lastTrigger: RuntimeFocusRecoveryTrigger?
        var lastObservation: RuntimeFocusRecoveryObservation?
    }

    var onFailure: ((RuntimeFocusRecoveryFailure) -> Void)?

    private let scheduler: any RuntimeFocusRecoveryScheduling
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private var nextGeneration: UInt64 = 1
    private var pending: PendingRecovery?
    private var observerRegistrations: [ObserverRegistration] = []

    init(
        scheduler: (any RuntimeFocusRecoveryScheduling)? = nil,
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter =
            NSWorkspace.shared.notificationCenter
    ) {
        self.scheduler = scheduler ?? RuntimeFocusRecoveryScheduler()
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
    }

    deinit {
        pending?.pollingToken?.cancel()
        pending?.watchdogToken?.cancel()
        for registration in observerRegistrations {
            registration.center.removeObserver(registration.token)
        }
    }

    @discardableResult
    func start(
        target: RuntimeFocusRecoveryTarget,
        policy: RuntimeFocusRecoveryPolicy,
        readback: @escaping (RuntimeFocusRecoveryTrigger) -> RuntimeFocusRecoveryReadback
    ) -> UInt64? {
        cancel(reason: "superseded")
        guard policy.isEnabled else { return nil }

        let generation = nextGeneration
        nextGeneration &+= 1
        pending = PendingRecovery(
            generation: generation,
            target: target,
            policy: policy,
            readback: readback,
            pollingAttempt: 0,
            pollingToken: nil,
            watchdogToken: nil,
            lastTrigger: nil,
            lastObservation: nil
        )
        installObservers(generation: generation, target: target)
        scheduleWatchdog(generation: generation)
        scheduleNextPollingReadback(generation: generation)
        RuntimeLog.info(
            .activation,
            [
                "focus-recovery",
                "state=observing",
                "generation=\(generation)",
                "appID=\(target.appID)",
                "pid=\(target.pid)",
                "windowID=\(target.windowID)",
                "targetCG=\(target.targetCGWindowID.map(String.init) ?? "nil")",
                "pollingSeconds=\(policy.pollingIntervals)",
                "watchdogSeconds=\(policy.watchdogInterval)"
            ].joined(separator: " ")
        )
        return generation
    }

    func performInitialReadback(generation: UInt64) {
        observe(trigger: .initialReadback, generation: generation)
    }

    func completeInitialAction(generation: UInt64, reason: String) {
        finish(generation: generation, trigger: nil, reason: reason)
    }

    func cancel(reason: String) {
        guard let active = takePending() else { return }
        RuntimeLog.debug(
            .activation,
            [
                "focus-recovery",
                "state=cancelled",
                "generation=\(active.generation)",
                "pid=\(active.target.pid)",
                "windowID=\(active.target.windowID)",
                "reason=\(reason)",
                RuntimeFocusRecoveryDiagnostics.lastObservationLogFields(
                    trigger: active.lastTrigger,
                    observation: active.lastObservation
                )
            ].joined(separator: " ")
        )
    }

    private func scheduleNextPollingReadback(generation: UInt64) {
        guard var active = pending, active.generation == generation else {
            return
        }
        let nextAttempt = active.pollingAttempt + 1
        let interval = active.policy.pollingInterval(forAttempt: nextAttempt)
        active.pollingToken = scheduler.schedule(after: interval) {
            [weak self] in
            self?.firePollingReadback(
                generation: generation,
                attempt: nextAttempt
            )
        }
        pending = active
    }

    private func scheduleWatchdog(generation: UInt64) {
        guard var active = pending, active.generation == generation else {
            return
        }
        active.watchdogToken = scheduler.schedule(
            after: active.policy.watchdogInterval
        ) { [weak self] in
            self?.expireWatchdog(generation: generation)
        }
        pending = active
    }

    private func firePollingReadback(generation: UInt64, attempt: Int) {
        guard var active = pending,
              active.generation == generation,
              active.pollingAttempt + 1 == attempt
        else {
            return
        }
        active.pollingAttempt = attempt
        active.pollingToken = nil
        pending = active
        observe(trigger: .polling(attempt: attempt), generation: generation)
        guard pending?.generation == generation else { return }
        scheduleNextPollingReadback(generation: generation)
    }

    private func observe(
        trigger: RuntimeFocusRecoveryTrigger,
        generation: UInt64
    ) {
        guard var active = pending, active.generation == generation else {
            return
        }
        let result = active.readback(trigger)
        active.lastTrigger = trigger
        active.lastObservation = result.observation
        pending = active
        if result.observation.processIsTerminated {
            fail(
                active,
                reason: .targetApplicationTerminated,
                fallbackTrigger: trigger
            )
            return
        }
        guard result.completed else { return }
        finish(
            generation: generation,
            trigger: trigger,
            reason: "conditionSatisfied"
        )
    }

    private func expireWatchdog(generation: UInt64) {
        observe(trigger: .watchdogReadback, generation: generation)
        guard let active = pending, active.generation == generation else {
            return
        }
        fail(
            active,
            reason: .watchdogExpired,
            fallbackTrigger: .watchdogReadback
        )
    }

    private func targetApplicationTerminated(
        generation: UInt64,
        pid: pid_t
    ) {
        guard pending?.generation == generation,
              pending?.target.pid == pid
        else {
            return
        }
        observe(
            trigger: .targetApplicationTerminated,
            generation: generation
        )
        guard let active = pending, active.generation == generation else {
            return
        }
        fail(
            active,
            reason: .targetApplicationTerminated,
            fallbackTrigger: .targetApplicationTerminated
        )
    }

    private func fail(
        _ active: PendingRecovery,
        reason: RuntimeFocusRecoveryFailure.Reason,
        fallbackTrigger: RuntimeFocusRecoveryTrigger
    ) {
        guard pending?.generation == active.generation else { return }
        let failure = RuntimeFocusRecoveryFailure(
            reason: reason,
            generation: active.generation,
            target: active.target,
            pollingAttempt: active.pollingAttempt,
            lastTrigger: active.lastTrigger ?? fallbackTrigger,
            lastObservation: active.lastObservation ?? RuntimeFocusRecoveryObservation(
                conditionSatisfied: false,
                processIsTerminated: reason == .targetApplicationTerminated,
                targetIsVisible: false,
                focusedCGWindowID: nil,
                frontmostCGWindowID: nil,
                visibleCGWindowIDs: []
            )
        )
        _ = takePending()
        RuntimeLog.warning(
            .activation,
            [
                "focus-recovery",
                "state=\(reason.rawValue)",
                "unmetCondition=exactTargetWindowFocusedOrFrontmost",
                "generation=\(failure.generation)",
                "appID=\(failure.target.appID)",
                "pid=\(failure.target.pid)",
                "windowID=\(failure.target.windowID)",
                "targetCG=\(failure.target.targetCGWindowID.map(String.init) ?? "nil")",
                "pollingAttempt=\(failure.pollingAttempt)",
                "lastTrigger=\(failure.lastTrigger.logValue)",
                RuntimeFocusRecoveryDiagnostics.observationLogFields(
                    failure.lastObservation
                )
            ].joined(separator: " ")
        )
        onFailure?(failure)
    }

    private func finish(
        generation: UInt64,
        trigger: RuntimeFocusRecoveryTrigger?,
        reason: String
    ) {
        guard let active = pending, active.generation == generation else {
            return
        }
        _ = takePending()
        RuntimeLog.info(
            .activation,
            [
                "focus-recovery",
                "state=completed",
                "generation=\(generation)",
                "pid=\(active.target.pid)",
                "windowID=\(active.target.windowID)",
                "trigger=\(trigger?.logValue ?? "initialAction")",
                "reason=\(reason)",
                RuntimeFocusRecoveryDiagnostics.lastObservationLogFields(
                    trigger: active.lastTrigger,
                    observation: active.lastObservation
                )
            ].joined(separator: " ")
        )
    }

    private func takePending() -> PendingRecovery? {
        guard let active = pending else { return nil }
        pending = nil
        active.pollingToken?.cancel()
        active.watchdogToken?.cancel()
        removeObservers()
        return active
    }

    private func installObservers(
        generation: UInt64,
        target: RuntimeFocusRecoveryTarget
    ) {
        addObserver(
            center: workspaceNotificationCenter,
            name: NSWorkspace.didActivateApplicationNotification
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[
                    NSWorkspace.applicationUserInfoKey
                ] as? NSRunningApplication,
                app.processIdentifier == target.pid
            else {
                return
            }
            self?.observe(
                trigger: .targetApplicationActivated,
                generation: generation
            )
        }
        addObserver(
            center: workspaceNotificationCenter,
            name: NSWorkspace.activeSpaceDidChangeNotification
        ) { [weak self] _ in
            self?.observe(
                trigger: .activeSpaceChanged,
                generation: generation
            )
        }
        addObserver(
            center: workspaceNotificationCenter,
            name: NSWorkspace.didTerminateApplicationNotification
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[
                    NSWorkspace.applicationUserInfoKey
                ] as? NSRunningApplication
            else {
                return
            }
            self?.targetApplicationTerminated(
                generation: generation,
                pid: app.processIdentifier
            )
        }
        addObserver(
            center: notificationCenter,
            name: .runtimeAppSwitcherProjectionDidUpdate
        ) { [weak self] _ in
            self?.observe(
                trigger: .appSwitcherProjectionUpdated,
                generation: generation
            )
        }
        addObserver(
            center: notificationCenter,
            name: .runtimeCurrentAppWindowProjectionDidUpdate
        ) { [weak self] notification in
            let appID = notification.userInfo?[
                RuntimeProjectionNotificationUserInfoKey.appID
            ] as? String
            guard appID == target.appID else { return }
            self?.observe(
                trigger: .currentAppWindowProjectionUpdated,
                generation: generation
            )
        }
    }

    private func addObserver(
        center: NotificationCenter,
        name: Notification.Name,
        handler: @escaping @MainActor (Notification) -> Void
    ) {
        let token = center.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                handler(notification)
            }
        }
        observerRegistrations.append(
            ObserverRegistration(center: center, token: token)
        )
    }

    private func removeObservers() {
        for registration in observerRegistrations {
            registration.center.removeObserver(registration.token)
        }
        observerRegistrations.removeAll()
    }

}
