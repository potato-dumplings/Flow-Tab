import Foundation

extension SwitcherPanelController {
    func scheduleDelayedWindowLayerEntryIfNeeded(
        preservingDeadline: Bool = false
    ) {
        guard autoEnterWindowLayerEnabled else {
            clearDelayedWindowLayerEntryState()
            return
        }
        guard !hasActiveOrPendingSearchInteraction else {
            clearDelayedWindowLayerEntryState()
            RuntimeLog.debug(.autoEnter, "skip searchInteraction")
            return
        }
        guard isPanelPresented else {
            clearDelayedWindowLayerEntryState()
            RuntimeLog.debug(.autoEnter, "skip panelHidden")
            return
        }
        guard let session = model.session,
              case .appCycle = session.mode
        else {
            clearDelayedWindowLayerEntryState()
            return
        }

        let targetAppID = session.selectedApp.id
        let presentationGeneration =
            presentationSessionGeneration
        let prewarmedPreviewCount =
            prewarmSelectedAppWindowPreviewPage()

        if preservingDeadline,
           delayedWindowLayerEntryObservationOwner.matches(
               targetAppID: targetAppID,
               presentationGeneration: presentationGeneration
           ) {
            requestAndObserveDelayedWindowLayerProjection(
                targetAppID: targetAppID,
                observationGeneration:
                    delayedWindowLayerEntryObservationOwner.generation,
                presentationGeneration: presentationGeneration,
                prewarmedPreviewCount: prewarmedPreviewCount,
                source: .sessionLayoutChanged
            )
            return
        }

        let delay = windowLayerPresentationDelay
        let observationGeneration =
            delayedWindowLayerEntryObservationOwner.start(
                targetAppID: targetAppID,
                presentationGeneration: presentationGeneration,
                delay: delay,
                readback: { [weak self] in
                    self?.delayedWindowLayerEntrySnapshot()
                        ?? DelayedWindowLayerEntrySnapshot(
                            presentationGeneration: -1,
                            selectedAppID: nil,
                            selectedWindowCount: 0,
                            projectionGeneration: 0,
                            isPanelPresented: false,
                            isAppLayer: false,
                            isSearchActive: false,
                            canAutoEnterWindowLayer: false
                        )
                },
                onReady: { [weak self] evidence in
                    self?.enterDelayedWindowLayer(
                        using: evidence
                    )
                }
            )
        guard delayedWindowLayerEntryObservationOwner.matches(
            targetAppID: targetAppID,
            presentationGeneration: presentationGeneration
        ) else {
            return
        }

        RuntimeLog.debug(
            .autoEnter,
            "observe targetAppID=\(targetAppID) delay=\(delay)s "
                + "prewarmed=\(prewarmedPreviewCount) "
                + "observationGeneration=\(observationGeneration) "
                + "presentationGeneration=\(presentationGeneration)"
        )
        requestAndObserveDelayedWindowLayerProjection(
            targetAppID: targetAppID,
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration,
            prewarmedPreviewCount: prewarmedPreviewCount,
            source: .projectionRequestReturnReadback
        )
    }

    func observeDelayedWindowLayerProjectionUpdate(
        source: DelayedWindowLayerEntryEvidenceSource,
        appID: String? = nil
    ) {
        guard
            let targetAppID =
                delayedWindowLayerEntryObservationOwner.targetAppID,
            delayedWindowLayerEntryObservationOwner.matches(
                targetAppID: targetAppID,
                presentationGeneration:
                    presentationSessionGeneration
            )
        else {
            return
        }
        _ = delayedWindowLayerEntryObservationOwner.observe(
            source: source,
            eventAppID: appID,
            observationGeneration:
                delayedWindowLayerEntryObservationOwner.generation,
            presentationGeneration:
                presentationSessionGeneration
        )
    }

    func clearDelayedWindowLayerEntryState() {
        delayedWindowLayerEntryObservationOwner.cancel()
    }

