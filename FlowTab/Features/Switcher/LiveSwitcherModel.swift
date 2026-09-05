import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import Combine
import FlowTabCore

@MainActor
final class LiveSwitcherModel: ObservableObject {
    var sessionState: any SwitcherSessionManaging
    lazy var sessionResources: any SwitcherSessionResourceManaging = SwitcherSessionResources(model: self)
    private var sessionStateObservation: AnyCancellable?
    var sessionPublisher: AnyPublisher<SwitcherSession?, Never> { sessionState.publisher }
    var session: SwitcherSession? {
        get { sessionState.session }
        set { sessionState.publish(newValue) }
    }

    private func sessionDidPublish(previous oldValue: SwitcherSession?, current session: SwitcherSession?) {
        guard let session else {
            sessionAppsByID = [:]
            return
        }
        updateAppLayerRenderSnapshot(
            from: session,
            previousSession: oldValue
        )
        handleSessionPreviewSnapshotLifecycle(session)
        guard searchViewState.isActive else {
            return
        }
        sessionAppsByID = Dictionary(uniqueKeysWithValues: session.apps.map { ($0.id, $0) })
    }
    @Published var appGridTileSize: CGFloat = 68
    @Published var appGridSpacing: CGFloat = 10
    @Published var previewSectionHeight: CGFloat = 220
    @Published var overlayStyle: SwitcherOverlayStyle = .appAndWindow
    @Published var searchViewState: SwitcherSearchViewState = .inactive
    @Published var searchResultScrollRevision: UInt64 = 0
    @Published var searchLayoutMeasurements: SwitcherSearchLayoutMeasurements = .fallback
    @Published var terminatingAppID: String?
    @Published var appLayerRenderSnapshot:
        SwitcherAppLayerRenderSnapshot?

    let runtimeProjectionService: any RuntimeProjectionServing
    lazy var focusedWindowSession: any SwitcherFocusedWindowSessionStarting = SwitcherFocusedWindowSessionCoordinator(model: self)
    var activator: any WindowActivating
    let iconProvider = AppIconProvider()
    let searchCoordinator = SwitcherSearchCoordinator()
    let searchSchedulingOwner: SwitcherSearchSchedulingOwner
    let windowRecencyTracker: RuntimeWindowRecencyTracker
    var previewProviderResolver = WindowPreviewProviderResolver.default
    var previewBatchFactory: any SwitcherPreviewBatchCreating = SwitcherPreviewBatchFactory()
    let previewStorage = SwitcherPreviewStorage()
    let runtimeContextStore = SwitcherRuntimeContextStore()
    let previewPublication = SwitcherPreviewPublication()
    private var previewPublicationObservation: AnyCancellable?
    lazy var previewSession: any SwitcherPreviewSessionOperating = SwitcherPreviewSession(
        state: previewStorage, contexts: runtimeContextStore, publication: previewPublication
    )
    var previewImageCache: BoundedImageCache { previewStorage.previewImageCache }
    lazy var previewPlanner: any SwitcherPreviewPlanning = SwitcherPreviewPlanner(
        state: previewStorage, contexts: runtimeContextStore, previewSession: previewSession
    )

    var onSearchStateChanged: (() -> Void)?
    var onSessionLayoutChanged: (() -> Void)?
    var onWindowOnlyPreviewPreparationChanged: (() -> Void)?
    var onSearchResultScrollRequestForTesting: ((String) -> Void)?
    var activationOverride: ((ActivationTarget, [String: RuntimeAppContext]) -> Void)?
    var terminateRequestOverride: ((String) -> (sent: Bool, pid: pid_t))?
    var previewCaptureOverride: ((
        CGWindowID?,
        pid_t,
        String?,
        Bool
    ) -> (image: NSImage, resolvedWindowID: CGWindowID, titleBarStyle: WindowTitleBarStyleGuess?)?)?
    var previewCaptureBatchOverride: ((
        [RuntimeWindowPreviewProvider.CaptureRequest]
    ) -> [RuntimeWindowPreviewProvider.CaptureResult?])?
    var previewCaptureBatchOutcomeOverride: ((
        [RuntimeWindowPreviewProvider.CaptureRequest]
    ) -> [RuntimeWindowPreviewProvider.CaptureOutcome])?

