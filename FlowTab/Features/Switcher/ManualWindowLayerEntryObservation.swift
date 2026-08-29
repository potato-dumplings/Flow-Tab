import Foundation
import FlowTabCore

struct SessionAppWindowIdentity: Equatable {
    let sessionGeneration: UInt64
    let appID: String
    let pid: pid_t
}

struct SessionAppWindowReadiness: Equatable {
    enum State: Equatable {
        case ready(
            windowCount: Int,
            projectionGeneration: RuntimeReadModelGeneration
        )
        case pending
        case unavailable
    }

    let identity: SessionAppWindowIdentity
    let state: State

    var readyWindowCount: Int? {
        guard case .ready(let windowCount, _) = state else {
            return nil
        }
        return windowCount
    }
}

enum SelectedAppWindowReadinessResolution {
    case ready(
        identity: SessionAppWindowIdentity,
        projection: RuntimeCurrentAppWindowProjection
    )
    case pending(identity: SessionAppWindowIdentity)
    case unavailable
}

enum SelectedAppWindowLayerEntryResult: Equatable {
    case entered
    case readyWithoutEnoughWindows(windowCount: Int)
    case pending
    case unavailable
}

enum SelectedAppWindowReadinessDiagnosticOutcome:
    String,
    Equatable
{
    case ready
    case pending
    case unavailable
}

struct SelectedAppWindowReadinessReadDiagnostic: Equatable {
    let appID: String?
    let outcome: SelectedAppWindowReadinessDiagnosticOutcome
    let startedAtMilliseconds: Double
    let finishedAtMilliseconds: Double
}

struct SelectedAppWindowMaintenanceWaitDiagnostic: Equatable {
    let appID: String
    let startedAtMilliseconds: Double
    let finishedAtMilliseconds: Double

    var elapsedMilliseconds: Double {
        max(0, finishedAtMilliseconds - startedAtMilliseconds)
    }
}

struct ManualWindowLayerProjectionReadback: Equatable {
    let appID: String
    let processIdentifier: pid_t
    let windowIDs: [String]
    let sourceGeneration: RuntimeReadModelGeneration
    let isCompleteForScope: Bool

    var logFields: String {
        "appID=\(appID) "
            + "pid=\(processIdentifier) "
            + "windows=\(windowIDs.joined(separator: ",")) "
            + "sourceGeneration{\(sourceGeneration.logFields)} "
            + "complete=\(isCompleteForScope ? 1 : 0)"
    }
}

struct ManualWindowLayerEntrySnapshot: Equatable {
    let readModelGeneration: RuntimeReadModelGeneration
    let presentationGeneration: Int
    let selectedAppID: String?
    let selectedAppPID: pid_t?
    let selectedWindowIDs: [String]
    let isPanelPresented: Bool
    let isAppLayer: Bool
    let isSearchActive: Bool
    let projection: ManualWindowLayerProjectionReadback?

    var logFields: String {
        "readModelGeneration{\(readModelGeneration.logFields)} "
            + "presentationGeneration=\(presentationGeneration) "
            + "selectedAppID=\(selectedAppID ?? "nil") "
            + "selectedAppPID=\(selectedAppPID.map(String.init) ?? "nil") "
            + "selectedWindows=\(selectedWindowIDs.joined(separator: ",")) "
            + "panelPresented=\(isPanelPresented ? 1 : 0) "
            + "appLayer=\(isAppLayer ? 1 : 0) "
            + "searchActive=\(isSearchActive ? 1 : 0) "
            + "projection{\(projection?.logFields ?? "nil")}"
    }
}

enum ManualWindowLayerEntryEvidenceSource: String, Equatable {
    case initialReadback
    case projectionRequestReturnReadback
    case currentAppWindowProjectionUpdated
}

struct ManualWindowLayerEntryEvidence: Equatable {
    let source: ManualWindowLayerEntryEvidenceSource
    let observationGeneration: Int
    let targetAppID: String
    let targetPID: pid_t
    let presentationGeneration: Int
    let baseline: ManualWindowLayerEntrySnapshot
    let snapshot: ManualWindowLayerEntrySnapshot

    var logFields: String {
        "source=\(source.rawValue) "
            + "observationGeneration=\(observationGeneration) "
            + "targetAppID=\(targetAppID) "
            + "targetPID=\(targetPID) "
            + "baseline{\(baseline.logFields)} "
            + "snapshot{\(snapshot.logFields)}"
    }
}

@MainActor
final class ManualWindowLayerEntryObservationOwner {
    private struct PendingObservation {
        let generation: Int
        let targetAppID: String
        let targetPID: pid_t
        let presentationGeneration: Int
        let baseline: ManualWindowLayerEntrySnapshot
        let readback: @MainActor () -> ManualWindowLayerEntrySnapshot
        let onSettled: @MainActor (ManualWindowLayerEntryEvidence) -> Void
        var lastEvidence: ManualWindowLayerEntryEvidence
    }

