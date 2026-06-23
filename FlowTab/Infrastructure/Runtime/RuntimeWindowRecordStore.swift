import AppKit
import Foundation

final class RuntimeWindowRecordStore {
    var mappingStatesByPID: [pid_t: RuntimeWindowMappingState]

    init(mappingStatesByPID: [pid_t: RuntimeWindowMappingState] = [:]) {
        self.mappingStatesByPID = mappingStatesByPID
    }

    func state(for pid: pid_t) -> RuntimeWindowMappingState? {
        mappingStatesByPID[pid]
    }

    func setState(_ state: RuntimeWindowMappingState, for pid: pid_t) {
        mappingStatesByPID[pid] = state
    }

    func removeState(for pid: pid_t) {
        mappingStatesByPID.removeValue(forKey: pid)
    }

    func cleanup(keepingRunningApps runningApps: [NSRunningApplication]) {
        let runningPIDs = Set(runningApps.map(\.processIdentifier))
        mappingStatesByPID = mappingStatesByPID.filter { runningPIDs.contains($0.key) }
    }
}