    var sessionAppsByID: [String: AppSwitchCandidate] = [:]
    var committedSearchAppsByID: [String: AppSwitchCandidate] = [:]
    var preparedSearchIndexIdentity: PreparedSearchIndexIdentity?
    var runtimeContextsByID: [String: RuntimeAppContext] {
        get { runtimeContextStore.values }
        set { runtimeContextStore.values = newValue }
        _modify { yield &runtimeContextStore.values }
    }
    var rememberedWindowIDByAppID: [String: String] = [:]
    var autoEnterSuppressedAppID: String?
    var titleBarStyleInferenceEnabled = false
    var searchInputHasMarkedText = false
    var pendingTerminateRequest: PendingTerminateRequest?
    var terminateAppInstanceGeneration: UInt64 = 0
    var runtimeProjectionMaintenanceGeneration: UInt64 = 0
    var runtimeProjectionMaintenanceEnabled = true
    var deferredRuntimeProjectionMaintenanceDirection:
        CycleDirection?
    var selectedAppWindowProjectionGeneration: UInt64 = 0
    var selectedAppWindowProjectionPendingAppID: String?
    var switcherSessionGeneration: UInt64 = 0
    var sessionAppWindowReadiness: SessionAppWindowReadiness?
    var lastSelectedAppWindowReadinessReadDiagnostic:
        SelectedAppWindowReadinessReadDiagnostic?
    var selectedAppWindowMaintenanceWaitStartedAtMilliseconds:
        Double?
    var lastSelectedAppWindowMaintenanceWaitDiagnostic:
        SelectedAppWindowMaintenanceWaitDiagnostic?
    var lastSelectedAppWindowSessionSwitchAtMilliseconds:
        Double?
    var selectedAppWindowPriorityRequestIdentity:
        SessionAppWindowIdentity?
    var pendingManualWindowLayerEntryAppID: String?
    var lastProjectionInvalidationRecord: ProjectionInvalidationRecord?
    var lastRuntimeProjectionMaintenanceDiagnostic: RuntimeProjectionMaintenanceDiagnostic?
    var lastAppSwitcherSessionLoadDiagnostic: AppSwitcherSessionLoadDiagnostic?
    var lastAppSwitcherSessionStartDiagnostic: AppSwitcherSessionStartDiagnostic?
    var lastSearchIndexReadDiagnostic: SearchIndexReadDiagnostic?
    var lastSearchResultPublicationDiagnostic:
        SearchResultPublicationDiagnostic?
    var pendingSearchActivationAfterFreshnessBarrier = false

    init(
        windowRecencyTracker: RuntimeWindowRecencyTracker = .shared,
        runtimeProjectionService: any RuntimeProjectionServing =
            sharedRuntimeProjectionService,
        searchSchedulingOwner: SwitcherSearchSchedulingOwner? = nil,
        sessionState: (any SwitcherSessionManaging)? = nil,
        activator: (any WindowActivating)? = nil
    ) {
        self.sessionState = sessionState ?? SwitcherSessionState()
        self.activator = activator ?? RuntimeActivator()
        self.windowRecencyTracker = windowRecencyTracker
        self.runtimeProjectionService = runtimeProjectionService
        self.searchSchedulingOwner =
            searchSchedulingOwner ?? SwitcherSearchSchedulingOwner()
        self.activator.windowFocusVerifiedHandler = { [windowRecencyTracker, runtimeProjectionService] verification in
            windowRecencyTracker.recordVerifiedFocus(
                appID: verification.appID,
                windowID: verification.windowID,
                ownerPID: verification.ownerPID,
                cgWindowID: verification.targetCGWindowID,
                title: verification.title,
                frame: verification.frame,
                allowedActions: verification.allowedActions
            )
            runtimeProjectionService.signalWindowFocusVerified(verification)
        }
        self.activator.windowFocusReadbackMismatchHandler = { [runtimeProjectionService] diagnostic in
            runtimeProjectionService.signalWindowFocusReadbackMismatch(diagnostic)
        }
        self.sessionState.didPublish = { [weak self] previous, current in
            self?.sessionDidPublish(previous: previous, current: current)
        }
        sessionStateObservation = self.sessionState.willChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        previewPublicationObservation = previewPublication.changes.sink { [weak self] in
            self?.objectWillChange.send()
        }
        previewPublication.preparationChanged = { [weak self] in
            self?.onWindowOnlyPreviewPreparationChanged?()
        }
    }