    private var pending: PendingObservation?

    private(set) var generation = 0

    var isObserving: Bool {
        pending != nil
    }

    var lastEvidence: ManualWindowLayerEntryEvidence? {
        pending?.lastEvidence
    }

    @discardableResult
    func start(
        targetAppID: String,
        targetPID: pid_t,
        presentationGeneration: Int,
        baseline suppliedBaseline:
            ManualWindowLayerEntrySnapshot? = nil,
        readback: @escaping @MainActor () -> ManualWindowLayerEntrySnapshot,
        onSettled: @escaping @MainActor (ManualWindowLayerEntryEvidence) -> Void
    ) -> Int {
        cancel(invalidate: false)
        generation += 1
        let observationGeneration = generation
        let baseline = suppliedBaseline ?? readback()
        let initialEvidence = ManualWindowLayerEntryEvidence(
            source: .initialReadback,
            observationGeneration: observationGeneration,
            targetAppID: targetAppID,
            targetPID: targetPID,
            presentationGeneration: presentationGeneration,
            baseline: baseline,
            snapshot: baseline
        )
        pending = PendingObservation(
            generation: observationGeneration,
            targetAppID: targetAppID,
            targetPID: targetPID,
            presentationGeneration: presentationGeneration,
            baseline: baseline,
            readback: readback,
            onSettled: onSettled,
            lastEvidence: initialEvidence
        )
        return observationGeneration
    }

    func matches(
        targetAppID: String,
        targetPID: pid_t,
        presentationGeneration: Int
    ) -> Bool {
        guard let pending else { return false }
        return pending.targetAppID == targetAppID
            && pending.targetPID == targetPID
            && pending.presentationGeneration
                == presentationGeneration
    }

    @discardableResult
    func observe(
        source: ManualWindowLayerEntryEvidenceSource,
        eventAppID: String? = nil,
        eventEvidence: RuntimeCurrentAppWindowProjectionUpdateEvidence? = nil,
        observationGeneration: Int,
        presentationGeneration: Int
    ) -> Bool {
        guard var active = matchingPending(
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration
        ) else {
            return false
        }
        if source == .currentAppWindowProjectionUpdated {
            guard eventAppID == active.targetAppID else {
                return false
            }
            if let eventEvidence,
               (eventEvidence.appID != active.targetAppID
                   || eventEvidence.processIdentifier != active.targetPID) {
                return false
            }
        }
        let evidence = ManualWindowLayerEntryEvidence(
            source: source,
            observationGeneration: active.generation,
            targetAppID: active.targetAppID,
            targetPID: active.targetPID,
            presentationGeneration: active.presentationGeneration,
            baseline: active.baseline,
            snapshot: active.readback()
        )
        active.lastEvidence = evidence
        pending = active
        return resolveIfSettled()
    }

    func cancel(invalidate: Bool = true) {
        pending = nil
        if invalidate {
            generation += 1
        }
    }

    private func resolveIfSettled() -> Bool {
        guard let active = pending else { return false }
        let evidence = active.lastEvidence
        guard evidence.snapshot.presentationGeneration
                == active.presentationGeneration,
              evidence.snapshot.selectedAppID == active.targetAppID,
              evidence.snapshot.selectedAppPID == active.targetPID,
              evidence.snapshot.isPanelPresented,
              evidence.snapshot.isAppLayer,
              !evidence.snapshot.isSearchActive,
              let projection = evidence.snapshot.projection,
              projection.appID == active.targetAppID,
              projection.processIdentifier == active.targetPID,
              projection.isCompleteForScope
        else {
            return false
        }
        guard projection.sourceGeneration.isStrictlyLater(
            than: active.baseline.readModelGeneration
        ) else {
            return false
        }
        if let baselineProjection = active.baseline.projection {
            guard projection.sourceGeneration.isStrictlyLater(
                than: baselineProjection.sourceGeneration
            ) else {
                return false
            }
        }
        guard let completed = takePending() else { return false }
        completed.onSettled(evidence)
        return true
    }

    private func matchingPending(
        observationGeneration: Int,
        presentationGeneration: Int
    ) -> PendingObservation? {
        guard let pending,
              pending.generation == observationGeneration,
              pending.presentationGeneration == presentationGeneration
        else {
            return nil
        }
        return pending
    }

    private func takePending() -> PendingObservation? {
        guard let pending else { return nil }
        self.pending = nil
        return pending
    }
}