    func prewarmSelectedAppWindowPreviewPage() -> Int {
        guard let selectedApp = model.selectedApp,
              !selectedApp.windows.isEmpty
        else {
            return 0
        }
        let sizingScreen = resolveSizingScreen(
            preferredScreen: activePresentationScreen
        )
        let visibleFrameSize = sizingScreen?.visibleFrame.size
            ?? CGSize(width: 1_440, height: 900)
        let maximumPanelWidth = max(
            appLayerMinimumWidth,
            visibleFrameSize.width - panelScreenMargin
        )
        let previewPanelWidth = min(
            maximumPanelWidth,
            preferredPreviewLayerWidth(
                appCount: model.appCount,
                windowCount: selectedApp.windows.count,
                maxPanelWidth: maximumPanelWidth
            )
        )
        let previewAvailableWidth = max(
            1,
            previewPanelWidth
                - SwitcherPanelLayoutMetrics.horizontalInset
                - standardPreviewWidthAdjustment
        )
        return model.prewarmSelectedAppWindowPreviews(
            availableWidth: previewAvailableWidth
        )
    }

    private func requestAndObserveDelayedWindowLayerProjection(
        targetAppID: String,
        observationGeneration: Int,
        presentationGeneration: Int,
        prewarmedPreviewCount: Int,
        source: DelayedWindowLayerEntryEvidenceSource
    ) {
        let requestedProjection =
            model.scheduleSelectedAppWindowProjectionIfNeeded(
                for: targetAppID
            )
        guard delayedWindowLayerEntryObservationOwner.matches(
            targetAppID: targetAppID,
            presentationGeneration: presentationGeneration
        ) else {
            return
        }
        _ = delayedWindowLayerEntryObservationOwner.observe(
            source: source,
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration
        )
        guard delayedWindowLayerEntryObservationOwner.matches(
            targetAppID: targetAppID,
            presentationGeneration: presentationGeneration
        ) else {
            return
        }
        let deadline = delayedWindowLayerEntryObservationOwner
            .deadlineMilliseconds
            .map(formatMilliseconds)
            ?? "resolved"
        RuntimeLog.debug(
            .autoEnter,
            "pending targetAppID=\(targetAppID) "
                + "requestedProjection=\(requestedProjection ? 1 : 0) "
                + "prewarmed=\(prewarmedPreviewCount) "
                + "deadlineMs=\(deadline) "
                + model.debugSelectionSummary()
        )
    }

    private func delayedWindowLayerEntrySnapshot()
        -> DelayedWindowLayerEntrySnapshot
    {
        let session = model.session
        let isAppLayer: Bool
        if let session, case .appCycle = session.mode {
            isAppLayer = true
        } else {
            isAppLayer = false
        }
        return DelayedWindowLayerEntrySnapshot(
            presentationGeneration:
                presentationSessionGeneration,
            selectedAppID: session?.selectedApp.id,
            selectedWindowCount:
                session?.selectedApp.windows.count ?? 0,
            projectionGeneration:
                model.selectedAppWindowProjectionGeneration,
            isPanelPresented: isPanelPresented,
            isAppLayer: isAppLayer,
            isSearchActive: model.isSearchActive,
            canAutoEnterWindowLayer:
                model.canAutoEnterWindowLayer
        )
    }

    private func enterDelayedWindowLayer(
        using evidence: DelayedWindowLayerEntryEvidence
    ) {
        guard
            evidence.presentationGeneration
                == presentationSessionGeneration,
            isPanelPresented,
            model.autoEnterWindowLayerIfPossible()
        else {
            RuntimeLog.debug(
                .autoEnter,
                "ready evidence rejected \(evidence.logFields)"
            )
            return
        }
        RuntimeLog.debug(
            .autoEnter,
            "entered source=\(evidence.source.rawValue) "
                + "overshootMs=\(formatMilliseconds(evidence.overshootMilliseconds)) "
                + model.debugSelectionSummary()
        )
        if evidence.overshootMilliseconds > 10 {
            RuntimeLog.warning(
                .autoEnter,
                "deadline overshootMs="
                    + formatMilliseconds(
                        evidence.overshootMilliseconds
                    )
                    + " "
                    + model.debugSelectionSummary()
            )
        }
        updatePanelSize()
    }
}
