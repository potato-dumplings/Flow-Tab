#if FLOWTAB_TESTING
import Foundation

private enum FlowTabUITestInitialSearchActivationPolicy {
    static let searchIndexReadinessWatchdog =
        RuntimeTransientRepairObservationPolicy.standard
            .watchdogInterval
}

@MainActor
extension FlowTabUITestBootstrapper {
    static func prepareInitialSearchActivationIfNeeded(
        panelController: SwitcherPanelController,
        runtimeProjectionService:
            any RuntimeProjectionServing,
        shouldActivateSearch: Bool
    ) {
        stopInitialSearchActivationObservation()
        guard shouldActivateSearch
        else {
            return
        }
        let owner =
            FlowTabUITestInitialSearchActivationObservationOwner(
                notificationObject:
                    runtimeProjectionService as AnyObject,
                readback: { [weak panelController] in
                    initialSearchActivationSnapshot(
                        panelController: panelController
                    )
                },
                activateSearch: { [weak panelController] in
                    _ = panelController?
                        .enterSearchModeIfPossible()
                }
        )
        initialSearchActivationObservationOwner = owner
        owner.start {
            runtimeProjectionService
                .requestSearchIndexFreshnessBarrier(
                    reason: .searchFreshnessBarrier
                )
        }
    }

    static func resolveInitialPresentation(
        _ evidence:
            FlowTabUITestInitialPresentationEvidence,
        observationOwner:
            FlowTabUITestInitialPresentationObservationOwner,
        panelController: SwitcherPanelController,
        shouldActivateSearch: Bool
    ) {
        guard initialPresentationObservationOwner
                === observationOwner
        else {
            return
        }
        initialPresentationObservationOwner = nil
        guard shouldActivateSearch
        else {
            stopInitialSearchActivationObservation()
            publishInitialPresentationResolution(
                evidence,
                panelController: panelController
            )
            return
        }
        guard let searchOwner =
                initialSearchActivationObservationOwner
        else {
            panelController.cancelSelectionForTesting()
            RuntimeLog.error(
                "UITest",
                "initial search activation owner missing "
                    + evidence.logFields
            )
            return
        }
        searchOwner.awaitActivation(
            expectedItemIDs: evidence.candidate.itemIDs,
            watchdogInterval:
                FlowTabUITestInitialSearchActivationPolicy
                    .searchIndexReadinessWatchdog,
            onResolved: {
                [weak searchOwner, weak panelController]
                searchEvidence in
                guard let searchOwner,
                      let panelController,
                      initialSearchActivationObservationOwner
                        === searchOwner
                else {
                    return
                }
                initialSearchActivationObservationOwner = nil
                publishInitialPresentationResolution(
                    evidence.confirmingSearchActivation(),
                    panelController: panelController,
                    searchEvidence: searchEvidence
                )
            },
            onWatchdog: {
                [weak searchOwner, weak panelController]
                failure in
                guard let searchOwner,
                      initialSearchActivationObservationOwner
                        === searchOwner
                else {
                    return
                }
                initialSearchActivationObservationOwner = nil
                panelController?
                    .cancelSelectionForTesting()
                RuntimeLog.error(
                    "UITest",
                    "initial search activation watchdog "
                        + failure.logFields
                        + " presentation{\(evidence.logFields)}"
                )
            }
        )
    }

    static func stopInitialSearchActivationObservation() {
        initialSearchActivationObservationOwner?
            .cancel()
        initialSearchActivationObservationOwner = nil
    }

    private static func initialSearchActivationSnapshot(
        panelController: SwitcherPanelController?
    ) -> FlowTabUITestInitialSearchActivationSnapshot {
        guard let panelController else {
            return FlowTabUITestInitialSearchActivationSnapshot(
                panelIsPresented: false,
                sessionItemIDs: [],
                searchIsActive: false,
                searchActivationIsPending: false
            )
        }
        let model = panelController.modelForTesting
        return FlowTabUITestInitialSearchActivationSnapshot(
            panelIsPresented:
                panelController.isPanelPresented,
            sessionItemIDs:
                model.session?.apps.map(\.id) ?? [],
            searchIsActive: model.isSearchActive,
            searchActivationIsPending:
                model
                    .pendingSearchActivationAfterFreshnessBarrier
        )
    }

    private static func publishInitialPresentationResolution(
        _ evidence:
            FlowTabUITestInitialPresentationEvidence,
        panelController: SwitcherPanelController,
        searchEvidence:
            FlowTabUITestInitialSearchActivationEvidence? = nil
    ) {
        publishInitialPresentationResolutionReadbackIfNeeded(
            evidence,
            panelController: panelController
        )
        NotificationCenter.default.post(
            name:
                .flowTabUITestInitialPresentationDidResolve,
            object: panelController,
            userInfo: evidence.notificationUserInfo
        )
        let searchFields = searchEvidence.map {
            " search{\($0.logFields)}"
        } ?? ""
        RuntimeLog.info(
            "UITest",
            "initial presentation resolved "
                + evidence.logFields
                + searchFields
        )
    }

