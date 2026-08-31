import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

@MainActor
final class LiveSwitcherModel: ObservableObject {
    enum TerminateSelectedAppResult {
        case notHandled
        case updatedSession
        case sessionEnded
    }

    struct PendingTerminateRequest: Equatable {
        struct AppInstanceIdentity: Equatable {
            let appID: String
            let pid: pid_t
            let generation: UInt64

            func matchesTerminatedInstance(appID: String, pid: pid_t) -> Bool {
                self.appID == appID && self.pid == pid
            }
        }

        let appInstance: AppInstanceIdentity
        let preferredSelectedAppID: String?

        var appID: String {
            appInstance.appID
        }

        var pid: pid_t {
            appInstance.pid
        }

        var generation: UInt64 {
            appInstance.generation
        }

        init(
            appID: String,
            pid: pid_t,
            generation: UInt64,
            preferredSelectedAppID: String?
        ) {
            appInstance = AppInstanceIdentity(
                appID: appID,
                pid: pid,
                generation: generation
            )
            self.preferredSelectedAppID = preferredSelectedAppID
        }

        func matchesTerminatedInstance(appID: String, pid: pid_t) -> Bool {
            appInstance.matchesTerminatedInstance(appID: appID, pid: pid)
        }
    }

    enum ProjectionInvalidationReason: String, Equatable {
        case startSession
        case startFocusedWindowSession
        case commitSelection
        case resetSession
        case resetRuntimeState
        case explicitRuntimeProjectionMaintenanceInvalidation
        case explicitSelectedAppWindowProjectionInvalidation
    }

    enum ProjectionInvalidationScope: String, Equatable {
        case runtimeProjectionMaintenance
        case selectedAppWindowProjection
    }

    struct ProjectionInvalidationRecord: Equatable {
        let reason: ProjectionInvalidationReason
        let scope: ProjectionInvalidationScope
        let maintenanceGeneration: UInt64
        let selectedAppWindowProjectionGeneration: UInt64
        let clearedDeferredMaintenanceRequest: Bool

        var logMessage: String {
            [
                "projectionInvalidation",
                "scope=\(scope.rawValue)",
                "reason=\(reason.rawValue)",
                "maintenanceGeneration=\(maintenanceGeneration)",
                "selectedAppWindowProjectionGeneration=\(selectedAppWindowProjectionGeneration)",
                "clearedDeferredMaintenanceRequest=\(clearedDeferredMaintenanceRequest ? 1 : 0)"
            ].joined(separator: " ")
        }
    }

    struct RuntimeProjectionMaintenanceDiagnostic: Equatable {
        let result: String
        let generation: UInt64
        let currentGeneration: UInt64
        let reason: ProjectionInvalidationReason
        let trigger: String
        let applyGeneration: UInt64?
        let totalMs: String

        var logMessage: String {
            [
                "runtimeProjectionMaintenance",
                "result=\(result)",
                "generation=\(generation)",
                "currentGeneration=\(currentGeneration)",
                "reason=\(reason.rawValue)",
                "trigger=\(trigger)",
                "applyGeneration=\(applyGeneration.map(String.init) ?? "nil")",
                "totalMs=\(totalMs)"
            ].joined(separator: " ")
        }
    }

    struct AppSwitcherSessionLoadDiagnostic: Equatable {
        let result: String
        let event: String
        let trigger: String
        let appCount: Int
        let windowCount: Int
        let projectionMs: Double
        let recencyMs: Double
        let sessionBuildMs: Double
        let indexMs: Double
        let publishMs: Double

        var totalMs: Double {
            projectionMs
                + recencyMs
                + sessionBuildMs
                + indexMs
                + publishMs
        }
    }

    struct AppSwitcherSessionStartDiagnostic: Equatable {
        let result: String
        let directoryRefreshMs: Double
        let invalidationMs: Double
        let stateResetMs: Double
        let projectionLoadMs: Double
        let maintenanceRequestMs: Double

        var totalMs: Double {
            directoryRefreshMs
                + invalidationMs
                + stateResetMs
                + projectionLoadMs
                + maintenanceRequestMs
        }
    }

    struct SearchIndexReadDiagnostic: Equatable {
        let reason: String
        let readiness: RuntimeSearchIndexReadiness
        let resultState: RuntimeSearchIndexResultState
        let appCount: Int
        let windowCount: Int
        let committedIndexCoversCurrentGeneration: Bool
        let dirtyAppCount: Int
        let dirtyPIDCount: Int
        let dirtyCGWindowIDCount: Int
        let pendingRepairScopeCount: Int
        let requestedFreshnessBarrier: Bool

