#if FLOWTAB_TESTING
import AppKit
import Combine
import Foundation

@MainActor
enum AppPanelPressureEvidenceTransport {
    enum StageKey {
        static let triggerDispatch = "trigger_dispatch_ms"
        static let mainPreparation = "main_preparation_ms"
        static let sessionProjection = "session_projection_ms"
        static let sessionRecency = "session_recency_ms"
        static let sessionBuild = "session_build_ms"
        static let sessionIndex = "session_index_ms"
        static let sessionPublish = "session_publish_ms"
        static let sessionDirectoryRefresh =
            "session_directory_refresh_ms"
        static let sessionInvalidation =
            "session_invalidation_ms"
        static let sessionStateReset =
            "session_state_reset_ms"
        static let sessionLoadWrapper =
            "session_load_wrapper_ms"
        static let sessionMaintenanceRequest =
            "session_maintenance_request_ms"
        static let sessionControllerWrapper =
            "session_controller_wrapper_ms"
        static let screenResolve = "screen_resolve_ms"
        static let panelSize = "panel_size_ms"
        static let panelCenter = "panel_center_ms"
        static let accessibilitySync = "accessibility_sync_ms"
        static let presentationLevel = "presentation_level_ms"
        static let initialVisibilityTracking =
            "initial_visibility_tracking_ms"
        static let makeKey = "make_key_and_order_front_ms"
        static let orderRegardless = "order_front_regardless_ms"
        static let firstMakeKey =
            "first_make_key_and_order_front_ms"
        static let firstOrderRegardless =
            "first_order_front_regardless_ms"
        static let secondMakeKey =
            "second_make_key_and_order_front_ms"
        static let secondOrderRegardless =
            "second_order_front_regardless_ms"
        static let hideNonPanelWindows =
            "hide_non_panel_windows_ms"
        static let presentationReadback =
            "presentation_visibility_readback_ms"
        static let monitorInstall = "monitor_install_ms"
        static let autoEnterSchedule = "auto_enter_schedule_ms"
        static let presentationWrapper =
            "presentation_wrapper_ms"
        static let nextMainTurn = "next_main_turn_ms"
        static let layout = "layout_ms"
        static let display = "display_ms"
        static let visibilityPollWait =
            "visibility_poll_wait_ms"
        static let visibilityReadback =
            "visibility_readback_ms"
        static let visibilityWait = "visibility_wait_ms"
        static let commandReturn = "command_return_ms"
        static let firstContentDraw =
            "first_content_draw_ms"
        static let panelExpose = "panel_expose_ms"
        static let occlusionVisible =
            "occlusion_visible_ms"
        static let windowReadinessRead =
            "window_readiness_read_ms"
        static let windowMaintenanceWait =
            "window_maintenance_wait_ms"
        static let windowSessionSwitch =
            "window_session_switch_ms"
        static let windowContentDraw =
            "window_content_draw_ms"
        static let searchDebounce = "search_debounce_ms"
        static let searchComputation =
            "search_computation_ms"
        static let searchResultsPublish =
            "search_results_publish_ms"
        static let searchShellDraw =
            "search_shell_draw_ms"
        static let searchFirstRowDraw =
            "search_first_row_draw_ms"

        static let openPartition = [
            sessionDirectoryRefresh,
            sessionInvalidation,
            sessionStateReset,
            sessionProjection,
            sessionRecency,
            sessionBuild,
            sessionIndex,
            sessionPublish,
            sessionLoadWrapper,
            sessionMaintenanceRequest,
            sessionControllerWrapper,
            screenResolve,
            panelSize,
            panelCenter,
            accessibilitySync,
            presentationLevel,
            hideNonPanelWindows,
            initialVisibilityTracking,
            monitorInstall,
            firstMakeKey,
            firstOrderRegardless,
            secondMakeKey,
            secondOrderRegardless,
            presentationReadback,
            autoEnterSchedule,
            presentationWrapper,
            nextMainTurn,
            layout,
            display,
            visibilityPollWait,
            visibilityReadback
        ]
    }

    private static var nextSequence: UInt64 = 0
    private static var observations:
        [UInt64: EventObservation] = [:]
    static var pendingEvidenceDeliveries:
        [UInt64: AppPanelPressurePendingEvidenceDelivery] = [:]
    static var evidenceAcknowledgementToken:
        NSObjectProtocol?
    static var installedEvidenceAcknowledgementName:
        Notification.Name?
    static let evidenceDeliveryQueue = DispatchQueue(
        label: "FlowTab.AppPanelPressureEvidenceDelivery",
        qos: .utility
    )

