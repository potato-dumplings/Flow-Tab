import CoreGraphics
import Foundation

enum RuntimeProjectionReconciliationExecutionOutcome {
    case completed
    case completedWithFullRepairEvidence(RuntimeFullRepairEvidence)
    case completedWithCurrentAppRepairEvidence([RuntimeCurrentAppRepairEvidence])
    case transientEmptyCurrentAppWindowPayload
    case waitingForEvidence(
        Set<RuntimeReconciliationEvidenceRequirement>
    )

    var currentAppRepairEvidence: [RuntimeCurrentAppRepairEvidence] {
        switch self {
        case .completed, .completedWithFullRepairEvidence:
            []
        case let .completedWithCurrentAppRepairEvidence(evidence):
            evidence
        case .transientEmptyCurrentAppWindowPayload,
             .waitingForEvidence:
            []
        }
    }

    var evidenceRequirements:
        Set<RuntimeReconciliationEvidenceRequirement>
    {
        switch self {
        case .completed,
             .completedWithFullRepairEvidence,
             .completedWithCurrentAppRepairEvidence:
            []
        case .transientEmptyCurrentAppWindowPayload:
            [.currentAppWindowPayloadNonEmpty]
        case .waitingForEvidence(let requirements):
            requirements
        }
    }
}

struct RuntimeProjectionReconciliationDrainResult {
    var startedRequests: [RuntimeReconciliationRequest] = []
    var completedCount = 0
    var deferredRequests: [RuntimeReconciliationRequest] = []
    var fullRepairEvidence: [RuntimeFullRepairEvidence] = []
    var currentAppRepairEvidence: [RuntimeCurrentAppRepairEvidence] = []
    var completedAffectedCGWindowIDs: Set<CGWindowID> = []

    var deferredCount: Int {
        deferredRequests.count
    }

    mutating func append(_ result: RuntimeProjectionReconciliationDrainResult) {
        startedRequests.append(contentsOf: result.startedRequests)
        completedCount += result.completedCount
        deferredRequests.append(contentsOf: result.deferredRequests)
        fullRepairEvidence.append(contentsOf: result.fullRepairEvidence)
        currentAppRepairEvidence.append(contentsOf: result.currentAppRepairEvidence)
        completedAffectedCGWindowIDs.formUnion(result.completedAffectedCGWindowIDs)
    }
}

typealias RuntimeProjectionReconciliationExecutor = (
    RuntimeReconciliationRequest,
    RuntimeProjectionRepairProviding
) -> RuntimeProjectionReconciliationExecutionOutcome

struct RuntimeProjectionReconciliationDrainer {
    let repairProvider: RuntimeProjectionRepairProviding
    let reconciliationExecutor: RuntimeProjectionReconciliationExecutor

    func drainReadyRequests(
        now: TimeInterval,
        maxRequests: Int? = nil,
        includeFullRepair: Bool = true
    ) -> RuntimeProjectionReconciliationDrainResult {
        let readyRequests = repairProvider.readyReconciliationRequests(
            includeFullRepair: includeFullRepair
        )
        let requests = maxRequests.map { Array(readyRequests.prefix($0)) } ?? readyRequests
        var result = RuntimeProjectionReconciliationDrainResult()
        result.startedRequests.reserveCapacity(requests.count)

        for request in requests {
            guard let startedRequest = repairProvider.startReconciliationRequest(id: request.id) else {
                continue
            }
            result.startedRequests.append(startedRequest)
            let outcome = reconciliationExecutor(startedRequest, repairProvider)
            switch outcome {
            case .completed, .completedWithFullRepairEvidence, .completedWithCurrentAppRepairEvidence:
                repairProvider.completeReconciliationRequest(id: startedRequest.id)
                result.completedCount += 1
                result.completedAffectedCGWindowIDs.formUnion(
                    startedRequest.affectedCGWindowIDs
                )
                if case let .completedWithFullRepairEvidence(evidence) = outcome {
                    result.fullRepairEvidence.append(evidence)
                }
                result.currentAppRepairEvidence.append(
                    contentsOf: outcome.currentAppRepairEvidence
                )
            case .transientEmptyCurrentAppWindowPayload,
                 .waitingForEvidence:
                if let deferredRequest =
                    repairProvider.deferReconciliationRequestAfterIncompleteEvidence(
                        id: startedRequest.id,
                        requirements:
                            outcome.evidenceRequirements,
                        now: now
                    ) {
                    result.deferredRequests.append(deferredRequest)
                }
            }
        }
        return result
    }
}

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
        var evidenceRequirements:
            Set<RuntimeReconciliationEvidenceRequirement> = []
        if result.isTransientEmptyCurrentAppWindowPayload {
            evidenceRequirements.insert(
                .currentAppWindowPayloadNonEmpty
            )
        }
        if result.isWindowTopologyConvergencePending {
            evidenceRequirements.insert(
                .windowTopologyConvergence
            )
        }
        if !evidenceRequirements.isEmpty {
            return .waitingForEvidence(evidenceRequirements)
        }
        if let evidence = result.currentAppRepairEvidence {
            return .completedWithCurrentAppRepairEvidence([evidence])
        }
        return .completed
    case .fullRepair:
        return .completedWithFullRepairEvidence(repairProvider.fullRepairEvidence())
    case .spaceTopology:
        let results = repairProvider.reconcileSpaceTopology(
            affectedCGWindowIDs: request.affectedCGWindowIDs
        )
        var currentAppRepairEvidence: [RuntimeCurrentAppRepairEvidence] = []
        for result in results {
            if result.isTransientEmptyCurrentAppWindowPayload {
                return .transientEmptyCurrentAppWindowPayload
            }
            if let evidence = result.currentAppRepairEvidence {
                currentAppRepairEvidence.append(evidence)
            }
        }
        if !currentAppRepairEvidence.isEmpty {
            return .completedWithCurrentAppRepairEvidence(
                currentAppRepairEvidence
            )
        }
        return .completed
    }
}