    func signalSpaceTopologyChanged() {
        runtimeProjectionService.signalSpaceTopologyChanged()
    }

    var appCount: Int {
        session?.apps.count ?? 0
    }

    var previewWindowCount: Int {
        guard let session else { return 0 }
        guard case .windowCycle(let appID) = session.mode else { return 0 }
        guard let app = session.apps.first(where: { $0.id == appID }) else { return 0 }
        return app.windows.count
    }

    func updateAppGridLayout(tileSize: CGFloat, spacing: CGFloat) {
        let normalizedTileSize = max(1, min(90, tileSize))
        let normalizedSpacing = max(0, spacing)
        guard appGridTileSize != normalizedTileSize || appGridSpacing != normalizedSpacing else {
            return
        }
        appGridTileSize = normalizedTileSize
        appGridSpacing = normalizedSpacing
    }

    func updatePreviewSectionHeight(_ height: CGFloat) {
        let normalizedHeight = max(130, min(220, height))
        guard previewSectionHeight != normalizedHeight else { return }
        previewSectionHeight = normalizedHeight
    }

    func updateSearchLayoutMeasurements(_ measurements: SwitcherSearchLayoutMeasurements) {
        let normalized = measurements.normalized
        guard searchLayoutMeasurements.differsVisibly(from: normalized) else { return }
        searchLayoutMeasurements = normalized
        RuntimeLog.debug(
            .switcherLayout,
            "measuredSearchLayout header=\(formatLayoutPoint(normalized.presentationHeaderHeight)) row=\(formatLayoutPoint(normalized.resultRowHeight)) fallbackHeader=\(formatLayoutPoint(SwitcherSearchLayoutMeasurements.fallback.presentationHeaderHeight)) fallbackRow=\(formatLayoutPoint(SwitcherSearchLayoutMeasurements.fallback.resultRowHeight))"
        )
        onSearchStateChanged?()
    }

    var isPreviewLayerMode: Bool {
        guard let session else { return false }
        if case .windowCycle = session.mode {
            return true
        }
        return false
    }

    var isWindowOnlyOverlay: Bool {
        overlayStyle == .windowOnly
    }

    var isSearchActive: Bool {
        searchViewState.isActive
    }

    var isSearchInputFocused: Bool {
        searchViewState.isInputFocused
    }

    var hasMarkedSearchText: Bool {
        searchInputHasMarkedText
    }

    var searchScope: SwitcherSearchScope {
        searchViewState.scope
    }

    var searchResultCount: Int {
        searchViewState.results.count
    }

    var shouldClearSearchOnEscape: Bool {
        searchViewState.isInputFocused && !searchViewState.query.isEmpty
    }

    func recordSearchResultScrollRequestForTesting(_ resultID: String) {
        onSearchResultScrollRequestForTesting?(resultID)
    }

    func startSession(
        triggerDirection: CycleDirection,
        deferMaintenanceUntilFirstVisibleFrame: Bool = false
    ) -> Bool {
        lastAppSwitcherSessionLoadDiagnostic = nil
        let startMs = Self.monotonicMilliseconds()
        runtimeProjectionService.refreshApplicationDirectoryMembershipForPresentation()
        let directoryReadyMs = Self.monotonicMilliseconds()
        invalidateSelectedAppWindowProjection(reason: .startSession)
        let invalidationReadyMs = Self.monotonicMilliseconds()
        clearTerminateSelectedAppAnimation()
        overlayStyle = .appAndWindow
        titleBarStyleInferenceEnabled = false
        let stateReadyMs = Self.monotonicMilliseconds()
        let loaded = loadFastAppSwitcherProjectionSession(
            triggerDirection: triggerDirection,
            preferredSelectedAppID: nil
        )
        let projectionReadyMs = Self.monotonicMilliseconds()
        if loaded && deferMaintenanceUntilFirstVisibleFrame {
            deferRuntimeProjectionMaintenance(
                triggerDirection: triggerDirection
            )
        } else {
            requestRuntimeProjectionMaintenance(
                triggerDirection: triggerDirection
            )
        }
        let completeMs = Self.monotonicMilliseconds()
        lastAppSwitcherSessionStartDiagnostic =
            AppSwitcherSessionStartDiagnostic(
                result: loaded ? "ready" : "empty",
                directoryRefreshMs:
                    directoryReadyMs - startMs,
                invalidationMs:
                    invalidationReadyMs - directoryReadyMs,
                stateResetMs:
                    stateReadyMs - invalidationReadyMs,
                projectionLoadMs:
                    projectionReadyMs - stateReadyMs,
                maintenanceRequestMs:
                    completeMs - projectionReadyMs
            )
        return loaded
    }