    static func begin(
        _ phase: AppPanelPressureEvidencePhase,
        triggerReceivedAtNanoseconds: UInt64? = nil,
        mainActorEnteredAtNanoseconds: UInt64? = nil,
        completionRequirement:
            AppPanelPressureCompletionRequirement =
                .phaseDefault,
        panelController: SwitcherPanelController
    ) -> AppPanelPressureMeasurementToken? {
        guard notificationName != nil else { return nil }
        installEvidenceAcknowledgementObserverIfNeeded()
        nextSequence &+= 1
        let token = AppPanelPressureMeasurementToken(
            sequence: nextSequence,
            phase: phase,
            startedAtNanoseconds:
                DispatchTime.now().uptimeNanoseconds,
            triggerReceivedAtNanoseconds:
                triggerReceivedAtNanoseconds,
            mainActorEnteredAtNanoseconds:
                mainActorEnteredAtNanoseconds,
            completionRequirement: completionRequirement
        )
        let observation = EventObservation(
            token: token,
            panelController: panelController
        ) { evidence in
            observations[token.sequence] = nil
            publish(evidence)
        }
        observations[token.sequence] = observation
        observation.start()
        return token
    }

    static func completeAfterCommand(
        _ token: AppPanelPressureMeasurementToken?,
        panelController: SwitcherPanelController
    ) {
        guard let token else { return }
        observations[token.sequence]?.commandDidReturn(
            panelController: panelController
        )
    }

    @MainActor
    private final class EventObservation {
        private let token: AppPanelPressureMeasurementToken
        private weak var panelController: SwitcherPanelController?
        private let onFinish: (AppPanelPressureEvidence) -> Void
        private var notificationTokens: [NSObjectProtocol] = []
        private var cancellables: Set<AnyCancellable> = []
        private var renderObserverID: UUID?
        private var watchdogTask: Task<Void, Never>?
        private var fixedStageMetrics: [String: Double] = [:]
        private var commandReturnedAtNanoseconds: UInt64?
        private var didRecordNextMainTurn = false
        private var panelExposedAtNanoseconds: UInt64?
        private var occlusionVisibleAtNanoseconds: UInt64?
        private var appContentDrawAtMilliseconds: Double?
        private var windowContentDrawAtMilliseconds: Double?
        private var searchShellDrawAtMilliseconds: Double?
        private var searchFirstRowDrawAtMilliseconds: Double?
        private var searchResultsPublishedAtMilliseconds: Double?
        private var didFinish = false

        init(
            token: AppPanelPressureMeasurementToken,
            panelController: SwitcherPanelController,
            onFinish: @escaping (AppPanelPressureEvidence) -> Void
        ) {
            self.token = token
            self.panelController = panelController
            self.onFinish = onFinish
        }

