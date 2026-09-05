import AppKit

@MainActor
protocol SwitcherPanelDelayedOperating: AnyObject {
    func scheduleDelayedWindowLayerEntryIfNeeded(
        preservingDeadline: Bool,
        prewarmsPreviews: Bool,
        requestsProjection: Bool
    )
    func observeDelayedWindowLayerProjectionUpdate(
        source: DelayedWindowLayerEntryEvidenceSource,
        appID: String?
    )
    func clearDelayedWindowLayerEntryState()
    func prewarmSelectedAppWindowPreviewPage() -> Int
    func beginInitialVisibilityTracking(trigger: String) -> Int
    func scheduleInitialVisibilityRecovery(trigger: String, initialVisibilityGeneration: Int)
    func cancelPresentationWork()
    func prewarmWindowOnlySessionPreviews() -> Int
}

@MainActor
final class SwitcherPanelDelayedOperations: SwitcherPanelDelayedOperating {
    unowned let controller: SwitcherPanelController
    let observation: DelayedWindowLayerEntryObservationOwner
    init(controller: SwitcherPanelController) {
        self.controller = controller
        self.observation = controller.delayedWindowLayerEntryObservationOwner
    }
    func beginInitialVisibilityTracking(trigger: String) -> Int {
        controller.beginInitialPresentationVisibilityTracking(trigger: trigger)
    }
    func scheduleInitialVisibilityRecovery(trigger: String, initialVisibilityGeneration: Int) {
        controller.scheduleInitialPanelVisibilityRecovery(trigger: trigger, initialVisibilityGeneration: initialVisibilityGeneration)
    }
    func cancelPresentationWork() {
        controller.cancelPendingFocusedWindowSessionPresentation(reason: "presentationEnded")
        controller.invalidatePresentationSessionGeneration(trigger: "endPresentationSession")
        controller.cancelActiveSpaceTransitionObservation()
        controller.cancelTerminateInterruptionProtection()
        controller.cancelPanelPresentationRecovery()
        controller.clearInitialPresentationVisibilityTracking(invalidate: true)
        controller.clearInitialVisibleFrameTracking()
    }
    func prewarmWindowOnlySessionPreviews() -> Int { controller.model.prewarmWindowOnlySessionPreviews() }