private extension RuntimeReadModelGeneration {
    var logFields: String {
        "appLifecycle=\(appLifecycle),cg=\(cg),space=\(space),"
            + "axDirty=\(axDirty),projection=\(projection)"
    }
}

extension LiveSwitcherModel {
    func beginSessionAppWindowReadinessTracking() {
        switcherSessionGeneration &+= 1
        selectedAppWindowPriorityRequestIdentity = nil
        selectedAppWindowProjectionPendingAppID = nil
        selectedAppWindowMaintenanceWaitStartedAtMilliseconds = nil
        lastSelectedAppWindowMaintenanceWaitDiagnostic = nil
        lastSelectedAppWindowSessionSwitchAtMilliseconds = nil
        sessionAppWindowReadiness = selectedAppWindowIdentity().map {
            SessionAppWindowReadiness(identity: $0, state: .pending)
        }
    }

    func resetSessionAppWindowReadinessTracking() {
        switcherSessionGeneration &+= 1
        sessionAppWindowReadiness = nil
        selectedAppWindowPriorityRequestIdentity = nil
        selectedAppWindowProjectionPendingAppID = nil
        selectedAppWindowMaintenanceWaitStartedAtMilliseconds = nil
        lastSelectedAppWindowMaintenanceWaitDiagnostic = nil
        lastSelectedAppWindowSessionSwitchAtMilliseconds = nil
    }

    func resetSelectedAppWindowReadinessForSelectionChange() {
        sessionAppWindowReadiness = nil
        selectedAppWindowPriorityRequestIdentity = nil
        selectedAppWindowProjectionPendingAppID = nil
        selectedAppWindowMaintenanceWaitStartedAtMilliseconds = nil
        lastSelectedAppWindowMaintenanceWaitDiagnostic = nil
        lastSelectedAppWindowSessionSwitchAtMilliseconds = nil
    }

    func resolveSelectedAppWindowReadiness()
        -> SelectedAppWindowReadinessResolution
    {
        let startedAtMilliseconds = Self.monotonicMilliseconds()
        guard let identity = selectedAppWindowIdentity() else {
            recordSelectedAppWindowReadinessRead(
                appID: nil,
                outcome: .unavailable,
                startedAtMilliseconds: startedAtMilliseconds
            )
            return .unavailable
        }
        guard let projection = runtimeProjectionService
            .readCurrentAppWindowProjection(appID: identity.appID),
              projection.appID == identity.appID,
              projection.currentAppWindowPayload.summary.pid
                == identity.pid
        else {
            recordSessionAppWindowReadiness(
                SessionAppWindowReadiness(
                    identity: identity,
                    state: .pending
                )
            )
            recordSelectedAppWindowReadinessRead(
                appID: identity.appID,
                outcome: .pending,
                startedAtMilliseconds: startedAtMilliseconds
            )
            return .pending(identity: identity)
        }
        guard projection.freshness.isCompleteForScope else {
            recordSessionAppWindowReadiness(
                SessionAppWindowReadiness(
                    identity: identity,
                    state: .pending
                )
            )
            recordSelectedAppWindowReadinessRead(
                appID: identity.appID,
                outcome: .pending,
                startedAtMilliseconds: startedAtMilliseconds
            )
            return .pending(identity: identity)
        }

        recordSessionAppWindowReadiness(
            SessionAppWindowReadiness(
                identity: identity,
                state: .ready(
                    windowCount: projection.currentAppWindowPayload
                        .candidate.windows.count,
                    projectionGeneration:
                        projection.freshness.sourceGeneration
                )
            )
        )
        selectedAppWindowProjectionPendingAppID = nil
        let finishedAtMilliseconds = Self.monotonicMilliseconds()
        recordSelectedAppWindowReadinessRead(
            appID: identity.appID,
            outcome: .ready,
            startedAtMilliseconds: startedAtMilliseconds,
            finishedAtMilliseconds: finishedAtMilliseconds
        )
        if let waitStartedAtMilliseconds =
            selectedAppWindowMaintenanceWaitStartedAtMilliseconds {
            lastSelectedAppWindowMaintenanceWaitDiagnostic =
                SelectedAppWindowMaintenanceWaitDiagnostic(
                    appID: identity.appID,
                    startedAtMilliseconds:
                        waitStartedAtMilliseconds,
                    finishedAtMilliseconds:
                        finishedAtMilliseconds
                )
            selectedAppWindowMaintenanceWaitStartedAtMilliseconds = nil
        }
        return .ready(identity: identity, projection: projection)
    }

    @discardableResult
    func refreshSelectedAppWindowReadiness() -> Bool {
        let previous = sessionAppWindowReadiness
        _ = resolveSelectedAppWindowReadiness()
        return previous != sessionAppWindowReadiness
    }