        func start() {
            guard let panelController else { return }
            let center = NotificationCenter.default
            let panel = panelController.panel
            notificationTokens.append(
                center.addObserver(
                    forName: NSWindow.didExposeNotification,
                    object: panel,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.recordPanelExpose()
                    }
                }
            )
            notificationTokens.append(
                center.addObserver(
                    forName:
                        NSWindow
                            .didChangeOcclusionStateNotification,
                    object: panel,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.recordOcclusionIfVisible()
                    }
                }
            )
            notificationTokens.append(
                center.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: panel,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.evaluate()
                    }
                }
            )
            renderObserverID =
                panelController.addRenderMilestoneObserver {
                    [weak self] event in
                    self?.recordRenderMilestone(event)
                }

            let model = panelController.modelForTesting
            model.$session
                .dropFirst()
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await Task.yield()
                        self?.evaluate()
                    }
                }
                .store(in: &cancellables)
            model.$searchViewState
                .dropFirst()
                .sink { [weak self] state in
                    Task { @MainActor [weak self] in
                        self?.recordSearchPublicationIfNeeded(
                            state
                        )
                        await Task.yield()
                        self?.evaluate()
                    }
                }
                .store(in: &cancellables)
        }

        func commandDidReturn(
            panelController: SwitcherPanelController
        ) {
            guard !didFinish else { return }
            let returnedAtNanoseconds =
                DispatchTime.now().uptimeNanoseconds
            commandReturnedAtNanoseconds = returnedAtNanoseconds
            fixedStageMetrics =
                AppPanelPressureEvidenceTransport
                    .fixedStageMetrics(
                        token: token,
                        completionStartedAtNanoseconds:
                            returnedAtNanoseconds,
                        panelController: panelController
                    )
            recordOcclusionIfVisible(
                fallbackTimestamp: returnedAtNanoseconds
            )
            evaluate()
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, !self.didFinish else { return }
                self.didRecordNextMainTurn = true
                if self.token.phase == .opened {
                    self.fixedStageMetrics[StageKey.nextMainTurn] =
                        AppPanelPressureEvidenceTransport
                            .milliseconds(
                                from: returnedAtNanoseconds,
                                to: DispatchTime.now()
                                    .uptimeNanoseconds
                            )
                }
                self.evaluate()
            }
            watchdogTask = Task { @MainActor [weak self] in
                try? await Task.sleep(
                    nanoseconds: UInt64(
                        AppPanelPressureObservationPolicy
                            .watchdogMilliseconds
                            * 1_000_000
                    )
                )
                self?.finish(watchdogExpired: true)
            }
        }

        private func recordPanelExpose() {
            guard panelExposedAtNanoseconds == nil else { return }
            panelExposedAtNanoseconds =
                DispatchTime.now().uptimeNanoseconds
            evaluate()
        }

        private func recordOcclusionIfVisible(
            fallbackTimestamp: UInt64? = nil
        ) {
            guard occlusionVisibleAtNanoseconds == nil else {
                return
            }
            guard panelController?.isPanelVisibleToUser == true
            else { return }
            occlusionVisibleAtNanoseconds =
                fallbackTimestamp
                    ?? DispatchTime.now().uptimeNanoseconds
            evaluate()
        }

        private func recordRenderMilestone(
            _ event: SwitcherRenderMilestoneEvent
        ) {
            guard event.drawnAtMilliseconds
                    >= tokenStartedAtMilliseconds,
                  let model = panelController?.modelForTesting
            else {
                return
            }
            switch event.milestone {
            case .appContent:
                guard model.overlayStyle == .appAndWindow,
                      !model.isPreviewLayerMode,
                      !model.isSearchActive
                else {
                    return
                }
                appContentDrawAtMilliseconds =
                    appContentDrawAtMilliseconds
                        ?? event.drawnAtMilliseconds
            case .windowContent:
                guard model.isPreviewLayerMode
                        || model.isWindowOnlyOverlay
                else {
                    return
                }
                windowContentDrawAtMilliseconds =
                    windowContentDrawAtMilliseconds
                        ?? event.drawnAtMilliseconds
            case .searchShell:
                guard model.isSearchActive else { return }
                searchShellDrawAtMilliseconds =
                    searchShellDrawAtMilliseconds
                        ?? event.drawnAtMilliseconds
            case .searchFirstRow:
                guard model.isSearchActive,
                      !model.searchViewState.results.isEmpty
                else {
                    return
                }
                searchFirstRowDrawAtMilliseconds =
                    searchFirstRowDrawAtMilliseconds
                        ?? event.drawnAtMilliseconds
            }
            evaluate()
        }

        private func recordSearchPublicationIfNeeded(
            _ state: SwitcherSearchViewState
        ) {
            guard case .committedSearchResults(let query) =
                    token.completionRequirement,
                  state.resultsQuery == query,
                  !state.results.isEmpty,
                  searchResultsPublishedAtMilliseconds == nil
            else {
                return
            }
            searchResultsPublishedAtMilliseconds =
                panelController?.modelForTesting
                    .lastSearchResultPublicationDiagnostic?
                    .publishedAtMilliseconds
                    ?? ProcessInfo.processInfo.systemUptime
                        * 1_000
        }

        private func evaluate() {
            guard !didFinish,
                  commandReturnedAtNanoseconds != nil,
                  let panelController
            else {
                return
            }
            if token.phase == .opened,
               !didRecordNextMainTurn {
                return
            }
            if panelController.isPanelVisibleToUser {
                recordOcclusionIfVisible()
            }
            let model = panelController.modelForTesting
            let session = model.session
            let baseVisibleState =
                panelController.isPanelPresented
                    && panelController.isPanelVisibleToUser
                    && session?.selectedApp.id != nil
                    && (session?.apps.count ?? 0) > 1
            let satisfied: Bool
            switch token.completionRequirement {
            case .phaseDefault:
                switch token.phase {
                case .opened:
                    satisfied = baseVisibleState
                        && appContentDrawAtMilliseconds != nil
                        && occlusionVisibleAtNanoseconds != nil
                case .highlighted:
                    satisfied = baseVisibleState
                        && appContentDrawAtMilliseconds != nil
                case .closed:
                    satisfied =
                        !panelController.isPanelPresented
                            && !panelController
                                .isPanelVisibleToUser
                            && session == nil
                }
            case .windowLayer:
                satisfied = baseVisibleState
                    && model.isPreviewLayerMode
                    && session?.selectedWindow != nil
                    && windowContentDrawAtMilliseconds != nil
            case .searchReady:
                satisfied = baseVisibleState
                    && panelController.panel.isKeyWindow
                    && panelController.panel.firstResponder
                        is SearchSystemTextView
                    && model.isSearchActive
                    && model.isSearchInputFocused
                    && searchShellDrawAtMilliseconds != nil
                    && occlusionVisibleAtNanoseconds != nil
            case .committedSearchResults(let query):
                let searchState = model.searchViewState
                satisfied = baseVisibleState
                    && panelController.panel.isKeyWindow
                    && panelController.panel.firstResponder
                        is SearchSystemTextView
                    && searchState.isActive
                    && searchState.isInputFocused
                    && searchState.query == query
                    && searchState.resultsQuery == query
                    && !searchState.results.isEmpty
                    && searchResultsPublishedAtMilliseconds != nil
                    && searchFirstRowDrawAtMilliseconds != nil
            }
            guard satisfied else { return }
            finish(watchdogExpired: false)
        }

        private func finish(watchdogExpired: Bool) {
            guard !didFinish, let panelController else { return }
            didFinish = true
            let readbackStartedAtNanoseconds =
                DispatchTime.now().uptimeNanoseconds
            let session = panelController.modelForTesting.session
            let panelPresented = panelController.isPanelPresented
            let userVisible = panelController.isPanelVisibleToUser
            let selectedAppID = session?.selectedApp.id
            let appCount = session?.apps.count ?? 0
            let selectedWindowCount =
                session?.selectedApp.windows.count ?? 0
            let panelWidth = panelController.panel.frame.width
            let visibleFrameWidth = (
                panelController.activePresentationScreen
                    ?? panelController.panel.screen
                    ?? NSScreen.main
            )?.visibleFrame.width ?? 0
            let visibleHomeWindowCount = NSApp.windows.filter {
                $0.isVisible
                    && $0.identifier?.rawValue
                        == AppWindowCoordinator.homeWindowIdentifier
            }.count
            let readbackCompletedAtNanoseconds =
                DispatchTime.now().uptimeNanoseconds
            let elapsedMilliseconds: Double
            if watchdogExpired {
                elapsedMilliseconds =
                    AppPanelPressureEvidenceTransport
                        .milliseconds(
                            from: token.startedAtNanoseconds,
                            to: readbackCompletedAtNanoseconds
                        )
            } else {
                elapsedMilliseconds =
                    completionEventElapsedMilliseconds(
                        fallbackNanoseconds:
                            readbackCompletedAtNanoseconds
                    )
            }
            var stageMetrics = fixedStageMetrics
            appendEventMetrics(
                to: &stageMetrics,
                panelController: panelController
            )
            if token.phase == .opened {
                stageMetrics[StageKey.layout] = 0
                stageMetrics[StageKey.display] = 0
                stageMetrics[StageKey.visibilityPollWait] = 0
                stageMetrics[StageKey.visibilityReadback] =
                    AppPanelPressureEvidenceTransport
                        .milliseconds(
                            from: readbackStartedAtNanoseconds,
                            to: readbackCompletedAtNanoseconds
                        )
                let accountedMilliseconds =
                    StageKey.openPartition.reduce(0) {
                        $0 + (stageMetrics[$1] ?? 0)
                    }
                stageMetrics[StageKey.visibilityWait] = max(
                    0,
                    elapsedMilliseconds
                        - accountedMilliseconds
                )
            }
            let evidence = AppPanelPressureEvidence(
                sequence: token.sequence,
                phase: token.phase,
                elapsedMilliseconds: elapsedMilliseconds,
                panelPresented: panelPresented,
                userVisible: userVisible,
                selectedAppID: selectedAppID,
                appCount: appCount,
                selectedWindowCount: selectedWindowCount,
                panelWidth: panelWidth,
                visibleFrameWidth: visibleFrameWidth,
                visibleHomeWindowCount: visibleHomeWindowCount,
                completionRequirementSatisfied:
                    watchdogExpired ? false : true,
                stageMetrics: stageMetrics
            )
            if watchdogExpired {
                RuntimeLog.error(
                    .uiTest,
                    "app-panel pressure evidence watchdog "
                        + "sequence=\(token.sequence) "
                        + "phase=\(token.phase.rawValue) "
                        + "requirement=\(String(describing: token.completionRequirement)) "
                        + "panelPresented=\(panelPresented ? 1 : 0) "
                        + "userVisible=\(userVisible ? 1 : 0) "
                        + "panelKey=\(panelController.panel.isKeyWindow ? 1 : 0) "
                        + "appActive=\(panelController.isAppCurrentlyActive ? 1 : 0) "
                        + "searchActive=\(panelController.modelForTesting.isSearchActive ? 1 : 0) "
                        + "inputFocused=\(panelController.modelForTesting.isSearchInputFocused ? 1 : 0) "
                        + "firstResponder=\(panelController.panelFirstResponderDebugName()) "
                        + "appDraw=\(appContentDrawAtMilliseconds == nil ? 0 : 1) "
                        + "windowDraw=\(windowContentDrawAtMilliseconds == nil ? 0 : 1) "
                        + "searchShellDraw=\(searchShellDrawAtMilliseconds == nil ? 0 : 1) "
                        + "searchFirstRowDraw=\(searchFirstRowDrawAtMilliseconds == nil ? 0 : 1) "
                        + "occlusionVisible=\(occlusionVisibleAtNanoseconds == nil ? 0 : 1) "
                        + "nextMainTurn=\(didRecordNextMainTurn ? 1 : 0)"
                )
            }
            cleanup()
            onFinish(evidence)
        }

        private func appendEventMetrics(
            to metrics: inout [String: Double],
            panelController: SwitcherPanelController
        ) {
            metrics[StageKey.commandReturn] =
                elapsedMilliseconds(
                    atNanoseconds: commandReturnedAtNanoseconds
                )
            metrics[StageKey.panelExpose] =
                elapsedMilliseconds(
                    atNanoseconds: panelExposedAtNanoseconds
                )
            metrics[StageKey.occlusionVisible] =
                elapsedMilliseconds(
                    atNanoseconds:
                        occlusionVisibleAtNanoseconds
                )
            metrics[StageKey.windowContentDraw] =
                elapsedMilliseconds(
                    atMonotonicMilliseconds:
                        windowContentDrawAtMilliseconds
                )
            metrics[StageKey.searchShellDraw] =
                elapsedMilliseconds(
                    atMonotonicMilliseconds:
                        searchShellDrawAtMilliseconds
                )
            metrics[StageKey.searchFirstRowDraw] =
                elapsedMilliseconds(
                    atMonotonicMilliseconds:
                        searchFirstRowDrawAtMilliseconds
                )
            metrics[StageKey.searchResultsPublish] =
                elapsedMilliseconds(
                    atMonotonicMilliseconds:
                        searchResultsPublishedAtMilliseconds
                )

            let firstContentDraw: Double?
            switch token.completionRequirement {
            case .windowLayer:
                firstContentDraw =
                    windowContentDrawAtMilliseconds
            case .searchReady:
                firstContentDraw =
                    searchShellDrawAtMilliseconds
            case .committedSearchResults:
                firstContentDraw =
                    searchFirstRowDrawAtMilliseconds
            case .phaseDefault:
                firstContentDraw =
                    appContentDrawAtMilliseconds
            }
            metrics[StageKey.firstContentDraw] =
                elapsedMilliseconds(
                    atMonotonicMilliseconds: firstContentDraw
                )

            let model = panelController.modelForTesting
            if let diagnostic = model
                .lastSelectedAppWindowReadinessReadDiagnostic,
               diagnostic.finishedAtMilliseconds
                    >= tokenStartedAtMilliseconds {
                metrics[StageKey.windowReadinessRead] =
                    elapsedMilliseconds(
                        atMonotonicMilliseconds:
                            diagnostic.finishedAtMilliseconds
                    )
            }
            if let diagnostic = model
                .lastSelectedAppWindowMaintenanceWaitDiagnostic,
               diagnostic.finishedAtMilliseconds
                    >= tokenStartedAtMilliseconds {
                metrics[StageKey.windowMaintenanceWait] =
                    diagnostic.elapsedMilliseconds
            }
            if let switchedAtMilliseconds = model
                .lastSelectedAppWindowSessionSwitchAtMilliseconds,
               switchedAtMilliseconds
                    >= tokenStartedAtMilliseconds {
                metrics[StageKey.windowSessionSwitch] =
                    elapsedMilliseconds(
                        atMonotonicMilliseconds:
                            switchedAtMilliseconds
                    )
            }
            if case .committedSearchResults(let query) =
                    token.completionRequirement,
               let diagnostic = model
                    .lastSearchResultPublicationDiagnostic,
               diagnostic.query == query,
               diagnostic.publishedAtMilliseconds
                    >= tokenStartedAtMilliseconds {
                metrics[StageKey.searchDebounce] =
                    diagnostic.debounceMilliseconds
                metrics[StageKey.searchComputation] =
                    diagnostic.computationMilliseconds
            }
        }

        private var tokenStartedAtMilliseconds: Double {
            Double(token.startedAtNanoseconds) / 1_000_000
        }

        private func completionEventElapsedMilliseconds(
            fallbackNanoseconds: UInt64
        ) -> Double {
            let fallback =
                AppPanelPressureEvidenceTransport
                    .milliseconds(
                        from: token.startedAtNanoseconds,
                        to: fallbackNanoseconds
                    )
            let eventElapsedMilliseconds: Double
            switch token.completionRequirement {
            case .phaseDefault:
                switch token.phase {
                case .opened:
                    eventElapsedMilliseconds = max(
                        elapsedMilliseconds(
                            atMonotonicMilliseconds:
                                appContentDrawAtMilliseconds
                        ),
                        elapsedMilliseconds(
                            atNanoseconds:
                                occlusionVisibleAtNanoseconds
                        )
                    )
                case .highlighted:
                    eventElapsedMilliseconds = elapsedMilliseconds(
                        atMonotonicMilliseconds:
                            appContentDrawAtMilliseconds
                    )
                case .closed:
                    eventElapsedMilliseconds = elapsedMilliseconds(
                        atNanoseconds:
                            commandReturnedAtNanoseconds
                    )
                }
            case .windowLayer:
                eventElapsedMilliseconds = elapsedMilliseconds(
                    atMonotonicMilliseconds:
                        windowContentDrawAtMilliseconds
                )
            case .searchReady:
                eventElapsedMilliseconds = max(
                    elapsedMilliseconds(
                        atMonotonicMilliseconds:
                            searchShellDrawAtMilliseconds
                    ),
                    elapsedMilliseconds(
                        atNanoseconds:
                            occlusionVisibleAtNanoseconds
                        )
                )
            case .committedSearchResults:
                eventElapsedMilliseconds = max(
                    elapsedMilliseconds(
                        atMonotonicMilliseconds:
                            searchResultsPublishedAtMilliseconds
                    ),
                    elapsedMilliseconds(
                        atMonotonicMilliseconds:
                            searchFirstRowDrawAtMilliseconds
                        )
                )
            }
            return eventElapsedMilliseconds > 0
                ? eventElapsedMilliseconds
                : fallback
        }

        private func elapsedMilliseconds(
            atNanoseconds timestamp: UInt64?
        ) -> Double {
            AppPanelPressureEvidenceTransport.milliseconds(
                from: token.startedAtNanoseconds,
                to: timestamp
            )
        }

        private func elapsedMilliseconds(
            atMonotonicMilliseconds timestamp: Double?
        ) -> Double {
            guard let timestamp,
                  timestamp >= tokenStartedAtMilliseconds
            else {
                return 0
            }
            return timestamp - tokenStartedAtMilliseconds
        }

        private func cleanup() {
            watchdogTask?.cancel()
            watchdogTask = nil
            cancellables.removeAll()
            let center = NotificationCenter.default
            for notificationToken in notificationTokens {
                center.removeObserver(notificationToken)
            }
            notificationTokens.removeAll()
            if let renderObserverID {
                panelController?.removeRenderMilestoneObserver(
                    renderObserverID
                )
            }
            renderObserverID = nil
        }

        deinit {
            watchdogTask?.cancel()
        }
    }

}
#endif
