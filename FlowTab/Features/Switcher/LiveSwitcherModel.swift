import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

struct RuntimeFocusedWindowIdentity {
    let cgWindowID: CGWindowID?
    let title: String?
    let frame: CGRect?
}

struct TerminateRefreshPollingDiagnostic: Equatable {
    enum Action: String, Equatable {
        case refresh
        case timeout
        case canceled
    }

    enum ProcessState: String, Equatable {
        case running
        case exited
        case unknown
    }

    let appID: String
    let pid: pid_t
    let appInstanceGeneration: UInt64
    let attempt: Int
    let maxAttempts: Int
    let elapsedMs: Double
    let finalProcessState: ProcessState
    let reason: String
    let action: Action

    var logMessage: String {
        [
            "terminate poll",
            "action=\(action.rawValue)",
            "reason=\(reason)",
            "appID=\(appID)",
            "pid=\(pid)",
            "appInstanceGeneration=\(appInstanceGeneration)",
            "attempt=\(attempt)/\(maxAttempts)",
            "elapsedMs=\(String(format: "%.3f", elapsedMs))",
            "finalProcessState=\(finalProcessState.rawValue)"
        ].joined(separator: " ")
    }
}

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

    struct BackgroundFullSnapshotRefreshRequest {
        let triggerDirection: CycleDirection
        let generation: UInt64
        let scheduledMs: Double
        let reason: SnapshotInvalidationReason

        init(
            triggerDirection: CycleDirection,
            generation: UInt64,
            scheduledMs: Double,
            reason: SnapshotInvalidationReason = .startSession
        ) {
            self.triggerDirection = triggerDirection
            self.generation = generation
            self.scheduledMs = scheduledMs
            self.reason = reason
        }
    }

    enum SnapshotInvalidationReason: String, Equatable {
        case startSession
        case startFocusedWindowSession
        case commitSelection
        case resetSession
        case resetRuntimeState
        case explicitBackgroundRefreshInvalidation
        case explicitSelectedAppWindowInvalidation
    }

    enum SnapshotInvalidationScope: String, Equatable {
        case backgroundFullSnapshot
        case selectedAppWindowSnapshot
    }

    struct SnapshotInvalidationRecord: Equatable {
        let reason: SnapshotInvalidationReason
        let scope: SnapshotInvalidationScope
        let backgroundGeneration: UInt64
        let selectedAppWindowGeneration: UInt64
        let clearedDeferredBackgroundRequest: Bool

        var logMessage: String {
            [
                "snapshotInvalidation",
                "scope=\(scope.rawValue)",
                "reason=\(reason.rawValue)",
                "backgroundGeneration=\(backgroundGeneration)",
                "selectedAppWindowGeneration=\(selectedAppWindowGeneration)",
                "clearedDeferredBackgroundRequest=\(clearedDeferredBackgroundRequest ? 1 : 0)"
            ].joined(separator: " ")
        }
    }

    struct BackgroundFullSnapshotRefreshDiagnostic: Equatable {
        let result: String
        let generation: UInt64
        let currentGeneration: UInt64
        let reason: SnapshotInvalidationReason
        let trigger: String
        let applyGeneration: UInt64?
        let totalMs: String

        var logMessage: String {
            [
                "backgroundFullSnapshotRefresh",
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

    @Published var session: SwitcherSession? {
        didSet {
            guard let session else {
                sessionAppsByID = [:]
                return
            }
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

    let runtimeSnapshotService: any RuntimeSnapshotServing
    let activator = RuntimeActivator()
    let iconProvider = AppIconProvider()
    let searchCoordinator = SwitcherSearchCoordinator()
    let windowRecencyTracker: RuntimeWindowRecencyTracker
    var previewProviderResolver = WindowPreviewProviderResolver.default
    let previewImageCache = BoundedImageCache(
        countLimit: 64,
        totalCostLimit: 160 * 1_024 * 1_024
    )

    var onSearchStateChanged: (() -> Void)?
    var onSessionLayoutChanged: (() -> Void)?
    var onSearchResultScrollRequestForTesting: ((String) -> Void)?
    var snapshotProviderOverride: (() -> RuntimeSnapshot)?
    var fastAppSnapshotProviderOverride: (() -> RuntimeSnapshot)?
    var selectedAppSnapshotProviderOverride: ((String) -> RuntimeHomeAppSnapshot?)?
    var backgroundFullSnapshotProviderOverride: (() -> RuntimeSnapshot)?
    var frontmostApplicationOverride: (() -> NSRunningApplication?)?
    var focusedWindowIdentityOverride: ((NSRunningApplication) -> RuntimeFocusedWindowIdentity?)?
    var frontmostRuntimeWindowIDOverride: ((
        NSRunningApplication,
        AppSwitchCandidate,
        RuntimeAppContext
    ) -> String?)?
    var activationOverride: ((ActivationTarget, [String: RuntimeAppContext]) -> Void)?
    var terminateRequestOverride: ((String) -> (sent: Bool, pid: pid_t))?
    var isProcessRunningOverride: ((pid_t) -> Bool)?
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
    var terminateRefreshPollIntervalNs: UInt64 = 60_000_000
    var terminateRefreshTimeoutNs: UInt64 = 1_800_000_000

    var sessionAppsByID: [String: AppSwitchCandidate] = [:]
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
    let previewCaptureSemaphore = DispatchSemaphore(value: 4)
    var previewWindowSnapshotsByAppID: [String: [WindowCandidate]] = [:]
    var lastWindowPreviewExposureLogSummary: String?
    var autoEnterSuppressedAppID: String?
    var titleBarStyleInferenceEnabled = false
    var searchInputHasMarkedText = false
    var pendingSearchComputationTask: Task<Void, Never>?
    var pendingTerminateRefreshTask: Task<Void, Never>?
    var pendingTerminateRequest: PendingTerminateRequest?
    var lastTerminateRefreshPollingDiagnostic: TerminateRefreshPollingDiagnostic?
    var terminateAppInstanceGeneration: UInt64 = 0
    var backgroundFullSnapshotRefreshGeneration: UInt64 = 0
    var backgroundFullSnapshotRefreshEnabled = true
    var backgroundFullSnapshotRefreshDelay: DispatchTimeInterval = .milliseconds(150)
    var deferredBackgroundFullSnapshotRefreshRequest: BackgroundFullSnapshotRefreshRequest?
    var selectedAppWindowSnapshotGeneration: UInt64 = 0
    var selectedAppWindowSnapshotPendingAppID: String?
    var lastSnapshotInvalidationRecord: SnapshotInvalidationRecord?
    var lastBackgroundFullSnapshotRefreshDiagnostic: BackgroundFullSnapshotRefreshDiagnostic?
    var searchComputationRevision: UInt64 = 0
    var searchDebounceNanoseconds: UInt64 = 20_000_000

    init(
        windowRecencyTracker: RuntimeWindowRecencyTracker = .shared,
        snapshotService: any RuntimeSnapshotServing = sharedRuntimeSnapshotService
    ) {
        self.windowRecencyTracker = windowRecencyTracker
        runtimeSnapshotService = snapshotService
        activator.windowFocusVerifiedHandler = { [windowRecencyTracker, snapshotService] verification in
            windowRecencyTracker.recordVerifiedFocus(
                appID: verification.appID,
                windowID: verification.windowID,
                ownerPID: verification.ownerPID,
                cgWindowID: verification.targetCGWindowID,
                title: verification.title,
                frame: verification.frame,
                allowedActions: verification.allowedActions
            )
            snapshotService.signalWindowFocusVerified(verification)
        }
    }

    func signalSpaceTopologyChanged() {
        runtimeSnapshotService.signalSpaceTopologyChanged()
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

    func startSession(triggerDirection: CycleDirection) -> Bool {
        cancelPendingTerminateRefresh()
        invalidateSelectedAppWindowSnapshot(reason: .startSession)
        clearTerminateSelectedAppAnimation()
        overlayStyle = .appAndWindow
        titleBarStyleInferenceEnabled = false
        guard loadFastAppSnapshot(triggerDirection: triggerDirection, preferredSelectedAppID: nil) else {
            return false
        }
        scheduleBackgroundFullSnapshotRefresh(triggerDirection: triggerDirection)
        return true
    }

    func startFocusedAppWindowSession(triggerDirection: CycleDirection) -> Bool {
        let startMs = Self.monotonicMilliseconds()
        cancelPendingTerminateRefresh()
        invalidateSelectedAppWindowSnapshot(reason: .startFocusedWindowSession)
        clearTerminateSelectedAppAnimation()
        overlayStyle = .windowOnly
        titleBarStyleInferenceEnabled = true
        guard let frontmostApp = resolveFrontmostApplication() else {
            logStartFocusedWindowSessionNoFrontmost(startMs: startMs)
            resetSessionState()
            return false
        }
        let frontmostReadyMs = Self.monotonicMilliseconds()

        let frontmostAppID = RuntimeSnapshotProvider.baseAppID(for: frontmostApp)
        let snapshotReadMs: Double
        let recencyAppliedMs: Double
        var resolvedAppCandidate: AppSwitchCandidate?
        var resolvedContext: RuntimeAppContext?

        if snapshotProviderOverride != nil {
            let rawSnapshot = makeSnapshot()
            snapshotReadMs = Self.monotonicMilliseconds()
            let snapshot = snapshotWithWindowRecencyApplied(rawSnapshot)
            recencyAppliedMs = Self.monotonicMilliseconds()
            resolvedAppCandidate = snapshot.apps.first(where: { $0.id == frontmostAppID })
            resolvedContext = snapshot.contextsByID[frontmostAppID]
        } else {
            let focusedSnapshot = runtimeSnapshotService.focusedAppSnapshot(
                processIdentifier: frontmostApp.processIdentifier
            )
            snapshotReadMs = Self.monotonicMilliseconds()
            let snapshot = focusedSnapshot.map {
                homeSnapshotWithWindowRecencyApplied(
                    $0,
                    appID: frontmostAppID,
                    frontmostApp: frontmostApp
                )
            }
            recencyAppliedMs = Self.monotonicMilliseconds()
            resolvedAppCandidate = snapshot?.candidate
            resolvedContext = snapshot?.context
        }

        guard let appCandidate = resolvedAppCandidate, let context = resolvedContext else {
            let failedMs = Self.monotonicMilliseconds()
            logStartFocusedWindowSession(
                result: "missingFrontmostApp",
                frontmostAppID: frontmostAppID,
                frontmostReadyMs: frontmostReadyMs,
                snapshotReadMs: snapshotReadMs,
                recencyAppliedMs: recencyAppliedMs,
                completeMs: failedMs,
                startMs: startMs
            )
            resetSessionState()
            return false
        }
        let sessionAppID = appCandidate.id
        guard !appCandidate.windows.isEmpty else {
            let failedMs = Self.monotonicMilliseconds()
            logStartFocusedWindowSession(
                result: "noWindows",
                frontmostAppID: frontmostAppID,
                frontmostReadyMs: frontmostReadyMs,
                snapshotReadMs: snapshotReadMs,
                recencyAppliedMs: recencyAppliedMs,
                completeMs: failedMs,
                startMs: startMs
            )
            resetSessionState()
            return false
        }

        runtimeContextsByID = [sessionAppID: context]
        clearPreviewSnapshotState()
        autoEnterSuppressedAppID = nil
        let preferences = SwitcherBehaviorPreferencesStore.loadSwitcherPreferences()
        var rebuiltSession = SwitcherSession(
            apps: [appCandidate],
            preferences: preferences,
            triggerDirection: triggerDirection,
            rememberedWindowIDByAppID: rememberedWindowIDByAppID
        )

        let focusedWindowSelected: Bool
        if let focusedWindowID = focusedWindowIDForWindowSession(
            app: appCandidate,
            context: context
        ) {
            focusedWindowSelected = rebuiltSession.selectWindow(
                appID: sessionAppID,
                windowID: focusedWindowID
            )
        } else {
            focusedWindowSelected = false
        }
        if !focusedWindowSelected {
            guard rebuiltSession.enterWindowCycle(allowSingleWindow: true) else {
                resetSessionState()
                return false
            }
        }

        session = rebuiltSession
        _ = searchCoordinator.exit()
        publishSearchStateIfNeeded()
        let completeMs = Self.monotonicMilliseconds()
        logStartFocusedWindowSession(
            result: "ready",
            frontmostAppID: frontmostAppID,
            frontmostReadyMs: frontmostReadyMs,
            snapshotReadMs: snapshotReadMs,
            recencyAppliedMs: recencyAppliedMs,
            completeMs: completeMs,
            startMs: startMs,
            windows: appCandidate.windows.count
        )
        return true
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
        schedulePostTerminateRefresh(for: request)
        return .updatedSession
    }

    func schedulePostTerminateRefresh(for request: PendingTerminateRequest) {
        cancelPendingTerminateRefresh()
        let maxAttempts = max(1, Int(terminateRefreshTimeoutNs / terminateRefreshPollIntervalNs))
        let startMs = Self.monotonicMilliseconds()
        pendingTerminateRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.session != nil, self.pendingTerminateRequest == request else {
                self.recordTerminateRefreshPollingDiagnostic(
                    request: request,
                    attempt: 0,
                    maxAttempts: maxAttempts,
                    startMs: startMs,
                    finalProcessState: .unknown,
                    reason: "request_stale",
                    action: .canceled
                )
                self.pendingTerminateRefreshTask = nil
                return
            }
            if !self.isProcessRunning(request.pid) {
                self.recordTerminateRefreshPollingDiagnostic(
                    request: request,
                    attempt: 0,
                    maxAttempts: maxAttempts,
                    startMs: startMs,
                    finalProcessState: .exited,
                    reason: "initial_process_check",
                    action: .refresh
                )
                self.refreshSessionAfterTerminatedApplication(
                    appID: request.appID,
                    pid: request.pid,
                    reason: "initial_process_check"
                )
                self.pendingTerminateRefreshTask = nil
                return
            }

            for attempt in 1...maxAttempts {
                try? await Task.sleep(nanoseconds: self.terminateRefreshPollIntervalNs)
                guard !Task.isCancelled else { return }
                guard self.session != nil else { break }
                guard self.pendingTerminateRequest == request else { break }

                guard !self.isProcessRunning(request.pid) else { continue }
                self.recordTerminateRefreshPollingDiagnostic(
                    request: request,
                    attempt: attempt,
                    maxAttempts: maxAttempts,
                    startMs: startMs,
                    finalProcessState: .exited,
                    reason: "poll",
                    action: .refresh
                )
                self.refreshSessionAfterTerminatedApplication(
                    appID: request.appID,
                    pid: request.pid,
                    reason: "poll"
                )
                self.pendingTerminateRefreshTask = nil
                return
            }

            guard self.pendingTerminateRequest == request else {
                self.recordTerminateRefreshPollingDiagnostic(
                    request: request,
                    attempt: maxAttempts,
                    maxAttempts: maxAttempts,
                    startMs: startMs,
                    finalProcessState: .unknown,
                    reason: "request_changed",
                    action: .canceled
                )
                self.pendingTerminateRefreshTask = nil
                return
            }
            if !self.isProcessRunning(request.pid) {
                self.recordTerminateRefreshPollingDiagnostic(
                    request: request,
                    attempt: maxAttempts,
                    maxAttempts: maxAttempts,
                    startMs: startMs,
                    finalProcessState: .exited,
                    reason: "poll_timeout_final_check",
                    action: .refresh
                )
                self.refreshSessionAfterTerminatedApplication(
                    appID: request.appID,
                    pid: request.pid,
                    reason: "poll_timeout_final_check"
                )
                self.pendingTerminateRefreshTask = nil
                return
            }
            self.recordTerminateRefreshPollingDiagnostic(
                request: request,
                attempt: maxAttempts,
                maxAttempts: maxAttempts,
                startMs: startMs,
                finalProcessState: .running,
                reason: "timeout",
                action: .timeout
            )
            self.pendingTerminateRequest = nil
            if self.terminatingAppID == request.appID {
                self.terminatingAppID = nil
            }
            self.pendingTerminateRefreshTask = nil
        }
    }

    func recordTerminateRefreshPollingDiagnostic(
        request: PendingTerminateRequest,
        attempt: Int,
        maxAttempts: Int,
        startMs: Double,
        finalProcessState: TerminateRefreshPollingDiagnostic.ProcessState,
        reason: String,
        action: TerminateRefreshPollingDiagnostic.Action
    ) {
        let diagnostic = TerminateRefreshPollingDiagnostic(
            appID: request.appID,
            pid: request.pid,
            appInstanceGeneration: request.generation,
            attempt: attempt,
            maxAttempts: maxAttempts,
            elapsedMs: max(0, Self.monotonicMilliseconds() - startMs),
            finalProcessState: finalProcessState,
            reason: reason,
            action: action
        )
        lastTerminateRefreshPollingDiagnostic = diagnostic
        if action == .timeout {
            RuntimeLog.error(.session, diagnostic.logMessage)
        } else {
            RuntimeLog.info(.session, diagnostic.logMessage)
        }
    }

    func restoreSearchStateAfterSnapshotRefreshIfNeeded(
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
        let refreshed = loadSnapshot(
            triggerDirection: .forward,
            preferredSelectedAppID: matchesPending ? pendingRequest?.preferredSelectedAppID : nil,
            animateAppStripUpdate: true,
            preserveSearchState: searchViewState.isActive
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
        guard var session else { return false }
        if case .windowCycle = session.mode {
            return false
        }
        if autoEnterSuppressedAppID == session.selectedApp.id {
            return false
        }
        guard session.selectedApp.windows.count >= 2 else { return false }
        session.enterWindowCycleIfPossible()
        self.session = session
        if case .windowCycle = session.mode {
            return true
        }
        return false
    }

    func debugSelectionSummary() -> String {
        guard let session else { return "session=nil" }
        return "app=\(session.selectedApp.displayName) windows=\(session.selectedApp.windows.count) mode=\(session.mode.debugName)"
    }

    func commitSelection() {
        guard var session else { return }
        let target = session.commitSelection()
        rememberedWindowIDByAppID = session.rememberedWindowIDByAppID
        invalidateBackgroundFullSnapshotRefresh(reason: .commitSelection)
        cancelPendingTerminateRefresh()
        clearTerminateSelectedAppAnimation()
        cancelPendingSearchComputation()
        self.session = nil
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

    func cancelSelection() {
        resetSessionState()
    }

    func resetSessionState() {
        invalidateBackgroundFullSnapshotRefresh(reason: .resetSession)
        cancelPendingTerminateRefresh()
        cancelPendingSearchComputation()
        session = nil
        pendingTerminateRequest = nil
        terminatingAppID = nil
        overlayStyle = .appAndWindow
        searchCoordinator.rebuildIndex(with: [])
        publishSearchStateIfNeeded()
        resetRuntimeState()
    }

    func resetRuntimeState() {
        invalidateSelectedAppWindowSnapshot(reason: .resetRuntimeState)
        runtimeContextsByID = [:]
        clearPreviewSnapshotState()
        autoEnterSuppressedAppID = nil
        titleBarStyleInferenceEnabled = false
    }

    func cancelPendingSearchComputation() {
        pendingSearchComputationTask?.cancel()
        pendingSearchComputationTask = nil
        searchComputationRevision &+= 1
    }

    func cancelPendingTerminateRefresh() {
        pendingTerminateRefreshTask?.cancel()
        pendingTerminateRefreshTask = nil
    }

    func snapshotWithWindowRecencyApplied(_ snapshot: RuntimeSnapshot) -> RuntimeSnapshot {
        recordFrontmostFocusedWindowRecency(in: snapshot)
        return windowRecencyTracker.snapshotWithRecencyApplied(snapshot)
    }

    private func homeSnapshotWithWindowRecencyApplied(
        _ snapshot: RuntimeHomeAppSnapshot,
        appID: String,
        frontmostApp: NSRunningApplication
    ) -> RuntimeHomeAppSnapshot {
        recordFrontmostFocusedWindowRecency(
            appID: appID,
            app: snapshot.candidate,
            context: snapshot.context,
            runningApp: frontmostApp
        )
        return windowRecencyTracker.homeSnapshotWithRecencyApplied(snapshot)
    }

    private func recordFrontmostFocusedWindowRecency(in snapshot: RuntimeSnapshot) {
        guard let frontmostApp = resolveFrontmostApplication() else { return }
        let frontmostAppID = frontmostApp.bundleIdentifier
            ?? "pid:\(frontmostApp.processIdentifier)"
        guard
            let app = snapshot.apps.first(where: { $0.id == frontmostAppID }),
            let context = snapshot.contextsByID[frontmostAppID]
        else {
            return
        }
        recordFrontmostFocusedWindowRecency(
            appID: frontmostAppID,
            app: app,
            context: context,
            runningApp: frontmostApp
        )
    }

    private func recordFrontmostFocusedWindowRecency(
        appID: String,
        app: AppSwitchCandidate,
        context: RuntimeAppContext,
        runningApp: NSRunningApplication
    ) {
        let focusedWindowID = focusedWindowIDForWindowSession(
            app: app,
            context: context,
            runningApp: runningApp
        ) ?? frontmostRuntimeWindowIDForWindowSession(
            frontmostApp: runningApp,
            app: app,
            context: context
        )
        guard let focusedWindowID else { return }
        windowRecencyTracker.recordVerifiedFocus(
            appID: appID,
            windowID: focusedWindowID,
            context: context
        )
    }

    func resolveFrontmostApplication() -> NSRunningApplication? {
        if let frontmostApplicationOverride {
            return frontmostApplicationOverride()
        }
        return NSWorkspace.shared.frontmostApplication
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

    func isProcessRunning(_ pid: pid_t) -> Bool {
        if let isProcessRunningOverride {
            return isProcessRunningOverride(pid)
        }
        return NSRunningApplication(processIdentifier: pid) != nil
    }

    private func focusedWindowIDForWindowSession(
        app: AppSwitchCandidate,
        context: RuntimeAppContext,
        runningApp: NSRunningApplication? = nil
    ) -> String? {
        guard let identity = focusedWindowIdentity(for: runningApp ?? context.runningApp) else {
            return nil
        }
        return focusedWindowID(matching: identity, app: app, context: context)
    }

    private func frontmostRuntimeWindowIDForWindowSession(
        frontmostApp: NSRunningApplication,
        app: AppSwitchCandidate,
        context: RuntimeAppContext
    ) -> String? {
        if let frontmostRuntimeWindowIDOverride {
            return frontmostRuntimeWindowIDOverride(frontmostApp, app, context)
        }

        let frontmostPID = frontmostApp.processIdentifier
        let appWindowIDs = Set(app.windows.map(\.id))
        var windowIDsByCGWindowID: [CGWindowID: [String]] = [:]
        for window in context.windowsByID.values {
            guard appWindowIDs.contains(window.id), let cgWindowID = window.cgWindowID else {
                continue
            }
            let ownerPID = window.ownerPID == 0
                ? context.runningApp.processIdentifier
                : window.ownerPID
            guard ownerPID == frontmostPID else { continue }
            windowIDsByCGWindowID[cgWindowID, default: []].append(window.id)
        }
        guard !windowIDsByCGWindowID.isEmpty else { return nil }

        let cgWindows = runtimeSnapshotService.currentCGWindowsByPID()[frontmostPID] ?? []
        for cgWindow in cgWindows where RuntimeSnapshotProvider.cgWindowPassesValidityConstraints(cgWindow) {
            guard let windowIDs = windowIDsByCGWindowID[cgWindow.id], windowIDs.count == 1 else {
                continue
            }
            return windowIDs[0]
        }
        return nil
    }

    private func focusedWindowIdentity(
        for app: NSRunningApplication
    ) -> RuntimeFocusedWindowIdentity? {
        if let focusedWindowIdentityOverride {
            return focusedWindowIdentityOverride(app)
        }
        guard AccessibilityPermissionChecker.isTrusted() else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard case .success(let focusedWindow) = AXTypedAttributeReader.elementAttribute(
            appElement,
            kAXFocusedWindowAttribute as CFString
        ) else {
            return nil
        }

        return RuntimeFocusedWindowIdentity(
            cgWindowID: AXWindowInspector.cgWindowID(for: focusedWindow),
            title: AXWindowInspector.title(for: focusedWindow),
            frame: AXWindowInspector.frame(for: focusedWindow)
        )
    }

    private func focusedWindowID(
        matching identity: RuntimeFocusedWindowIdentity,
        app: AppSwitchCandidate,
        context: RuntimeAppContext
    ) -> String? {
        let appWindowIDs = Set(app.windows.map(\.id))
        let eligibleWindows = context.windowsByID.values.filter { window in
            appWindowIDs.contains(window.id)
        }

        if let cgWindowID = identity.cgWindowID {
            let cgMatches = eligibleWindows.filter { $0.cgWindowID == cgWindowID }
            if let focusedWindowID = singleFocusedWindowID(from: cgMatches) {
                return focusedWindowID
            }
        }

        let title = normalizedRuntimeWindowTitle(identity.title)
        let frame = identity.frame?.standardized
        guard title != nil || frame != nil else { return nil }

        let semanticMatches = eligibleWindows.filter { window in
            let titleMatches: Bool
            if let title {
                titleMatches = runtimeWindowTitle(window.title, matches: title)
            } else {
                titleMatches = false
            }

            let frameMatches: Bool
            if let frame, let windowFrame = window.frame {
                frameMatches = RuntimeWindowTopologyClassifier.framesApproximatelyMatch(
                    windowFrame,
                    frame
                )
            } else {
                frameMatches = false
            }

            switch (title, frame) {
            case (.some, .some):
                return titleMatches && frameMatches
            case (.some, .none):
                return titleMatches
            case (.none, .some):
                return frameMatches
            case (.none, .none):
                return false
            }
        }
        return singleFocusedWindowID(from: semanticMatches)
    }

    private func singleFocusedWindowID(from windows: [RuntimeWindowContext]) -> String? {
        windows.count == 1 ? windows[0].id : nil
    }

    private func runtimeWindowTitle(_ candidateTitle: String, matches focusedTitle: String) -> Bool {
        guard let candidateTitle = normalizedRuntimeWindowTitle(candidateTitle) else {
            return false
        }
        return candidateTitle.caseInsensitiveCompare(focusedTitle) == .orderedSame
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
