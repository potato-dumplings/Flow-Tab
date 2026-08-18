import Foundation

struct TerminateInterruptionTargetIdentity: Equatable {
    let appID: String
    let pid: pid_t
    let requestGeneration: UInt64?
}

enum TerminateTargetProjectionState: String, Equatable {
    case exactInstancePresent
    case instanceAbsent
    case instanceReplaced
    case identityUnavailable
    case projectionUnavailable

    var confirmsTargetRemoval: Bool {
        self == .instanceAbsent || self == .instanceReplaced
    }
}

enum TerminateTargetProcessState: String, Equatable {
    case running
    case terminated
    case unavailable
}

struct TerminateInterruptionProtectionBaseline: Equatable {
    let appID: String
    let projectionGeneration: UInt64
    let projectionContainsAppID: Bool?
    let panelVisibility: PanelVisibilitySnapshot

    var logFields: String {
        "appID=\(appID) "
            + "projectionGeneration=\(projectionGeneration) "
            + "projectionContainsAppID="
            + (projectionContainsAppID.map { $0 ? "1" : "0" } ?? "unavailable")
            + " panel{\(panelVisibility.logFields)}"
    }
}

struct TerminateInterruptionProtectionSnapshot: Equatable {
    let projectionGeneration: UInt64
    let projectionState: TerminateTargetProjectionState
    let processState: TerminateTargetProcessState
    let sessionContainsAppID: Bool
    let pendingRequestMatches: Bool
    let activeSpaceTransitionPending: Bool
    let panelVisibility: PanelVisibilitySnapshot

    var logFields: String {
        "projectionGeneration=\(projectionGeneration) "
            + "projectionState=\(projectionState.rawValue) "
            + "processState=\(processState.rawValue) "
            + "sessionContainsAppID=\(sessionContainsAppID ? 1 : 0) "
            + "pendingRequestMatches=\(pendingRequestMatches ? 1 : 0) "
            + "activeSpaceTransitionPending="
            + "\(activeSpaceTransitionPending ? 1 : 0) "
            + "panel{\(panelVisibility.logFields)}"
    }
}

enum TerminateInterruptionProtectionEvidenceSource: String, Equatable {
    case requestReturnReadback
    case workspaceTerminationReadback
    case projectionUpdateReadback
    case activeSpaceTransitionReadback
    case panelVisibilityReadback
    case systemInterruptionReadback
    case watchdogReadback
}

struct TerminateInterruptionProtectionEvidence: Equatable {
    let source: TerminateInterruptionProtectionEvidenceSource
    let observationGeneration: Int
    let presentationGeneration: Int
    let target: TerminateInterruptionTargetIdentity
    let baseline: TerminateInterruptionProtectionBaseline
    let matchingTerminationObserved: Bool
    let protectedSystemInterruptionObserved: Bool
    let snapshot: TerminateInterruptionProtectionSnapshot
}

struct TerminateInterruptionProtectionWatchdogFailure: Equatable {
    let trigger: String
    let observationGeneration: Int
    let presentationGeneration: Int
    let target: TerminateInterruptionTargetIdentity
    let baseline: TerminateInterruptionProtectionBaseline
    let lastEvidence: TerminateInterruptionProtectionEvidence
    let finalEvidence: TerminateInterruptionProtectionEvidence

    var logFields: String {
        "condition=targetTerminationAndProjectionRemoval "
            + "targetAppID=\(target.appID) targetPID=\(target.pid) "
            + "requestGeneration=\(target.requestGeneration.map(String.init) ?? "none") "
            + "baseline{\(baseline.logFields)} "
            + "lastSource=\(lastEvidence.source.rawValue) "
            + "lastProtectedInterruption="
            + "\(lastEvidence.protectedSystemInterruptionObserved ? 1 : 0) "
            + "last{\(lastEvidence.snapshot.logFields)} "
            + "final{\(finalEvidence.snapshot.logFields)}"
    }
}
