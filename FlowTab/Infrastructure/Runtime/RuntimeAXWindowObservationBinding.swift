import Foundation

struct RuntimeAXWindowObservationIdentity: Equatable, Hashable, Sendable {
    let appID: String
    let pid: pid_t
}

struct RuntimeAXWindowObservationBinding: Equatable, Hashable, Sendable {
    let appID: String
    let pid: pid_t
    let expectedWindowCount: Int

    init(
        appID: String,
        pid: pid_t,
        expectedWindowCount: Int
    ) {
        self.appID = appID
        self.pid = pid
        self.expectedWindowCount = max(0, expectedWindowCount)
    }

    var identity: RuntimeAXWindowObservationIdentity {
        RuntimeAXWindowObservationIdentity(appID: appID, pid: pid)
    }
}

struct RuntimeAXWindowObservationBindingCollection: Equatable, Sendable {
    let bindings: [RuntimeAXWindowObservationBinding]

    init(
        _ bindings: [RuntimeAXWindowObservationBinding],
        currentPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        var normalizedByIdentity:
            [RuntimeAXWindowObservationIdentity: RuntimeAXWindowObservationBinding] = [:]
        for binding in bindings {
            guard binding.pid > 0, binding.pid != currentPID else { continue }
            let normalized = RuntimeAXWindowObservationBinding(
                appID: binding.appID,
                pid: binding.pid,
                expectedWindowCount: binding.expectedWindowCount
            )
            let identity = normalized.identity
            if let existing = normalizedByIdentity[identity],
               existing.expectedWindowCount >= normalized.expectedWindowCount
            {
                continue
            }
            normalizedByIdentity[identity] = normalized
        }
        self.bindings = normalizedByIdentity.values.sorted(by: Self.sort)
    }

    var byPID: [pid_t: RuntimeAXWindowObservationBinding] {
        bindings.reduce(into: [:]) { bindingsByPID, binding in
            bindingsByPID[binding.pid] = binding
        }
    }

    func binding(appID: String, pid: pid_t)
        -> RuntimeAXWindowObservationBinding?
    {
        bindings.first { $0.appID == appID && $0.pid == pid }
    }

    private static func sort(
        _ lhs: RuntimeAXWindowObservationBinding,
        _ rhs: RuntimeAXWindowObservationBinding
    ) -> Bool {
        if lhs.pid != rhs.pid {
            return lhs.pid < rhs.pid
        }
        return lhs.appID < rhs.appID
    }
}

struct RuntimeAXWindowObservationBindingDelta: Equatable {
    let addedPIDs: Set<pid_t>
    let removedPIDs: Set<pid_t>
    let updatedPIDs: Set<pid_t>

    static func resolve(
        current: [pid_t: RuntimeAXWindowObservationBinding],
        desired: [pid_t: RuntimeAXWindowObservationBinding]
    ) -> RuntimeAXWindowObservationBindingDelta {
        var addedPIDs: Set<pid_t> = []
        var removedPIDs: Set<pid_t> = []
        var updatedPIDs: Set<pid_t> = []

        for (pid, desiredBinding) in desired {
            guard let currentBinding = current[pid] else {
                addedPIDs.insert(pid)
                continue
            }
            if currentBinding.appID != desiredBinding.appID {
                removedPIDs.insert(pid)
                addedPIDs.insert(pid)
            } else if currentBinding.expectedWindowCount
                        != desiredBinding.expectedWindowCount
            {
                updatedPIDs.insert(pid)
            }
        }
        for pid in current.keys where desired[pid] == nil {
            removedPIDs.insert(pid)
        }
        return RuntimeAXWindowObservationBindingDelta(
            addedPIDs: addedPIDs,
            removedPIDs: removedPIDs,
            updatedPIDs: updatedPIDs
        )
    }
}
