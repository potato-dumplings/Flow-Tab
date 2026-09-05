#if FLOWTAB_TESTING
import Foundation

enum RuntimeFocusedRepairDiagnosticStage: String, Sendable {
    case onScreenCGRead = "on_screen_cg_read"
    case allCGRead = "all_cg_read"
    case axRead = "ax_read"
    case mappingSpaceFilter = "mapping_space_filter"
}

typealias RuntimeFocusedRepairCPUSnapshot = RuntimeProcessCPUSnapshot

struct RuntimeFocusedRepairDiagnosticSpan: Sendable {
    let processIdentifier: pid_t
    let stage: RuntimeFocusedRepairDiagnosticStage
    let startedAtNanoseconds: UInt64
    let completedAtNanoseconds: UInt64
    let startedCPU: RuntimeFocusedRepairCPUSnapshot
    let completedCPU: RuntimeFocusedRepairCPUSnapshot
    let workUnits: Int
}

struct RuntimeFocusedRepairDiagnosticToken: Sendable {
    let rawValue: UInt64
}

final class RuntimeFocusedRepairDiagnosticCollector: @unchecked Sendable {
    static let shared = RuntimeFocusedRepairDiagnosticCollector()

    private struct ActiveSpan {
        let processIdentifier: pid_t
        let stage: RuntimeFocusedRepairDiagnosticStage
        let startedAtNanoseconds: UInt64
        let startedCPU: RuntimeFocusedRepairCPUSnapshot
    }

    private let lock = NSLock()
    private var enabled = false
    private var generation: UInt64 = 0
    private var nextToken: UInt64 = 0
    private var active: [UInt64: ActiveSpan] = [:]
    private var completedByPID:
        [pid_t: [RuntimeFocusedRepairDiagnosticSpan]] = [:]

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        if self.enabled != enabled || !enabled {
            generation &+= 1
            active.removeAll()
            completedByPID.removeAll()
        }
        self.enabled = enabled
        lock.unlock()
    }

    var scopeGeneration: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    func reset() {
        lock.lock()
        generation &+= 1
        active.removeAll()
        completedByPID.removeAll()
        lock.unlock()
    }

    func begin(
        _ stage: RuntimeFocusedRepairDiagnosticStage,
        processIdentifier: pid_t,
        scopeGeneration: UInt64? = nil
    ) -> RuntimeFocusedRepairDiagnosticToken? {
        lock.lock()
        guard enabled, scopeGeneration == nil || scopeGeneration == generation else {
            lock.unlock()
            return nil
        }
        nextToken &+= 1
        let token = nextToken
        active[token] = ActiveSpan(
            processIdentifier: processIdentifier,
            stage: stage,
            startedAtNanoseconds:
                DispatchTime.now().uptimeNanoseconds,
            startedCPU: RuntimeProcessDiagnosticClock.cpuSnapshot()
        )
        lock.unlock()
        return RuntimeFocusedRepairDiagnosticToken(rawValue: token)
    }

    func end(
        _ token: RuntimeFocusedRepairDiagnosticToken?,
        workUnits: Int
    ) {
        guard let token else { return }
        let completedAt = DispatchTime.now().uptimeNanoseconds
        let completedCPU = RuntimeProcessDiagnosticClock.cpuSnapshot()
        lock.lock()
        guard let started = active.removeValue(
            forKey: token.rawValue
        ) else {
            lock.unlock()
            return
        }
        completedByPID[started.processIdentifier, default: []]
            .append(
                RuntimeFocusedRepairDiagnosticSpan(
                    processIdentifier: started.processIdentifier,
                    stage: started.stage,
                    startedAtNanoseconds: started.startedAtNanoseconds,
                    completedAtNanoseconds: completedAt,
                    startedCPU: started.startedCPU,
                    completedCPU: completedCPU,
                    workUnits: max(0, workUnits)
                )
            )
        lock.unlock()
    }

    func drain(
        processIdentifier: pid_t
    ) -> [RuntimeFocusedRepairDiagnosticSpan] {
        lock.lock()
        let spans = completedByPID.removeValue(
            forKey: processIdentifier
        ) ?? []
        lock.unlock()
        return spans.sorted {
            $0.startedAtNanoseconds < $1.startedAtNanoseconds
        }
    }
}
#endif