        var searchTraceFields: String {
            [
                "searchIndexReadiness=\(readiness.rawValue)",
                "searchIndexResultState=\(resultState.rawValue)",
                "searchIndexDegraded=\(resultState == .degradedStaleCommittedResult ? 1 : 0)",
                "searchIndexCoversCurrentGeneration=\(committedIndexCoversCurrentGeneration ? 1 : 0)",
                "searchFreshnessBarrierRequested=\(requestedFreshnessBarrier ? 1 : 0)"
            ].joined(separator: " ")
        }

        var logMessage: String {
            [
                "searchIndexSource",
                "reason=\(reason)",
                "source=committedRuntimeIndex",
                "readiness=\(readiness.rawValue)",
                "resultState=\(resultState.rawValue)",
                "apps=\(appCount)",
                "windows=\(windowCount)",
                "committedIndexCoversCurrentGeneration=\(committedIndexCoversCurrentGeneration ? 1 : 0)",
                "degraded=\(resultState == .degradedStaleCommittedResult ? 1 : 0)",
                "dirtyApps=\(dirtyAppCount)",
                "dirtyPIDs=\(dirtyPIDCount)",
                "dirtyCGWindowIDs=\(dirtyCGWindowIDCount)",
                "pendingScopes=\(pendingRepairScopeCount)",
                "freshnessBarrierRequested=\(requestedFreshnessBarrier ? 1 : 0)"
            ].joined(separator: " ")
        }
    }

    struct SearchResultPublicationDiagnostic: Equatable {
        let query: String
        let debounceMilliseconds: Double
        let computationMilliseconds: Double
        let publishedAtMilliseconds: Double
    }

    @Published var session: SwitcherSession? {
        didSet {
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
    let activator = RuntimeActivator()
    let iconProvider = AppIconProvider()
    let searchCoordinator = SwitcherSearchCoordinator()
    let searchSchedulingOwner: SwitcherSearchSchedulingOwner
    let windowRecencyTracker: RuntimeWindowRecencyTracker
    var previewProviderResolver = WindowPreviewProviderResolver.default
    let previewImageCache = BoundedImageCache(
        countLimit: 64,
        totalCostLimit: 160 * 1_024 * 1_024
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
    var runtimeContextsByID: [String: RuntimeAppContext] = [:]
    var rememberedWindowIDByAppID: [String: String] = [:]
    var previewCaptureAttemptedKeys: Set<String> = []
    var previewCaptureFailedKeys: Set<String> = []
    var previewCaptureInFlightKeys: Set<String> = []
    var previewCaptureStatesByKey: [String: PreviewCaptureState] = [:]
    var previewImageReadyLoggedKeys: Set<String> = []
    var previewSessionPinnedKeys: Set<String> = []
    var previewSessionPinnedImagesByKey: [String: NSImage] = [:]
    var previewDeferredCaptureScheduledAppIDs: Set<String> = []
    var previewCaptureGeneration: UInt64 = 0
    var previewCaptureCancellationsByID:
        [UUID: WindowPreviewCaptureCancellation] = [:]
    let previewCaptureSemaphore = DispatchSemaphore(value: 4)
    var previewWindowSnapshotsByAppID: [String: [WindowCandidate]] = [:]
    var lastWindowPreviewExposureLogSummary: String?
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
        searchSchedulingOwner: SwitcherSearchSchedulingOwner? = nil
    ) {
        self.windowRecencyTracker = windowRecencyTracker
        self.runtimeProjectionService = runtimeProjectionService
        self.searchSchedulingOwner =
            searchSchedulingOwner ?? SwitcherSearchSchedulingOwner()
        activator.windowFocusVerifiedHandler = { [windowRecencyTracker, runtimeProjectionService] verification in
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
        activator.windowFocusReadbackMismatchHandler = { [runtimeProjectionService] diagnostic in
            runtimeProjectionService.signalWindowFocusReadbackMismatch(diagnostic)
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
        session.handle(keyInput)

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
        guard var session else { return }
        let target = session.commitSelection()
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
        invalidateRuntimeProjectionMaintenanceRequest(reason: .resetSession)
        cancelPendingSearchComputation()
        pendingSearchActivationAfterFreshnessBarrier = false
        session = nil
        resetSessionAppWindowReadinessTracking()
        pendingTerminateRequest = nil
        terminatingAppID = nil
        overlayStyle = .appAndWindow
        _ = searchCoordinator.exit()
        committedSearchAppsByID = [:]
        publishSearchStateIfNeeded()
        resetRuntimeState()
    }

    func resetRuntimeState() {
        invalidateSelectedAppWindowProjection(reason: .resetRuntimeState)
        runtimeContextsByID = [:]
        clearPreviewSnapshotState()
        autoEnterSuppressedAppID = nil
        pendingManualWindowLayerEntryAppID = nil
        titleBarStyleInferenceEnabled = false
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
