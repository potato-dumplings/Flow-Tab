import Foundation

let runtimeSearchFreshnessBarrierMaxReadyRepairs = 4
let runtimeAppLaunchWindowConvergenceDelay: TimeInterval = 0.8

final class RuntimeAppLaunchConvergenceScheduler {
    let delay: TimeInterval

    private var nextGeneration: UInt64 = 1
    private var generationByPID: [pid_t: UInt64] = [:]

    init(delay: TimeInterval = runtimeAppLaunchWindowConvergenceDelay) {
        self.delay = delay
    }

    func schedule(
        pid: pid_t,
        on queue: DispatchQueue,
        action: @escaping @Sendable () -> Void
    ) {
        let generation = nextGeneration
        nextGeneration &+= 1
        generationByPID[pid] = generation
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, generationByPID[pid] == generation else { return }
            generationByPID.removeValue(forKey: pid)
            action()
        }
    }

    func cancel(pid: pid_t) {
        generationByPID.removeValue(forKey: pid)
    }
}

enum RuntimeProjectionMaintenanceReason: String, Sendable {
    case switcherSessionStarted
    case appLifecycleRefresh
    case homeProjectionMissing
    case searchFreshnessBarrier
}
