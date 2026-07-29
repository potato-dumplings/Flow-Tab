#if FLOWTAB_TESTING
import CoreGraphics
import Darwin
import Foundation

extension Notification.Name {
    static let flowTabUITestInitialPresentationDidResolve =
        Notification.Name(
            "FlowTab.UITestInitialPresentationDidResolve"
        )
}

enum FlowTabUITestInitialPresentationMode:
    String,
    Equatable
{
    case global
    case inAppWindow
}

struct FlowTabUITestInitialPresentationSnapshot:
    Equatable
{
    let mode: FlowTabUITestInitialPresentationMode
    let projectionIsPresent: Bool
    let projectionIsComplete: Bool
    let sourceGeneration: RuntimeReadModelGeneration?
    let processIdentifier: pid_t?
    let itemIDs: [String]
    let dirtyAppIDs: Set<String>
    let dirtyPIDs: Set<pid_t>
    let dirtyCGWindowIDs: Set<CGWindowID>
    let pendingRepairScopes: Set<String>

    var isReadyForPresentation: Bool {
        projectionIsPresent
            && projectionIsComplete
            && !itemIDs.isEmpty
    }

    var isTerminalNoContent: Bool {
        projectionIsPresent
            && projectionIsComplete
            && itemIDs.isEmpty
    }

    func hasProgressed(
        from baseline:
            FlowTabUITestInitialPresentationSnapshot
    ) -> Bool {
        if !baseline.projectionIsPresent,
           projectionIsPresent {
            return true
        }
        switch (
            baseline.sourceGeneration,
            sourceGeneration
        ) {
        case let (baselineGeneration?, generation?):
            if generation.isStrictlyLater(
                than: baselineGeneration
            ) {
                return true
            }
            guard generation == baselineGeneration
            else {
                return false
            }
        case (nil, .some):
            return true
        case (.some, nil):
            return false
        case (nil, nil):
            break
        }
        return !baseline.projectionIsComplete
            && projectionIsComplete
    }

    func isCompatibleAfterPresenting(
        _ candidate:
            FlowTabUITestInitialPresentationSnapshot
    ) -> Bool {
        guard mode == candidate.mode,
              projectionIsPresent,
              processIdentifier
                == candidate.processIdentifier,
              itemIDs == candidate.itemIDs
        else {
            return false
        }
        switch (
            candidate.sourceGeneration,
            sourceGeneration
        ) {
        case let (candidateGeneration?, generation?):
            return generation == candidateGeneration
                || generation.isStrictlyLater(
                    than: candidateGeneration
                )
        case (nil, .some), (nil, nil):
            return true
        case (.some, nil):
            return false
        }
    }

    var unmetConditions: [String] {
        var conditions: [String] = []
        if !projectionIsPresent {
            conditions.append("projectionPresent")
        }
        if !projectionIsComplete {
            conditions.append("projectionComplete")
        }
        if itemIDs.isEmpty {
            conditions.append("presentationItems")
        }
        return conditions
    }

    var logFields: String {
        "mode=\(mode.rawValue) "
            + "projectionPresent=\(projectionIsPresent) "
            + "projectionComplete=\(projectionIsComplete) "
            + "sourceGeneration=\(generationDescription) "
            + "pid=\(processIdentifier.map(String.init) ?? "nil") "
            + "items=[\(itemIDs.joined(separator: ","))] "
            + "dirtyApps=[\(dirtyAppIDs.sorted().joined(separator: ","))] "
            + "dirtyPIDs=[\(dirtyPIDs.sorted().map(String.init).joined(separator: ","))] "
            + "dirtyCG=[\(dirtyCGWindowIDs.sorted().map(String.init).joined(separator: ","))] "
            + "pending=[\(pendingRepairScopes.sorted().joined(separator: ","))]"
    }

    private var generationDescription: String {
        guard let sourceGeneration else {
            return "nil"
        }
        return [
            "app:\(sourceGeneration.appLifecycle)",
            "cg:\(sourceGeneration.cg)",
            "space:\(sourceGeneration.space)",
            "ax:\(sourceGeneration.axDirty)",
            "projection:\(sourceGeneration.projection)"
        ].joined(separator: "/")
    }
}

