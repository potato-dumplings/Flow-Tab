import Foundation

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
        readback: @escaping @MainActor () -> ManualWindowLayerEntrySnapshot,
        onSettled: @escaping @MainActor (ManualWindowLayerEntryEvidence) -> Void
    ) -> Int {
        cancel(invalidate: false)
        generation += 1
        let observationGeneration = generation
        let baseline = readback()
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
