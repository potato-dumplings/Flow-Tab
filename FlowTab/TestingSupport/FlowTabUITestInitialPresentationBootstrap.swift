#if FLOWTAB_TESTING
import Foundation

private enum FlowTabUITestInitialPresentationPolicy {
    static let watchdog: TimeInterval = 3
}

@MainActor
extension FlowTabUITestBootstrapper {
    static var isObservingInitialPresentationForTesting:
        Bool
    {
        initialPresentationObservationOwner?
            .isObserving == true
            || initialSearchActivationObservationOwner?
                .isObserving == true
    }

    static func presentInitialUIIfNeeded(
        panelController: SwitcherPanelController
    ) {
        guard FlowTabTestLaunchOptions
                .opensSwitcherOnLaunch
        else {
            stopInitialUIPresentationObservation()
            return
        }
        stopInitialUIPresentationObservation()
        panelController
            .setModifierReleaseConfirmationSuppressedForTesting(
                true
            )

        let mode = initialPresentationMode
        let runtimeProjectionService =
            panelController.modelForTesting
                .runtimeProjectionService
        let shouldActivateInitialSearch =
            FlowTabTestLaunchOptions.entersSearchOnLaunch
            && panelController.searchFeatureEnabled
        prepareInitialSearchActivationIfNeeded(
            panelController: panelController,
            runtimeProjectionService:
                runtimeProjectionService,
            shouldActivateSearch:
                shouldActivateInitialSearch
        )
        let observationOwner =
            FlowTabUITestInitialPresentationObservationOwner(
                notificationRoutes:
                    initialPresentationNotificationRoutes(
                        mode: mode
                    ),
                notificationObject:
                    runtimeProjectionService as AnyObject
            ) { [weak panelController] in
                guard let panelController else {
                    return missingInitialPresentationSnapshot(
                        mode: mode
                    )
                }
                return initialPresentationSnapshot(
                    panelController:
                        panelController,
                    mode: mode
                )
            }
        initialPresentationObservationOwner =
            observationOwner

        observationOwner.start(
            watchdogInterval:
                FlowTabUITestInitialPresentationPolicy
                    .watchdog
        ) {
            requestInitialPresentationReadiness(
                runtimeProjectionService:
                    runtimeProjectionService,
                mode: mode
            )
        } attemptPresentation: {
            [weak panelController] _ in
            guard let panelController else {
                return FlowTabUITestInitialPresentationAttempt(
                    didPresent: false,
                    sessionItemIDs: [],
                    searchIsActiveOrPending: false
                )
            }
            let didPresent = presentLaunchSwitcher(
                panelController:
                    panelController,
                mode: mode
            )
            return FlowTabUITestInitialPresentationAttempt(
                didPresent: didPresent,
                sessionItemIDs:
                    initialPresentationSessionItemIDs(
                        panelController:
                            panelController,
                        mode: mode
                    ),
                searchIsActiveOrPending:
                    panelController.modelForTesting
                        .isSearchActive
                    || panelController.modelForTesting
                        .pendingSearchActivationAfterFreshnessBarrier
            )
        } cancelPresentation: {
            [weak panelController] in
            panelController?
                .cancelSelectionForTesting()
        } onResolved: {
            [weak observationOwner, weak panelController] evidence in
            guard let observationOwner,
                  let panelController
            else {
                return
            }
            resolveInitialPresentation(
                evidence,
                observationOwner: observationOwner,
                panelController: panelController,
                shouldActivateSearch:
                    shouldActivateInitialSearch
            )
        } onWatchdog: {
            [weak observationOwner] failure in
            guard let observationOwner,
                  initialPresentationObservationOwner
                    === observationOwner
            else {
                return
            }
            initialPresentationObservationOwner = nil
            stopInitialSearchActivationObservation()
            RuntimeLog.error(
                "UITest",
                "initial presentation watchdog "
                    + failure.logFields
            )
        }
    }

    static func stopInitialUIPresentationObservation() {
        initialPresentationObservationOwner?
            .cancel()
        initialPresentationObservationOwner = nil
        stopInitialSearchActivationObservation()
    }

    private static var initialPresentationMode:
        FlowTabUITestInitialPresentationMode
    {
        FlowTabTestLaunchOptions
            .opensInAppWindowSwitcherOnLaunch
        ? .inAppWindow
        : .global
    }

    private static func initialPresentationNotificationRoutes(
        mode: FlowTabUITestInitialPresentationMode
    ) -> [FlowTabUITestInitialPresentationNotificationRoute] {
        switch mode {
        case .global:
            return [
                .init(
                    name:
                        .runtimeAppSwitcherProjectionDidUpdate,
                    source:
                        .appSwitcherProjectionDidUpdate
                )
            ]
        case .inAppWindow:
            return [
                .init(
                    name:
                        .runtimeCurrentAppWindowProjectionDidUpdate,
                    source:
                        .currentAppWindowProjectionDidUpdate
                ),
                .init(
                    name:
                        .runtimeAppSwitcherProjectionDidUpdate,
                    source:
                        .appSwitcherProjectionDidUpdate
                )
            ]
        }
    }

