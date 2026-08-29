import Foundation
import FlowTabCore

extension SwitcherPanelController {
    @discardableResult
    func beginManualWindowLayerEntryIfNeeded() -> Bool {
        guard let session = model.session,
              case .appCycle = session.mode
        else {
            return false
        }
        switch model.resolveSelectedAppWindowReadiness() {
        case .ready(let identity, let projection):
            let result = model.enterSelectedAppWindowLayer(
                using: .ready(
                    identity: identity,
                    projection: projection
                )
            )
            completeResolvedWindowLayerEntry(result: result)
            return true
        case .unavailable:
            return true
        case .pending(let identity):
            return beginPendingManualWindowLayerEntry(
                identity: identity
            )
        }
    }

    private func beginPendingManualWindowLayerEntry(
        identity: SessionAppWindowIdentity
    ) -> Bool {
        let targetAppID = identity.appID
        let targetPID = identity.pid
        let presentationGeneration = presentationSessionGeneration
        let observationGeneration =
            manualWindowLayerEntryObservationOwner.start(
                targetAppID: targetAppID,
                targetPID: targetPID,
                presentationGeneration: presentationGeneration,
                baseline: manualWindowLayerEntrySnapshot(
                    targetAppID: targetAppID,
                    readsProjection: false
                ),
                readback: { [unowned self] in
                    self.manualWindowLayerEntrySnapshot(
                        targetAppID: targetAppID
                    )
                },
                onSettled: { [weak self] _ in
                    guard let self else { return }
                    let resolution = self.model
                        .resolveSelectedAppWindowReadiness()
                    self.completeManualWindowLayerEntry(
                        using: resolution,
                        trigger: "ownerSettled"
                    )
                }
            )

        guard manualWindowLayerEntryObservationOwner.isObserving else {
            return true
        }
        _ = model.requestSelectedAppWindowMaintenanceIfNeeded(
            identity: identity
        )
        let requestReturnResolution =
            model.resolveSelectedAppWindowReadiness()
        if completePendingManualWindowLayerEntryIfReady(
            using: requestReturnResolution,
            trigger: "requestReturn"
        ) {
            return true
        }
        scheduleDelayedWindowLayerEntryIfNeeded(
            prewarmsPreviews: false,
            requestsProjection: false
        )
        RuntimeLog.debug(
            .projection,
            "manualWindowLayerEntry result=observing "
                + "appID=\(targetAppID) pid=\(targetPID) "
                + "observationGeneration=\(observationGeneration) "
                + "presentationGeneration=\(presentationGeneration) "
                + "last{\(manualWindowLayerEntryObservationOwner.lastEvidence?.logFields ?? "none")}"
        )
        return true
    }

    @discardableResult
    func observeManualWindowLayerProjectionUpdate(
        appID: String?,
        evidence: RuntimeCurrentAppWindowProjectionUpdateEvidence?
    ) -> Bool {
        guard manualWindowLayerEntryObservationOwner.isObserving else {
            return false
        }
        guard let appID,
              model.sessionAppWindowReadiness?
                  .identity.appID == appID
        else {
            return false
        }
        if let evidence,
           (evidence.appID != appID
               || !manualWindowLayerEntryObservationOwner.matches(
                   targetAppID: evidence.appID,
                   targetPID: evidence.processIdentifier,
                   presentationGeneration:
                       presentationSessionGeneration
               )) {
            return false
        }
        let resolution = model.resolveSelectedAppWindowReadiness()
        return completePendingManualWindowLayerEntryIfReady(
            using: resolution,
            trigger: "projectionUpdated"
        )
    }

    func cancelManualWindowLayerEntryObservation() {
        manualWindowLayerEntryObservationOwner.cancel()
    }

    private func completePendingManualWindowLayerEntryIfReady(
        using resolution: SelectedAppWindowReadinessResolution,
        trigger: String
    ) -> Bool {
        guard case .ready(let identity, _) = resolution,
              manualWindowLayerEntryObservationOwner.matches(
                  targetAppID: identity.appID,
                  targetPID: identity.pid,
                  presentationGeneration:
                      presentationSessionGeneration
              )
        else {
            return false
        }
        manualWindowLayerEntryObservationOwner.cancel(
            invalidate: false
        )
        completeManualWindowLayerEntry(
            using: resolution,
            trigger: trigger
        )
        return true
    }

    private func completeManualWindowLayerEntry(
        using resolution: SelectedAppWindowReadinessResolution,
        trigger: String
    ) {
        guard isPanelPresented else { return }
        let result = model.enterSelectedAppWindowLayer(
            using: resolution
        )
        completeResolvedWindowLayerEntry(result: result)
        resetPointerSelectionGate()
        RuntimeLog.debug(
            .session,
            "advance key=downArrow "
                + "readinessDriven=1 trigger=\(trigger) "
                + model.debugSelectionSummary()
        )
    }

    private func completeResolvedWindowLayerEntry(
        result: SelectedAppWindowLayerEntryResult
    ) {
        RuntimeLog.debug(
            .projection,
            "manualWindowLayerEntry resolution=\(String(describing: result))"
        )
        switch result {
        case .entered:
            updatePanelSize()
            clearDelayedWindowLayerEntryState()
        case .pending:
            scheduleDelayedWindowLayerEntryIfNeeded()
        case .readyWithoutEnoughWindows, .unavailable:
            clearDelayedWindowLayerEntryState()
        }
    }

    private func manualWindowLayerEntrySnapshot(
        targetAppID: String,
        readsProjection: Bool = true
    ) -> ManualWindowLayerEntrySnapshot {
        let session = model.session
        let isAppLayer: Bool
        if let session, case .appCycle = session.mode {
            isAppLayer = true
        } else {
            isAppLayer = false
        }
        let selectedAppID = session?.selectedApp.id
        let selectedPID = selectedAppID.flatMap {
            selectedAppProcessIdentifier(appID: $0)
        }
        return ManualWindowLayerEntrySnapshot(
            readModelGeneration:
                model.runtimeProjectionService
                    .runtimeReadModelDiagnostics().generation,
            presentationGeneration: presentationSessionGeneration,
            selectedAppID: selectedAppID,
            selectedAppPID: selectedPID,
            selectedWindowIDs:
                session?.selectedApp.windows.map(\.id) ?? [],
            isPanelPresented: isPanelPresented,
            isAppLayer: isAppLayer,
            isSearchActive: model.isSearchActive,
            projection: readsProjection
                ? manualWindowLayerProjectionReadback(
                    targetAppID: targetAppID
                )
                : nil
        )
    }

    private func manualWindowLayerProjectionReadback(
        targetAppID: String
    ) -> ManualWindowLayerProjectionReadback? {
        let runtimeService = model.runtimeProjectionService
        if let projection = runtimeService
            .readCurrentAppWindowProjection(appID: targetAppID) {
            return ManualWindowLayerProjectionReadback(
                appID: projection.appID,
                processIdentifier:
                    projection.currentAppWindowPayload.summary.pid,
                windowIDs: projection.currentAppWindowPayload
                    .candidate.windows.map(\.id),
                sourceGeneration:
                    projection.freshness.sourceGeneration,
                isCompleteForScope:
                    projection.freshness.isCompleteForScope
            )
        }
        return nil
    }

    private func selectedAppProcessIdentifier(
        appID: String
    ) -> pid_t? {
        guard let context = model.runtimeContextsByID[appID] else {
            return nil
        }
        return context.ownerPID == 0
            ? context.runningApp.processIdentifier
            : context.ownerPID
    }
}