    func terminateSelectedApp() -> TerminateSelectedAppResult {
        guard let currentSession = session else { return .notHandled }

        let selectedApp = currentSession.selectedApp
        guard let terminateRequest = makeTerminateRequest(forAppID: selectedApp.id) else {
            return .notHandled
        }
        let preferredSelectedAppID = preferredAppIDAfterRemovingSelectedApp(from: currentSession)
        let terminatingPID = terminateRequest.pid
        let sent = terminateRequest.sent
        let terminateLogMessage = "terminate request app=\(selectedApp.displayName) appID=\(selectedApp.id) sent=\(sent)"
        guard sent else {
            RuntimeLog.error(.session, terminateLogMessage)
            return .notHandled
        }
        RuntimeLog.info(.session, terminateLogMessage)

        terminateAppInstanceGeneration &+= 1
        let request = PendingTerminateRequest(
            appID: selectedApp.id,
            pid: terminatingPID,
            generation: terminateAppInstanceGeneration,
            preferredSelectedAppID: preferredSelectedAppID
        )
        pendingTerminateRequest = request
        terminatingAppID = selectedApp.id
        runtimeProjectionService.requestAppSwitcherProjectionMaintenance(reason: .appLifecycleRefresh)
        return .updatedSession
    }

    func restoreSearchStateAfterProjectionRefreshIfNeeded(
        _ previousState: SwitcherSearchViewState
    ) {
        guard previousState.isActive else { return }
        guard searchCoordinator.activate(defaultScope: previousState.scope) else { return }
        if !previousState.query.isEmpty {
            _ = searchCoordinator.replaceQueryWithoutRebuild(
                previousState.query,
                cursorPosition: previousState.queryCursorPosition
            )
        }
        if !previousState.isInputFocused {
            _ = searchCoordinator.focusResults()
        }
        scheduleSearchComputation(resetSelection: true, debounced: false)
    }

    @discardableResult
    func handleWorkspaceApplicationDidTerminate(_ notification: Notification) -> Bool {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else {
            return false
        }
        let appID = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        return handleApplicationTerminated(appID: appID, pid: app.processIdentifier)
    }

    @discardableResult
    func handleApplicationTerminated(appID: String, pid: pid_t) -> Bool {
        refreshSessionAfterTerminatedApplication(appID: appID, pid: pid, reason: "workspace_notification")
    }

    @discardableResult
    func handleAppSwitcherProjectionDidUpdate() -> Bool {
        guard session != nil else { return false }
        return refreshSelectedAppWindowReadiness()
    }

    @discardableResult
    func handleCurrentAppWindowProjectionDidUpdate(appID: String?) -> Bool {
        guard let currentSession = session else { return false }
        guard !searchViewState.isActive else { return false }
        guard case .appCycle = currentSession.mode else { return false }
        let targetAppID = appID ?? currentSession.selectedApp.id
        guard targetAppID == currentSession.selectedApp.id else {
            return false
        }
        return refreshSelectedAppWindowReadiness()
    }

    func isPresentingWindowLayerSnapshot(_ session: SwitcherSession) -> Bool {
        if case .windowCycle = session.mode {
            return true
        }
        return false
    }