    private static func requestInitialPresentationReadiness(
        runtimeProjectionService:
            any RuntimeProjectionServing,
        mode: FlowTabUITestInitialPresentationMode
    ) {
        switch mode {
        case .global:
            runtimeProjectionService
                .requestAppSwitcherProjectionMaintenance(
                    reason: .switcherSessionStarted
                )
        case .inAppWindow:
            runtimeProjectionService
                .signalFocusedCurrentAppWindowsChanged()
        }
    }

    private static func presentLaunchSwitcher(
        panelController: SwitcherPanelController,
        mode: FlowTabUITestInitialPresentationMode
    ) -> Bool {
        installInitialPanelOcclusionStaleOverrideIfNeeded(
            panelController: panelController
        )
        switch mode {
        case .global:
            return panelController
                .presentGlobalHotkeySessionForTesting()
        case .inAppWindow:
            return panelController
                .presentInAppWindowHotkeySessionForTesting()
        }
    }

    private static func initialPresentationSessionItemIDs(
        panelController: SwitcherPanelController,
        mode: FlowTabUITestInitialPresentationMode
    ) -> [String] {
        guard let session =
                panelController.modelForTesting.session
        else {
            return []
        }
        switch mode {
        case .global:
            return session.apps.map(\.id)
        case .inAppWindow:
            return session.apps.flatMap {
                [$0.id] + $0.windows.map(\.id)
            }
        }
    }

    private static func initialPresentationSnapshot(
        panelController: SwitcherPanelController,
        mode: FlowTabUITestInitialPresentationMode
    ) -> FlowTabUITestInitialPresentationSnapshot {
        let model = panelController.modelForTesting
        switch mode {
        case .global:
            guard let projection =
                    model.runtimeProjectionService
                        .readAppSwitcherProjection()
            else {
                return missingInitialPresentationSnapshot(
                    mode: mode
                )
            }
            let payload =
                model.appSwitcherPayloadWithHiddenAppsFiltered(
                    model
                        .appSwitcherPayloadWithWindowRecencyApplied(
                            AppSwitcherProjectionSessionPayload(
                                projection: projection
                            )
                        )
                )
            return makeInitialPresentationSnapshot(
                mode: mode,
                freshness: projection.freshness,
                processIdentifier: nil,
                itemIDs: payload.apps.map(\.id)
            )
        case .inAppWindow:
            guard let focusedRead =
                    model.runtimeProjectionService
                        .readFocusedCurrentAppWindowProjection(),
                  let projection =
                    focusedRead.projection
            else {
                return missingInitialPresentationSnapshot(
                    mode: mode
                )
            }
            let payload =
                model
                    .currentAppWindowPayloadWithWindowRecencyApplied(
                        projection
                            .currentAppWindowPayload
                    )
            return makeInitialPresentationSnapshot(
                mode: mode,
                freshness: projection.freshness,
                processIdentifier: focusedRead.pid,
                itemIDs:
                    [focusedRead.appID]
                    + payload.candidate.windows.map(\.id)
            )
        }
    }

    private static func makeInitialPresentationSnapshot(
        mode: FlowTabUITestInitialPresentationMode,
        freshness: RuntimeProjectionFreshness,
        processIdentifier: pid_t?,
        itemIDs: [String]
    ) -> FlowTabUITestInitialPresentationSnapshot {
        FlowTabUITestInitialPresentationSnapshot(
            mode: mode,
            projectionIsPresent: true,
            projectionIsComplete:
                freshness.isCompleteForScope,
            sourceGeneration:
                freshness.sourceGeneration,
            processIdentifier: processIdentifier,
            itemIDs: itemIDs,
            dirtyAppIDs: freshness.dirtyAppIDs,
            dirtyPIDs: freshness.dirtyPIDs,
            dirtyCGWindowIDs:
                freshness.dirtyCGWindowIDs,
            pendingRepairScopes:
                freshness.pendingRepairScopes
        )
    }

    private static func missingInitialPresentationSnapshot(
        mode: FlowTabUITestInitialPresentationMode
    ) -> FlowTabUITestInitialPresentationSnapshot {
        FlowTabUITestInitialPresentationSnapshot(
            mode: mode,
            projectionIsPresent: false,
            projectionIsComplete: false,
            sourceGeneration: nil,
            processIdentifier: nil,
            itemIDs: [],
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: []
        )
    }
}
#endif
