import Foundation
import FlowTabCore

extension SwitcherPanelController {
    @discardableResult
    func beginManualWindowLayerEntryIfNeeded() -> Bool {
        guard let session = model.session,
              case .appCycle = session.mode,
              session.selectedApp.windows.count >= 2,
              let targetPID = selectedAppProcessIdentifier(
                  appID: session.selectedApp.id
              )
        else {
            return false
        }
        let targetAppID = session.selectedApp.id
        let presentationGeneration = presentationSessionGeneration
        let observationGeneration =
            manualWindowLayerEntryObservationOwner.start(
                targetAppID: targetAppID,
                targetPID: targetPID,
                presentationGeneration: presentationGeneration,
                readback: { [unowned self] in
                    self.manualWindowLayerEntrySnapshot(
                        targetAppID: targetAppID
                    )
                },
                onSettled: { [weak self] evidence in
                    self?.completeManualWindowLayerEntry(
                        using: evidence
                    )
                }
            )

        guard manualWindowLayerEntryObservationOwner.isObserving else {
            return true
        }
        model.runtimeProjectionService
            .signalSelectedCurrentAppWindowsChanged(
                appID: targetAppID,
                pid: targetPID
            )
        _ = manualWindowLayerEntryObservationOwner.observe(
            source: .projectionRequestReturnReadback,
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration
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
        return manualWindowLayerEntryObservationOwner.observe(
            source: .currentAppWindowProjectionUpdated,
            eventAppID: appID,
            eventEvidence: evidence,
            observationGeneration:
                manualWindowLayerEntryObservationOwner.generation,
            presentationGeneration: presentationSessionGeneration
        )
    }

    func cancelManualWindowLayerEntryObservation() {
        manualWindowLayerEntryObservationOwner.cancel()
    }

    private func completeManualWindowLayerEntry(
        using evidence: ManualWindowLayerEntryEvidence
    ) {
        guard evidence.presentationGeneration
                == presentationSessionGeneration,
              isPanelPresented
        else {
            return
        }
        _ = model.applyCurrentAppWindowProjectionIfReady(
            appID: evidence.targetAppID
        )
        model.handle(.downArrow)
        resetPointerSelectionGate()
        RuntimeLog.debug(
            .session,
            "advance key=downArrow "
                + "evidenceDriven=1 \(model.debugSelectionSummary()) "
                + "evidence{\(evidence.logFields)}"
        )
        updatePanelSize()
        scheduleDelayedWindowLayerEntryIfNeeded()
    }

    private func manualWindowLayerEntrySnapshot(
        targetAppID: String
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
            projection: manualWindowLayerProjectionReadback(
                targetAppID: targetAppID
            )
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