    @discardableResult
    func refreshSessionAfterTerminatedApplication(appID: String, pid: pid_t, reason: String) -> Bool {
        guard session != nil else { return false }

        let pendingRequest = pendingTerminateRequest
        let matchesPending = pendingRequest?.matchesTerminatedInstance(appID: appID, pid: pid) == true
        let appPresentInSessionByID = session?.apps.contains(where: { $0.id == appID }) == true
        let appPresentInSessionByPID = runtimeContextsByID.values.contains {
            $0.runningApp.processIdentifier == pid
        }
        guard matchesPending || appPresentInSessionByID || appPresentInSessionByPID else {
            return false
        }

        if matchesPending {
            pendingTerminateRequest = nil
        }
        runtimeProjectionService.signalAppTerminated(appID: appID, pid: pid)
        let refreshed = loadAppSwitcherProjectionSession(
            triggerDirection: .forward,
            preferredSelectedAppID: matchesPending ? pendingRequest?.preferredSelectedAppID : nil,
            animateAppStripUpdate: true,
            preserveSearchState: searchViewState.isActive,
            resetWhenEmpty: false,
            removingTerminatedAppID: appID,
            terminatedPID: pid
        )
        RuntimeLog.info(
            .session,
            "terminate post-refresh reason=\(reason) appID=\(appID) pid=\(pid) matchedPending=\(matchesPending ? 1 : 0) pendingGeneration=\(pendingRequest?.generation.description ?? "nil") refreshed=\(refreshed)"
        )
        if matchesPending, let pendingRequest, terminatingAppID == pendingRequest.appID {
            terminatingAppID = nil
        }
        onSessionLayoutChanged?()
        return refreshed
    }

    func preferredAppIDAfterRemovingSelectedApp(from session: SwitcherSession) -> String? {
        guard session.apps.count > 1 else { return nil }
        let remainingAppIDs = session.apps.map(\.id).filter { $0 != session.selectedApp.id }
        guard !remainingAppIDs.isEmpty else { return nil }
        let preferredIndex = min(session.selectedAppIndex, remainingAppIDs.count - 1)
        return remainingAppIDs[preferredIndex]
    }

    func handle(_ keyInput: KeyInput) {
        guard !searchViewState.isActive else { return }
        guard var session else { return }
        let previousMode = session.mode
        let previousAppID = session.selectedApp.id
        guard let updatedSession = sessionState.applying(keyInput) else { return }
        session = updatedSession

        let currentAppID = session.selectedApp.id
        if currentAppID != previousAppID {
            autoEnterSuppressedAppID = nil
            pendingManualWindowLayerEntryAppID = nil
            resetSelectedAppWindowReadinessForSelectionChange()
        }

        if
            case .windowCycle(let appID) = previousMode,
            case .appCycle = session.mode,
            keyInput == .upArrow
        {
            autoEnterSuppressedAppID = appID
        }

        if
            case .appCycle = previousMode,
            case .windowCycle = session.mode,
            keyInput == .downArrow
        {
            autoEnterSuppressedAppID = nil
            pendingManualWindowLayerEntryAppID = nil
        } else if
            case .appCycle = previousMode,
            case .appCycle = session.mode,
            keyInput == .downArrow,
            currentAppID == previousAppID,
            session.selectedApp.windows.isEmpty
        {
            pendingManualWindowLayerEntryAppID = currentAppID
            RuntimeLog.debug(
                .projection,
                "manualWindowLayerEntry result=pending appID=\(currentAppID)"
            )
        }
        self.session = session
    }

    @discardableResult
    func selectAppFromPointer(appID: String) -> Bool {
        guard !searchViewState.isActive else { return false }
        guard var session else { return false }
        let previousAppID = session.selectedApp.id
        guard session.selectApp(withID: appID) else { return false }
        if session.selectedApp.id != previousAppID {
            autoEnterSuppressedAppID = nil
            pendingManualWindowLayerEntryAppID = nil
            resetSelectedAppWindowReadinessForSelectionChange()
        }
        self.session = session
        return true
    }

    @discardableResult
    func selectWindowFromPointer(appID: String, windowID: String) -> Bool {
        guard !searchViewState.isActive else { return false }
        guard var session else { return false }
        let previousAppID = session.selectedApp.id
        guard session.selectWindow(appID: appID, windowID: windowID) else { return false }
        if session.selectedApp.id != previousAppID {
            autoEnterSuppressedAppID = nil
            pendingManualWindowLayerEntryAppID = nil
        }
        self.session = session
        return true
    }