    @discardableResult
    func requestSelectedAppWindowMaintenanceIfNeeded(
        identity: SessionAppWindowIdentity
    ) -> Bool {
        guard identity == selectedAppWindowIdentity() else {
            return false
        }
        guard selectedAppWindowPriorityRequestIdentity != identity else {
            return false
        }
        selectedAppWindowPriorityRequestIdentity = identity
        selectedAppWindowProjectionPendingAppID = identity.appID
        if selectedAppWindowMaintenanceWaitStartedAtMilliseconds == nil {
            selectedAppWindowMaintenanceWaitStartedAtMilliseconds =
                Self.monotonicMilliseconds()
        }
        selectedAppWindowProjectionGeneration &+= 1
        RuntimeLog.debug(
            .projection,
            "selectedAppWindowProjection result=priorityRequested appID=\(identity.appID) pid=\(identity.pid) sessionGeneration=\(identity.sessionGeneration)"
        )
        runtimeProjectionService.signalSelectedCurrentAppWindowsChanged(
            appID: identity.appID,
            pid: identity.pid
        )
        return true
    }

    func enterSelectedAppWindowLayerUsingCurrentReadiness()
        -> SelectedAppWindowLayerEntryResult
    {
        enterSelectedAppWindowLayer(
            using: resolveSelectedAppWindowReadiness()
        )
    }

    func enterSelectedAppWindowLayer(
        using resolution: SelectedAppWindowReadinessResolution
    ) -> SelectedAppWindowLayerEntryResult {
        switch resolution {
        case .unavailable:
            return .unavailable
        case .pending:
            return .pending
        case .ready(let identity, let projection):
            return applyReadySelectedAppWindowProjectionAndEnter(
                identity: identity,
                projection: projection
            )
        }
    }

    private func applyReadySelectedAppWindowProjectionAndEnter(
        identity: SessionAppWindowIdentity,
        projection: RuntimeCurrentAppWindowProjection
    ) -> SelectedAppWindowLayerEntryResult {
        guard identity == selectedAppWindowIdentity(),
              projection.appID == identity.appID,
              projection.currentAppWindowPayload.summary.pid
                == identity.pid,
              projection.freshness.isCompleteForScope
        else {
            return .unavailable
        }

        pendingManualWindowLayerEntryAppID = nil
        selectedAppWindowProjectionGeneration &+= 1
        let startMs = Self.monotonicMilliseconds()
        completeSelectedAppWindowProjection(
            currentAppWindowPayloadWithWindowRecencyApplied(
                projection.currentAppWindowPayload
            ),
            appID: identity.appID,
            generation: selectedAppWindowProjectionGeneration,
            startMs: startMs,
            projectionReadMs: startMs,
            notifiesSessionLayoutChange: false
        )

        let windowCount = projection.currentAppWindowPayload
            .candidate.windows.count
        guard windowCount >= 2,
              var currentSession = session,
              case .appCycle = currentSession.mode,
              currentSession.selectedApp.id == identity.appID,
              currentSession.enterWindowCycle(allowSingleWindow: false)
        else {
            return .readyWithoutEnoughWindows(
                windowCount: windowCount
            )
        }
        session = currentSession
        lastSelectedAppWindowSessionSwitchAtMilliseconds =
            Self.monotonicMilliseconds()
        return .entered
    }

    private func selectedAppWindowIdentity()
        -> SessionAppWindowIdentity?
    {
        guard let session,
              case .appCycle = session.mode,
              !searchViewState.isActive,
              let context = runtimeContextsByID[session.selectedApp.id]
        else {
            return nil
        }
        let pid = context.ownerPID == 0
            ? context.runningApp.processIdentifier
            : context.ownerPID
        guard pid != 0 else { return nil }
        return SessionAppWindowIdentity(
            sessionGeneration: switcherSessionGeneration,
            appID: session.selectedApp.id,
            pid: pid
        )
    }

    private func recordSessionAppWindowReadiness(
        _ readiness: SessionAppWindowReadiness
    ) {
        guard sessionAppWindowReadiness != readiness else { return }
        sessionAppWindowReadiness = readiness
    }

    private func recordSelectedAppWindowReadinessRead(
        appID: String?,
        outcome: SelectedAppWindowReadinessDiagnosticOutcome,
        startedAtMilliseconds: Double,
        finishedAtMilliseconds: Double? = nil
    ) {
        lastSelectedAppWindowReadinessReadDiagnostic =
            SelectedAppWindowReadinessReadDiagnostic(
                appID: appID,
                outcome: outcome,
                startedAtMilliseconds: startedAtMilliseconds,
                finishedAtMilliseconds:
                    finishedAtMilliseconds
                        ?? Self.monotonicMilliseconds()
            )
    }
}