    func scheduleDelayedWindowLayerEntryIfNeeded(
        preservingDeadline: Bool = false,
        prewarmsPreviews: Bool = true,
        requestsProjection: Bool = true
    ) {
        guard controller.autoEnterWindowLayerEnabled else {
            clearDelayedWindowLayerEntryState()
            return
        }
        guard !controller.hasActiveOrPendingSearchInteraction else {
            clearDelayedWindowLayerEntryState()
            RuntimeLog.debug(.autoEnter, "skip searchInteraction")
            return
        }
        guard controller.isPanelPresented else {
            clearDelayedWindowLayerEntryState()
            RuntimeLog.debug(.autoEnter, "skip panelHidden")
            return
        }
        guard let session = controller.model.session,
              case .appCycle = session.mode
        else {
            clearDelayedWindowLayerEntryState()
            return
        }

        let targetAppID = session.selectedApp.id
        let presentationGeneration =
            controller.presentationSessionGeneration
        let prewarmedPreviewCount = prewarmsPreviews
            ? prewarmSelectedAppWindowPreviewPage()
            : 0

        if preservingDeadline,
           observation.matches(
               targetAppID: targetAppID,
               presentationGeneration: presentationGeneration
           ) {
            requestAndObserveDelayedWindowLayerProjection(
                targetAppID: targetAppID,
                observationGeneration:
                    observation.generation,
                presentationGeneration: presentationGeneration,
                prewarmedPreviewCount: prewarmedPreviewCount,
                requestsProjection: requestsProjection,
                source: .sessionLayoutChanged
            )
            return
        }

        let delay = controller.windowLayerPresentationDelay
        let observationGeneration =
            observation.start(
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
        guard observation.matches(
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
            requestsProjection: requestsProjection,
            source: .projectionRequestReturnReadback
        )
    }

    func observeDelayedWindowLayerProjectionUpdate(
        source: DelayedWindowLayerEntryEvidenceSource,
        appID: String? = nil
    ) {
        guard
            let targetAppID =
                observation.targetAppID,
            observation.matches(
                targetAppID: targetAppID,
                presentationGeneration:
                    controller.presentationSessionGeneration
            )
        else {
            return
        }
        _ = observation.observe(
            source: source,
            eventAppID: appID,
            observationGeneration:
                observation.generation,
            presentationGeneration:
                controller.presentationSessionGeneration
        )
    }

    func clearDelayedWindowLayerEntryState() {
        observation.cancel()
    }

    func prewarmSelectedAppWindowPreviewPage() -> Int {
        guard let selectedApp = controller.model.selectedApp,
              !selectedApp.windows.isEmpty
        else {
            return 0
        }
        let sizingScreen = controller.resolveSizingScreen(
            preferredScreen: controller.activePresentationScreen
        )
        let visibleFrameSize = sizingScreen?.visibleFrame.size
            ?? CGSize(width: 1_440, height: 900)
        let maximumPanelWidth = max(
            controller.appLayerMinimumWidth,
            visibleFrameSize.width - controller.panelScreenMargin
        )
        let previewPanelWidth = min(
            maximumPanelWidth,
            controller.preferredPreviewLayerWidth(
                appCount: controller.model.appCount,
                windowCount: selectedApp.windows.count,
                maxPanelWidth: maximumPanelWidth
            )
        )
        let previewAvailableWidth = max(
            1,
            previewPanelWidth
                - SwitcherPanelLayoutMetrics.horizontalInset
                - controller.standardPreviewWidthAdjustment
        )
        return controller.model.prewarmSelectedAppWindowPreviews(
            availableWidth: previewAvailableWidth
        )
    }

    func requestAndObserveDelayedWindowLayerProjection(
        targetAppID: String,
        observationGeneration: Int,
        presentationGeneration: Int,
        prewarmedPreviewCount: Int,
        requestsProjection: Bool,
        source: DelayedWindowLayerEntryEvidenceSource
    ) {
        let requestedProjection = requestsProjection
            && controller.model.scheduleSelectedAppWindowProjectionIfNeeded(
                for: targetAppID
            )
        guard observation.matches(
            targetAppID: targetAppID,
            presentationGeneration: presentationGeneration
        ) else {
            return
        }
        _ = observation.observe(
            source: source,
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration
        )
        guard observation.matches(
            targetAppID: targetAppID,
            presentationGeneration: presentationGeneration
        ) else {
            return
        }
        let deadline = observation
            .deadlineMilliseconds
            .map(controller.formatMilliseconds)
            ?? "resolved"
        RuntimeLog.debug(
            .autoEnter,
            "pending targetAppID=\(targetAppID) "
                + "requestedProjection=\(requestedProjection ? 1 : 0) "
                + "prewarmed=\(prewarmedPreviewCount) "
                + "deadlineMs=\(deadline) "
                + controller.model.debugSelectionSummary()
        )
    }

    func delayedWindowLayerEntrySnapshot()
        -> DelayedWindowLayerEntrySnapshot
    {
        let session = controller.model.session
        let isAppLayer: Bool
        if let session, case .appCycle = session.mode {
            isAppLayer = true
        } else {
            isAppLayer = false
        }
        return DelayedWindowLayerEntrySnapshot(
            presentationGeneration:
                controller.presentationSessionGeneration,
            selectedAppID: session?.selectedApp.id,
            selectedWindowCount:
                controller.model.sessionAppWindowReadiness?
                    .readyWindowCount ?? 0,
            projectionGeneration:
                controller.model.selectedAppWindowProjectionGeneration,
            isPanelPresented: controller.isPanelPresented,
            isAppLayer: isAppLayer,
            isSearchActive: controller.model.isSearchActive,
            canAutoEnterWindowLayer:
                controller.model.canAutoEnterWindowLayer
        )
    }

    func enterDelayedWindowLayer(
        using evidence: DelayedWindowLayerEntryEvidence
    ) {
        guard
            evidence.presentationGeneration
                == controller.presentationSessionGeneration,
            controller.isPanelPresented,
            controller.model.autoEnterWindowLayerIfPossible()
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
                + "overshootMs=\(controller.formatMilliseconds(evidence.overshootMilliseconds)) "
                + controller.model.debugSelectionSummary()
        )
        if evidence.overshootMilliseconds > 10 {
            RuntimeLog.warning(
                .autoEnter,
                "deadline overshootMs="
                    + controller.formatMilliseconds(
                        evidence.overshootMilliseconds
                    )
                    + " "
                    + controller.model.debugSelectionSummary()
            )
        }
        controller.updatePanelSize()
    }
}