    func prepareTerminateSelectedAppAnimation() -> Bool {
        guard let session else { return false }
        terminatingAppID = session.selectedApp.id
        return true
    }

    func clearTerminateSelectedAppAnimation() {
        pendingTerminateRequest = nil
        terminatingAppID = nil
    }

    @discardableResult
    func autoEnterWindowLayerIfPossible() -> Bool {
        guard !pendingSearchActivationAfterFreshnessBarrier,
              let session,
              autoEnterSuppressedAppID != session.selectedApp.id
        else {
            return false
        }
        return enterSelectedAppWindowLayerUsingCurrentReadiness()
            == .entered
    }

    func debugSelectionSummary() -> String {
        guard let session else { return "session=nil" }
        return "app=\(session.selectedApp.displayName) windows=\(session.selectedApp.windows.count) mode=\(session.mode.debugName)"
    }

    func commitSelection() {
        guard let resolution = sessionState.resolvingSelection() else { return }
        let session = resolution.session
        let target = resolution.target
        rememberedWindowIDByAppID = session.rememberedWindowIDByAppID
        recordCommittedSelectionRecencyIfNeeded(target)
        invalidateRuntimeProjectionMaintenanceRequest(reason: .commitSelection)
        clearTerminateSelectedAppAnimation()
        cancelPendingSearchComputation()
        pendingSearchActivationAfterFreshnessBarrier = false
        self.session = nil
        resetSessionAppWindowReadinessTracking()
        _ = searchCoordinator.exit()
        publishSearchStateIfNeeded()

        guard let target else {
            overlayStyle = .appAndWindow
            resetRuntimeState()
            return
        }
        if let activationOverride {
            activationOverride(target, runtimeContextsByID)
        } else {
            activator.activate(target: target, contextsByID: runtimeContextsByID)
        }
        overlayStyle = .appAndWindow
        resetRuntimeState()
    }

    private func recordCommittedSelectionRecencyIfNeeded(_ target: ActivationTarget?) {
        guard
            case .window(let appID, let windowID, _) = target,
            let context = runtimeContextsByID[appID]
        else {
            return
        }
        windowRecencyTracker.recordSelectedWindow(
            appID: appID,
            windowID: windowID,
            context: context
        )
    }

    func cancelSelection() {
        resetSessionState()
    }

    func resetSessionState() {
        sessionResources.resetSession()
    }

    func resetRuntimeState() {
        sessionResources.resetRuntime()
    }

    func appSwitcherPayloadWithWindowRecencyApplied(
        _ payload: AppSwitcherProjectionSessionPayload
    ) -> AppSwitcherProjectionSessionPayload {
        AppSwitcherProjectionSessionPayload(
            apps: windowRecencyTracker.appsWithRecencyApplied(
                payload.apps,
                contextsByID: payload.contextsByID
            ),
            contextsByID: payload.contextsByID
        )
    }

    func currentAppWindowPayloadWithWindowRecencyApplied(
        _ payload: RuntimeCurrentAppWindowPayload
    ) -> RuntimeCurrentAppWindowPayload {
        return windowRecencyTracker.currentAppWindowPayloadWithRecencyApplied(payload)
    }

    func makeTerminateRequest(forAppID appID: String) -> (sent: Bool, pid: pid_t)? {
        if let terminateRequestOverride {
            return terminateRequestOverride(appID)
        }
        guard let context = runtimeContextsByID[appID] else { return nil }
        return (
            sent: context.runningApp.terminate(),
            pid: context.runningApp.processIdentifier
        )
    }

}

private extension SwitcherSearchLayoutMeasurements {
    func differsVisibly(from other: SwitcherSearchLayoutMeasurements) -> Bool {
        abs(presentationHeaderHeight - other.presentationHeaderHeight) > 0.5
            || abs(resultRowHeight - other.resultRowHeight) > 0.5
    }
}

func formatLayoutPoint(_ value: CGFloat) -> String {
    String(format: "%.2f", Double(value))
}
