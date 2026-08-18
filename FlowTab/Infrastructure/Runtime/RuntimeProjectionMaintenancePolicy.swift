import ApplicationServices
import Foundation

let runtimeSearchFreshnessBarrierMaxReadyRepairs = 4
let runtimeAppLaunchObserverInstallRetryIntervalNanoseconds: UInt64 = 250_000_000

@MainActor
protocol RuntimeAppLaunchObservationRetryCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol RuntimeAppLaunchObservationRetryScheduling: AnyObject {
    func schedule(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimeAppLaunchObservationRetryCancellable
}

@MainActor
private final class RuntimeAppLaunchObservationRetryToken:
    RuntimeAppLaunchObservationRetryCancellable
{
    private var task: Task<Void, Never>?

    init(
        delayNanoseconds: UInt64,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
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
final class RuntimeAppLaunchObservationRetryScheduler:
    RuntimeAppLaunchObservationRetryScheduling
{
    private let intervalNanoseconds: UInt64

    init(
        intervalNanoseconds: UInt64 =
            runtimeAppLaunchObserverInstallRetryIntervalNanoseconds
    ) {
        self.intervalNanoseconds = intervalNanoseconds
    }

    func schedule(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimeAppLaunchObservationRetryCancellable {
        RuntimeAppLaunchObservationRetryToken(
            delayNanoseconds: intervalNanoseconds,
            action: action
        )
    }
}

@MainActor
protocol RuntimeAppLaunchWindowEvidenceCoordinating: AnyObject {
    func prepareObservation(appID: String, pid: pid_t)
    func cancelObservation(appID: String, pid: pid_t)
    func stop()
}

@MainActor
final class RuntimeAppLaunchWindowEvidenceCoordinator:
    RuntimeAppLaunchWindowEvidenceCoordinating
{
    private struct PendingObservation {
        let appID: String
        let generation: UInt64
        var lastInstallError: AXError
        var retry: (any RuntimeAppLaunchObservationRetryCancellable)?
    }

    private let monitor: any RuntimeAXWindowChangeMonitoring
    private let retryScheduler: any RuntimeAppLaunchObservationRetryScheduling
    private let currentPID: pid_t
    private let onAppWindowChanged: (String, pid_t) -> Void
    private var nextGeneration: UInt64 = 1
    private var activeAppIDsByPID: [pid_t: String] = [:]
    private var pendingObservationsByPID: [pid_t: PendingObservation] = [:]

    init(
        monitor: any RuntimeAXWindowChangeMonitoring,
        retryScheduler: any RuntimeAppLaunchObservationRetryScheduling,
        currentPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        onAppWindowChanged: @escaping (String, pid_t) -> Void,
        onAXWindowDestroyed: @escaping (String, pid_t, String) -> Void
    ) {
        self.monitor = monitor
        self.retryScheduler = retryScheduler
        self.currentPID = currentPID
        self.onAppWindowChanged = onAppWindowChanged
        monitor.onAppWindowChanged = { evidence in
            onAppWindowChanged(evidence.appID, evidence.pid)
        }
        monitor.onAXWindowDestroyed = onAXWindowDestroyed
    }

    convenience init(
        currentPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        onAppWindowChanged: @escaping (String, pid_t) -> Void,
        onAXWindowDestroyed: @escaping (String, pid_t, String) -> Void
    ) {
        self.init(
            monitor: RuntimeAXWindowChangeMonitor(
                deliveryPolicy: .standardCoalesced
            ),
            retryScheduler: RuntimeAppLaunchObservationRetryScheduler(),
            currentPID: currentPID,
            onAppWindowChanged: onAppWindowChanged,
            onAXWindowDestroyed: onAXWindowDestroyed
        )
    }

    func prepareObservation(appID: String, pid: pid_t) {
        guard pid > 0, pid != currentPID else { return }
        invalidatePendingObservation(pid: pid)

        let generation = nextGeneration
        nextGeneration &+= 1
        activeAppIDsByPID[pid] = appID

        switch monitor.observe(appID: appID, pid: pid) {
        case .installed:
            RuntimeLog.debug(
                .projection,
                "appLaunchWindowEvidence observerInstalled appID=\(appID) pid=\(pid) initialReadback=appLaunchRepair"
            )
        case .unavailable(let error):
            pendingObservationsByPID[pid] = PendingObservation(
                appID: appID,
                generation: generation,
                lastInstallError: error,
                retry: nil
            )
            scheduleRetry(pid: pid, generation: generation)
        }
    }

    func cancelObservation(appID: String, pid: pid_t) {
        guard activeAppIDsByPID[pid] == appID else {
            RuntimeLog.debug(
                .projection,
                "appLaunchWindowEvidence ignoredStaleTermination appID=\(appID) pid=\(pid) activeAppID=\(activeAppIDsByPID[pid] ?? "none")"
            )
            return
        }
        activeAppIDsByPID.removeValue(forKey: pid)
        if let pending = pendingObservationsByPID.removeValue(forKey: pid) {
            pending.retry?.cancel()
            RuntimeLog.debug(
                .projection,
                "appLaunchWindowEvidence cancelled appID=\(pending.appID) pid=\(pid) lastAXError=\(pending.lastInstallError.rawValue)"
            )
        }
        monitor.stopObserving(pid: pid)
    }

    func stop() {
        for pending in pendingObservationsByPID.values {
            pending.retry?.cancel()
        }
        pendingObservationsByPID.removeAll()
        activeAppIDsByPID.removeAll()
        monitor.stop()
    }

    private func scheduleRetry(pid: pid_t, generation: UInt64) {
        guard var pending = pendingObservationsByPID[pid],
              pending.generation == generation
        else { return }

        pending.retry = retryScheduler.schedule { [weak self] in
            self?.retryObservation(pid: pid, generation: generation)
        }
        pendingObservationsByPID[pid] = pending
    }

    private func retryObservation(pid: pid_t, generation: UInt64) {
        guard var pending = pendingObservationsByPID[pid],
              pending.generation == generation,
              activeAppIDsByPID[pid] == pending.appID
        else { return }
        pending.retry = nil
        pendingObservationsByPID[pid] = pending

        switch monitor.observe(appID: pending.appID, pid: pid) {
        case .installed:
            pendingObservationsByPID.removeValue(forKey: pid)
            RuntimeLog.debug(
                .projection,
                "appLaunchWindowEvidence observerInstalled appID=\(pending.appID) pid=\(pid) initialReadback=appWindowsChanged"
            )
            onAppWindowChanged(pending.appID, pid)
        case .unavailable(let error):
            pending.lastInstallError = error
            pendingObservationsByPID[pid] = pending
            scheduleRetry(pid: pid, generation: generation)
        }
    }

    private func invalidatePendingObservation(pid: pid_t) {
        let pending = pendingObservationsByPID.removeValue(forKey: pid)
        pending?.retry?.cancel()
    }
}

enum RuntimeProjectionMaintenanceReason: String, Sendable {
    case switcherSessionStarted
    case appLifecycleRefresh
    case homeProjectionMissing
    case searchFreshnessBarrier
}