struct FlowTabUITestInitialPresentationAttempt:
    Equatable
{
    let didPresent: Bool
    let sessionItemIDs: [String]
    let searchIsActiveOrPending: Bool
}

enum FlowTabUITestInitialPresentationEvidenceSource:
    String,
    Equatable
{
    case initialReadback
    case readinessRequestReadback
    case appSwitcherProjectionDidUpdate
    case currentAppWindowProjectionDidUpdate
    case watchdogReadback
}

enum FlowTabUITestInitialPresentationResolution:
    String,
    Equatable
{
    case presented
    case noContent
}

struct FlowTabUITestInitialPresentationNotificationRoute {
    let name: Notification.Name
    let source:
        FlowTabUITestInitialPresentationEvidenceSource
}

typealias FlowTabUITestInitialPresentationSnapshotProvider =
    @MainActor () ->
        FlowTabUITestInitialPresentationSnapshot

typealias FlowTabUITestInitialPresentationAttemptHandler =
    @MainActor (
        FlowTabUITestInitialPresentationSnapshot
    ) -> FlowTabUITestInitialPresentationAttempt

struct FlowTabUITestInitialPresentationEvidence:
    Equatable
{
    let observationGeneration: UInt64
    let baseline:
        FlowTabUITestInitialPresentationSnapshot
    let source:
        FlowTabUITestInitialPresentationEvidenceSource
    let candidate:
        FlowTabUITestInitialPresentationSnapshot
    let attempt:
        FlowTabUITestInitialPresentationAttempt?
    let postPresentationReadback:
        FlowTabUITestInitialPresentationSnapshot?
    let resolution:
        FlowTabUITestInitialPresentationResolution?

    var logFields: String {
        var fields = [
            "generation=\(observationGeneration)",
            "source=\(source.rawValue)",
            "resolution=\(resolution?.rawValue ?? "pending")",
            "baseline{\(baseline.logFields)}",
            "candidate{\(candidate.logFields)}"
        ]
        if let attempt {
            fields.append(
                "attempt{presented=\(attempt.didPresent) "
                    + "sessionItems=[\(attempt.sessionItemIDs.joined(separator: ","))] "
                    + "searchActiveOrPending=\(attempt.searchIsActiveOrPending)}"
            )
        }
        if let postPresentationReadback {
            fields.append(
                "post{\(postPresentationReadback.logFields)}"
            )
        }
        return fields.joined(separator: " ")
    }
}

extension FlowTabUITestInitialPresentationEvidence {
    private enum NotificationUserInfoKey {
        static let evidence = "evidence"
    }

    init?(notification: Notification) {
        guard
            let evidence =
                notification.userInfo?[
                    NotificationUserInfoKey.evidence
                ] as? FlowTabUITestInitialPresentationEvidence
        else {
            return nil
        }
        self = evidence
    }

    var notificationUserInfo: [AnyHashable: Any] {
        [
            NotificationUserInfoKey.evidence:
                self
        ]
    }
}

struct FlowTabUITestInitialPresentationWatchdogFailure:
    Equatable
{
    let watchdogInterval: TimeInterval
    let lastEvidence:
        FlowTabUITestInitialPresentationEvidence
    let finalEvidence:
        FlowTabUITestInitialPresentationEvidence

    var logFields: String {
        let unmet = finalEvidence.candidate
            .unmetConditions
            .joined(separator: ",")
        return "condition=initialUIPresentation "
            + "watchdogSeconds=\(watchdogInterval) "
            + "unmet=[\(unmet)] "
            + "last{\(lastEvidence.logFields)} "
            + "final{\(finalEvidence.logFields)}"
    }
}
#endif