    private static func publishInitialPresentationResolutionReadbackIfNeeded(
        _ evidence:
            FlowTabUITestInitialPresentationEvidence,
        panelController: SwitcherPanelController
    ) {
        guard let route =
                FlowTabTestLaunchOptions
                    .initialPresentationResolutionRoute
        else {
            return
        }
        guard let attempt = evidence.attempt,
              let baseline =
                evidence.postPresentationReadback,
              let selectedAppID =
                panelController.modelForTesting
                    .session?.selectedApp.id,
              !selectedAppID.isEmpty
        else {
            RuntimeLog.error(
                "UITest",
                "initial presentation resolution readback "
                    + "missing terminal evidence "
                    + evidence.logFields
            )
            return
        }
        initialPresentationInputReadinessObservationOwner?
            .cancel()
        let mode = evidence.candidate.mode
        let runtimeProjectionService =
            panelController.modelForTesting
                .runtimeProjectionService
        let owner =
            FlowTabUITestInitialPresentationInputReadinessObservationOwner(
                notificationNames:
                    initialPresentationNotificationRoutes(
                        mode: mode
                    ).map(\.name),
                notificationObject:
                    runtimeProjectionService as AnyObject,
                readback: {
                    FlowTabUITestInitialPresentationInputReadinessSnapshot(
                        panelController: panelController,
                        mode: mode
                    )
                }
            )
        initialPresentationInputReadinessObservationOwner = owner
        owner.start(
            baseline: baseline,
            expectedPresentationGeneration:
                panelController.presentationSessionGeneration,
            expectedSessionItemIDs:
                attempt.sessionItemIDs,
            expectedSelectedAppID: selectedAppID,
            watchdogInterval:
                FlowTabUITestInitialPresentationInputReadinessPolicy
                    .watchdog,
            triggerReadiness: {
                requestInitialPresentationReadiness(
                    runtimeProjectionService:
                        runtimeProjectionService,
                    mode: mode
                )
            },
            onResolved: {
                [weak owner, weak panelController]
                inputEvidence in
                guard let owner,
                      let panelController,
                      initialPresentationInputReadinessObservationOwner
                        === owner
                else {
                    return
                }
                initialPresentationInputReadinessObservationOwner = nil
                postInitialPresentationResolutionReadback(
                    evidence,
                    inputReadinessEvidence:
                        inputEvidence,
                    panelController: panelController,
                    route: route
                )
                RuntimeLog.info(
                    "UITest",
                    "initial presentation input ready "
                        + inputEvidence.logFields
                )
            },
            onWatchdog: {
                [weak owner, weak panelController]
                failure in
                guard let owner,
                      let panelController,
                      initialPresentationInputReadinessObservationOwner
                        === owner
                else {
                    return
                }
                initialPresentationInputReadinessObservationOwner = nil
                postInitialPresentationResolutionReadback(
                    evidence,
                    inputReadinessEvidence:
                        failure.finalEvidence,
                    panelController: panelController,
                    route: route
                )
                RuntimeLog.error(
                    "UITest",
                    "initial presentation input readiness watchdog "
                        + failure.logFields
                )
            }
        )
    }

    private static func postInitialPresentationResolutionReadback(
        _ evidence:
            FlowTabUITestInitialPresentationEvidence,
        inputReadinessEvidence:
            FlowTabUITestInitialPresentationInputReadinessEvidence,
        panelController: SwitcherPanelController,
        route:
            FlowTabUITestInitialPresentationResolutionRoute
    ) {
        guard let readback =
                FlowTabUITestInitialPresentationResolutionReadback(
                    evidence: evidence,
                    inputReadinessEvidence:
                        inputReadinessEvidence,
                    panelController: panelController
                )
        else {
            RuntimeLog.error(
                "UITest",
                "initial presentation resolution readback "
                    + "missing input-readiness evidence "
                    + inputReadinessEvidence.logFields
            )
            return
        }
        FlowTabUITestInitialPresentationResolutionTransport
            .post(readback, route: route)
    }
}

private extension FlowTabUITestInitialPresentationEvidence {
    func confirmingSearchActivation()
        -> FlowTabUITestInitialPresentationEvidence
    {
        let confirmedAttempt = attempt.map {
            FlowTabUITestInitialPresentationAttempt(
                didPresent: $0.didPresent,
                sessionItemIDs: $0.sessionItemIDs,
                searchIsActiveOrPending: true
            )
        }
        return FlowTabUITestInitialPresentationEvidence(
            observationGeneration: observationGeneration,
            baseline: baseline,
            source: source,
            candidate: candidate,
            attempt: confirmedAttempt,
            postPresentationReadback:
                postPresentationReadback,
            resolution: resolution
        )
    }
}
#endif
