import Foundation

enum RuntimeProjectionReconciliationExecutionOutcome {
    case completed
    case completedWithFullRepairProjection(RuntimeFullRepairProjectionPayload)
    case completedWithRepairedCurrentAppWindowPayloads([RuntimeCurrentAppWindowPayload])
    case transientEmptyCurrentAppWindowPayload

    var repairedCurrentAppWindowPayloads: [RuntimeCurrentAppWindowPayload] {
        switch self {
        case .completed, .completedWithFullRepairProjection:
            []
        case let .completedWithRepairedCurrentAppWindowPayloads(payloads):
            payloads
        case .transientEmptyCurrentAppWindowPayload:
            []
        }
    }
}

struct RuntimeProjectionReconciliationDrainResult {
    var startedRequests: [RuntimeReconciliationRequest] = []
    var completedCount = 0
    var deferredCount = 0
    var fullRepairProjectionPayloads: [RuntimeFullRepairProjectionPayload] = []
    var repairedCurrentAppWindowPayloads: [RuntimeCurrentAppWindowPayload] = []
}

struct RuntimeFullRepairProjectionCommitSummary {
    var coldStartCommittedCount = 0
    var degradedCommittedCount = 0
}

typealias RuntimeProjectionReconciliationExecutor = (
    RuntimeReconciliationRequest,
    RuntimeProjectionRepairProviding
) -> RuntimeProjectionReconciliationExecutionOutcome

func runtimeProjectionDefaultReconciliationExecutor(
    request: RuntimeReconciliationRequest,
    repairProvider: RuntimeProjectionRepairProviding
) -> RuntimeProjectionReconciliationExecutionOutcome {
    switch request.target {
    case let .app(pid):
        let result = repairProvider.reconcileAppWindows(
            processIdentifier: pid,
            affectedCGWindowIDs: request.affectedCGWindowIDs
        )
        if result.isTransientEmptyCurrentAppWindowPayload {
            return .transientEmptyCurrentAppWindowPayload
        }
        if let payload = result.currentAppWindowPayload {
            return .completedWithRepairedCurrentAppWindowPayloads([payload])
        }
        return .completed
    case .fullRepair:
        return .completedWithFullRepairProjection(repairProvider.fullRepairProjectionPayload())
    case .spaceTopology:
        let results = repairProvider.reconcileSpaceTopology(
            affectedCGWindowIDs: request.affectedCGWindowIDs
        )
        var repairedCurrentAppWindowPayloads: [RuntimeCurrentAppWindowPayload] = []
        for result in results {
            if result.isTransientEmptyCurrentAppWindowPayload {
                return .transientEmptyCurrentAppWindowPayload
            }
            if let payload = result.currentAppWindowPayload {
                repairedCurrentAppWindowPayloads.append(payload)
            }
        }
        if !repairedCurrentAppWindowPayloads.isEmpty {
            return .completedWithRepairedCurrentAppWindowPayloads(
                repairedCurrentAppWindowPayloads
            )
        }
        return .completed
    }
}
