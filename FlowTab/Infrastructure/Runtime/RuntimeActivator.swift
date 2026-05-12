import AppKit
import ApplicationServices
import Foundation
import FlowTabCore

@MainActor
final class RuntimeActivator {
    private enum WindowFocusAttemptResult: Equatable {
        case verified
        case focusedButUnverified
        case noFocusRoute

        var debugName: String {
            switch self {
            case .verified:
                return "verified"
            case .focusedButUnverified:
                return "focusedButUnverified"
            case .noFocusRoute:
                return "noFocusRoute"
            }
        }
    }

    var activateCurrentAppIfNeededOverride: ((NSRunningApplication) -> Bool)?
    var requestActivationOverride: ((NSRunningApplication, ((NSRunningApplication) -> Void)?) -> Void)?
    var focusWindowOverride: ((String, String, Bool, NSRunningApplication) -> Void)?
    var windowFocusVerifiedHandler: ((String, String, pid_t, CGWindowID?, String, CGRect?) -> Void)?
    var focusAXWindowOverride: ((AXUIElement, Bool, NSRunningApplication) -> Bool)?
    var liveWindowRegistry: AXLiveWindowRegistry = .shared
    var currentAXWindowsOverride: ((NSRunningApplication) -> [AXUIElement])?
    var currentCGWindowsOverride: ((pid_t) -> [RuntimeSnapshotProvider.CGWindowEntry])?
    var axWindowFrameOverride: ((AXUIElement) -> CGRect?)?
    var axWindowTitleOverride: ((AXUIElement) -> String?)?
    var focusCGWindowOverride: ((NSRunningApplication, CGWindowID) -> Bool)?
    var focusRecoveryRetryDelaysNanoseconds: [UInt64] = [50_000_000, 150_000_000]

    private var focusRecoveryTask: Task<Void, Never>?

    func activate(target: ActivationTarget, contextsByID: [String: RuntimeAppContext]) {
        focusRecoveryTask?.cancel()
        focusRecoveryTask = nil

        switch target {
        case .app(let appID):
            activateApp(appID: appID, contextsByID: contextsByID)
        case .window(let appID, let windowID, let restoreIfMinimized):
            activateWindow(
                appID: appID,
                windowID: windowID,
                restoreIfMinimized: restoreIfMinimized,
                contextsByID: contextsByID
            )
        }
    }

    private func activateApp(appID: String, contextsByID: [String: RuntimeAppContext]) {
        guard let context = contextsByID[appID] else { return }
        if activateCurrentAppIfNeeded(context.runningApp) {
            return
        }
        requestActivation(of: context.runningApp)
    }

    private func activateWindow(
        appID: String,
        windowID: String,
        restoreIfMinimized: Bool,
        contextsByID: [String: RuntimeAppContext]
    ) {
        guard let context = contextsByID[appID] else { return }
        guard let windowContext = context.windowsByID[windowID] else {
            requestActivation(of: context.runningApp)
            return
        }
        let targetApp = activationTargetApplication(for: windowContext, fallback: context.runningApp)
        if activateCurrentAppIfNeeded(targetApp) {
            return
        }

        let request = WindowFocusRequest(
            appID: appID,
            windowID: windowID,
            title: windowContext.title,
            frame: windowContext.frame,
            ownerPID: windowContext.ownerPID == 0 ? targetApp.processIdentifier : windowContext.ownerPID,
            preferredAXWindow: windowContext.axWindow,
            preferredActivationHandleID: windowContext.activationHandleID,
            preferredCGWindowID: windowContext.cgWindowID,
            spaceIDs: windowContext.spaceIDs,
            allowsPublicAXRecovery: windowContext.allowsPublicAXRecovery,
            restoreIfMinimized: restoreIfMinimized || windowContext.isMinimized
        )
        RuntimeLog.info(
            "Activation",
            "window-request appID=\(appID) pid=\(targetApp.processIdentifier) windowID=\(windowID) title=\(runtimeActivationLogValue(windowContext.title)) cg=\(windowContext.cgWindowID.map(String.init) ?? "nil") handle=\(windowContext.activationHandleID ?? "nil") ax=\(windowContext.axWindow == nil ? 0 : 1) fallbackAX=0 spaces=\(windowContext.spaceIDs) frame=\(runtimeActivationFrameDescription(windowContext.frame)) restore=\(request.restoreIfMinimized) sticky=\(windowContext.hasStickyBinding) source=\(windowContext.lastConfirmationSource?.rawValue ?? "nil") publicAXRecovery=\(windowContext.allowsPublicAXRecovery ? 1 : 0)"
        )
        if request.targetCGWindowID(expectedPID: targetApp.processIdentifier) != nil {
            self.focusWindow(request, in: targetApp)
            return
        }

        requestActivation(of: targetApp) { [weak self] _ in
            guard let self else { return }
            self.focusWindow(request, in: targetApp)
        }
    }

    private func focusWindow(_ request: WindowFocusRequest, in app: NSRunningApplication) {
        guard !attemptWindowFocus(request, in: app) else { return }
        scheduleFocusRecovery(for: request, in: app)
    }

    @discardableResult
    private func attemptWindowFocus(_ request: WindowFocusRequest, in app: NSRunningApplication) -> Bool {
        if let focusWindowOverride {
            focusWindowOverride(request.windowID, request.title, request.restoreIfMinimized, app)
            return reportWindowFocusVerified(request, in: app)
        }

        let cgFocusResult = attemptCGWindowFocus(request, in: app)
        RuntimeLog.info(
            "Activation",
            "focus-attempt route=cg result=\(cgFocusResult.debugName) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(request.targetCGWindowID(expectedPID: app.processIdentifier).map(String.init) ?? "nil") frontmost=\(runtimeActivationFrontmostDescription())"
        )
        let cgFocusVerified: Bool
        switch cgFocusResult {
        case .verified:
            cgFocusVerified = true
        case .focusedButUnverified:
            cgFocusVerified = false
        case .noFocusRoute:
            cgFocusVerified = false
        }

        let windowFromRegistry = liveWindowRegistry.window(
            forWindowID: request.preferredActivationHandleID ?? request.windowID,
            expectedPID: app.processIdentifier
        )
        if let directWindow = request.preferredAXWindow ?? windowFromRegistry {
            let axFocusResult = attemptAXWindowFocus(
                directWindow,
                route: "direct",
                request: request,
                in: app
            )
            RuntimeLog.info(
                "Activation",
                "focus-attempt route=ax-direct result=\(axFocusResult.debugName) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(request.targetCGWindowID(expectedPID: app.processIdentifier).map(String.init) ?? "nil")"
            )
            switch axFocusResult {
            case .verified:
                return reportWindowFocusVerified(request, in: app)
            case .focusedButUnverified:
                return false
            case .noFocusRoute:
                if cgFocusVerified {
                    return reportWindowFocusVerified(request, in: app)
                }
            }
        } else {
            RuntimeLog.info(
                "Activation",
                "ax-direct unavailable pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(request.targetCGWindowID(expectedPID: app.processIdentifier).map(String.init) ?? "nil") handle=\(request.preferredActivationHandleID ?? "nil") preferredAX=0 registryAX=0"
            )
        }

        if cgFocusVerified {
            return reportWindowFocusVerified(request, in: app)
        }

        guard request.allowsPublicAXRecovery else {
            RuntimeLog.info(
                "Activation",
                "ax-recovery skipped pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(request.targetCGWindowID(expectedPID: app.processIdentifier).map(String.init) ?? "nil") reason=disabled"
            )
            return false
        }

        let targetCGWindowID = request.targetCGWindowID(expectedPID: app.processIdentifier)
        let includeRemoteWindows = RuntimeWindowTopologyClassifier.hasOffDesktopSpace(
            spaceIDs: request.spaceIDs
        )
        RuntimeLog.info(
            "Activation",
            "ax-recovery scan pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID.map(String.init) ?? "nil") includeRemote=\(includeRemoteWindows ? 1 : 0) spaces=\(request.spaceIDs) expectedTitle=\(runtimeActivationLogValue(request.title)) expectedFrame=\(runtimeActivationFrameDescription(request.frame))"
        )
        let windows = currentAXWindows(
            for: app,
            includeRemoteWindows: includeRemoteWindows
        )
        RuntimeLog.info(
            "Activation",
            "ax-recovery fetched pid=\(app.processIdentifier) windowID=\(request.windowID) count=\(windows.count)"
        )
        if windows.isEmpty {
            RuntimeLog.info(
                "Activation",
                "ax-recovery no-candidates pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID.map(String.init) ?? "nil")"
            )
        } else {
            if let matchedWindow = resolveAXWindow(
                matchingCGWindowID: targetCGWindowID,
                expectedTitle: request.title,
                expectedFrame: request.frame,
                windows: windows,
                in: app
            ) {
                let axFocusResult = attemptAXWindowFocus(
                    matchedWindow,
                    route: "public-recovery",
                    request: request,
                    in: app
                )
                RuntimeLog.info(
                    "Activation",
                    "focus-attempt route=ax-public-recovery result=\(axFocusResult.debugName) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID.map(String.init) ?? "nil")"
                )
                switch axFocusResult {
                case .verified:
                    return reportWindowFocusVerified(request, in: app)
                case .focusedButUnverified, .noFocusRoute:
                    return false
                }
            }

            if let relatedAXFocusResult = attemptRelatedAXWindowFocus(
                request,
                publicWindows: windows,
                in: app
            ) {
                RuntimeLog.info(
                    "Activation",
                    "focus-attempt route=ax-related result=\(relatedAXFocusResult.debugName) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID.map(String.init) ?? "nil")"
                )
                if relatedAXFocusResult == .verified {
                    return reportWindowFocusVerified(request, in: app)
                }
            }
        }

        if let sameSpaceCGFocusResult = attemptSameSpaceCGWindowFocus(request, in: app) {
            RuntimeLog.info(
                "Activation",
                "focus-attempt route=cg-same-space result=\(sameSpaceCGFocusResult.debugName) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID.map(String.init) ?? "nil")"
            )
            if sameSpaceCGFocusResult == .verified {
                return reportWindowFocusVerified(request, in: app)
            }
        }

        if let relatedCGFocusResult = attemptRelatedCGWindowFocus(request, in: app) {
            RuntimeLog.info(
                "Activation",
                "focus-attempt route=cg-related result=\(relatedCGFocusResult.debugName) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID.map(String.init) ?? "nil")"
            )
            switch relatedCGFocusResult {
            case .verified:
                return reportWindowFocusVerified(request, in: app)
            case .focusedButUnverified, .noFocusRoute:
                return false
            }
        }

        RuntimeLog.info(
            "Activation",
            "ax-recovery no-match pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID.map(String.init) ?? "nil")"
        )
        return false
    }

    private func attemptAXWindowFocus(
        _ window: AXUIElement,
        route: String,
        request: WindowFocusRequest,
        in app: NSRunningApplication
    ) -> WindowFocusAttemptResult {
        guard focusAXWindow(window, restoreIfMinimized: request.restoreIfMinimized, in: app) else {
            RuntimeLog.info(
                "Activation",
                "ax-focus \(route) action-unavailable pid=\(app.processIdentifier) windowID=\(request.windowID)"
            )
            return .noFocusRoute
        }
        guard verifyFocusAttempt(request, route: "ax-\(route)", in: app) else {
            return .focusedButUnverified
        }
        return .verified
    }

    private func verifyFocusAttempt(
        _ request: WindowFocusRequest,
        route: String,
        in app: NSRunningApplication
    ) -> Bool {
        guard !request.spaceIDs.isEmpty else {
            RuntimeLog.info(
                "Activation",
                "focus-verify route=\(route) skipped=empty-spaces pid=\(app.processIdentifier) windowID=\(request.windowID)"
            )
            return true
        }

        guard let targetCGWindowID = request.targetCGWindowID(expectedPID: app.processIdentifier) else {
            RuntimeLog.info(
                "Activation",
                "focus-verify route=\(route) skipped=no-target-cg pid=\(app.processIdentifier) windowID=\(request.windowID)"
            )
            return true
        }

        let currentWindows = currentCGWindows(forPID: app.processIdentifier)
        let isVisible = targetCGWindowIsVisible(
            targetCGWindowID,
            in: app,
            currentWindows: currentWindows
        )
        RuntimeLog.info(
            "Activation",
            "focus-verify route=\(route) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID) visible=\(isVisible ? 1 : 0) windows=\(runtimeActivationCGWindowSummary(currentWindows, targetCGWindowID: targetCGWindowID))"
        )
        return isVisible
    }

    private func attemptCGWindowFocus(
        _ request: WindowFocusRequest,
        in app: NSRunningApplication
    ) -> WindowFocusAttemptResult {
        guard let targetCGWindowID = request.targetCGWindowID(expectedPID: app.processIdentifier) else {
            return .noFocusRoute
        }
        guard focusCGWindow(targetCGWindowID, in: app) else {
            return .noFocusRoute
        }
        let currentWindows = currentCGWindows(forPID: app.processIdentifier)
        let isVisible = targetCGWindowIsVisible(
            targetCGWindowID,
            in: app,
            currentWindows: currentWindows
        )
        RuntimeLog.info(
            "Activation",
            "cg-window-focus verify pid=\(app.processIdentifier) targetCG=\(targetCGWindowID) visible=\(isVisible ? 1 : 0) windows=\(runtimeActivationCGWindowSummary(currentWindows, targetCGWindowID: targetCGWindowID))"
        )
        return isVisible ? .verified : .focusedButUnverified
    }

    private func attemptRelatedAXWindowFocus(
        _ request: WindowFocusRequest,
        publicWindows: [AXUIElement],
        in app: NSRunningApplication
    ) -> WindowFocusAttemptResult? {
        guard RuntimeWindowTopologyClassifier.hasOffDesktopSpace(spaceIDs: request.spaceIDs) else {
            return nil
        }
        guard let targetCGWindowID = request.targetCGWindowID(expectedPID: app.processIdentifier) else {
            return nil
        }
        let currentWindows = currentCGWindows(forPID: app.processIdentifier)
        guard
            let targetWindow = currentWindows.first(where: { $0.id == targetCGWindowID }),
            runtimeCGWindowLooksLikeFullscreenActivationTarget(targetWindow)
        else {
            return nil
        }

        let candidates = publicWindows.compactMap { window -> AXUIElement? in
            guard let cgWindowID = AXWindowInspector.cgWindowID(for: window) else { return nil }
            guard cgWindowID != targetCGWindowID else { return nil }
            guard
                let cgWindow = currentWindows.first(where: { $0.id == cgWindowID }),
                RuntimeSnapshotProvider.cgWindowPassesValidityConstraints(cgWindow)
            else {
                return nil
            }
            guard runtimeCGWindowSharesOffDesktopSpace(cgWindow, with: targetWindow) else {
                return nil
            }
            guard runtimeCGWindowLooksLikeRelatedFullscreenAXSurface(
                cgWindow,
                targetFrame: targetWindow.bounds ?? request.frame
            ) else {
                return nil
            }
            return window
        }
        let candidateIDs = candidates.compactMap { AXWindowInspector.cgWindowID(for: $0) }
        RuntimeLog.info(
            "Activation",
            "ax-related candidates pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID) count=\(candidates.count) ids=\(candidateIDs.map(String.init).joined(separator: ","))"
        )
        guard candidates.count == 1, let candidate = candidates.first else {
            return nil
        }
        let result = attemptAXWindowFocus(
            candidate,
            route: "related",
            request: request,
            in: app
        )
        RuntimeLog.info(
            "Activation",
            "ax-related verify pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID) candidateCG=\(AXWindowInspector.cgWindowID(for: candidate).map(String.init) ?? "nil") result=\(result.debugName)"
        )
        return result
    }

    private func attemptSameSpaceCGWindowFocus(
        _ request: WindowFocusRequest,
        in app: NSRunningApplication
    ) -> WindowFocusAttemptResult? {
        guard RuntimeWindowTopologyClassifier.hasOffDesktopSpace(spaceIDs: request.spaceIDs) else {
            return nil
        }
        guard let targetCGWindowID = request.targetCGWindowID(expectedPID: app.processIdentifier) else {
            return nil
        }

        let currentWindows = currentCGWindows(forPID: app.processIdentifier)
        guard
            let targetWindow = currentWindows.first(where: { $0.id == targetCGWindowID }),
            runtimeCGWindowLooksLikeFullscreenActivationTarget(targetWindow)
        else {
            return nil
        }

        let candidates = currentWindows.filter { window in
            guard window.id != targetCGWindowID else { return false }
            guard runtimeCGWindowSharesOffDesktopSpace(window, with: targetWindow) else {
                return false
            }
            return runtimeCGWindowLooksLikeSameSpaceActivationSurface(
                window,
                targetFrame: targetWindow.bounds ?? request.frame
            )
        }
        RuntimeLog.info(
            "Activation",
            "cg-same-space candidates pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID) count=\(candidates.count) ids=\(candidates.map { String($0.id) }.joined(separator: ","))"
        )
        guard !candidates.isEmpty else { return nil }

        for candidate in candidates.sorted(by: runtimeCGSameSpaceActivationCandidateSort) {
            guard focusCGWindow(candidate.id, in: app) else { continue }
            let windowsAfterFocus = currentCGWindows(forPID: app.processIdentifier)
            let isVisible = targetCGWindowIsVisible(
                targetCGWindowID,
                in: app,
                currentWindows: windowsAfterFocus
            )
            RuntimeLog.info(
                "Activation",
                "cg-same-space verify pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID) candidateCG=\(candidate.id) visible=\(isVisible ? 1 : 0) windows=\(runtimeActivationCGWindowSummary(windowsAfterFocus, targetCGWindowID: targetCGWindowID))"
            )
            if isVisible {
                return .verified
            }
        }
        return .focusedButUnverified
    }

    private func attemptRelatedCGWindowFocus(
        _ request: WindowFocusRequest,
        in app: NSRunningApplication
    ) -> WindowFocusAttemptResult? {
        guard RuntimeWindowTopologyClassifier.hasOffDesktopSpace(spaceIDs: request.spaceIDs) else {
            return nil
        }
        guard let targetCGWindowID = request.targetCGWindowID(expectedPID: app.processIdentifier) else {
            return nil
        }
        guard let expectedTitle = normalizedRuntimeWindowTitle(request.title) else {
            return nil
        }

        let currentWindows = currentCGWindows(forPID: app.processIdentifier)
        let candidates = currentWindows.filter { window in
            guard window.id != targetCGWindowID else { return false }
            guard RuntimeSnapshotProvider.cgWindowPassesValidityConstraints(window) else { return false }
            guard !RuntimeWindowTopologyClassifier.isLikelyFullscreenContent(bounds: window.bounds) else {
                return false
            }
            guard let title = normalizedRuntimeWindowTitle(window.title) else { return false }
            return title.caseInsensitiveCompare(expectedTitle) == .orderedSame
        }
        RuntimeLog.info(
            "Activation",
            "cg-related candidates pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID) count=\(candidates.count) ids=\(candidates.map { String($0.id) }.joined(separator: ","))"
        )
        guard candidates.count == 1, let candidate = candidates.first else {
            return nil
        }
        guard focusCGWindow(candidate.id, in: app) else {
            return .noFocusRoute
        }

        let windowsAfterFocus = currentCGWindows(forPID: app.processIdentifier)
        let isVisible = targetCGWindowIsVisible(
            targetCGWindowID,
            in: app,
            currentWindows: windowsAfterFocus
        )
        RuntimeLog.info(
            "Activation",
            "cg-related verify pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID) relatedCG=\(candidate.id) visible=\(isVisible ? 1 : 0) windows=\(runtimeActivationCGWindowSummary(windowsAfterFocus, targetCGWindowID: targetCGWindowID))"
        )
        return isVisible ? .verified : .focusedButUnverified
    }

    private func targetCGWindowIsVisible(
        _ targetCGWindowID: CGWindowID?,
        in app: NSRunningApplication
    ) -> Bool {
        targetCGWindowIsVisible(
            targetCGWindowID,
            in: app,
            currentWindows: currentCGWindows(forPID: app.processIdentifier)
        )
    }

    private func targetCGWindowIsVisible(
        _ targetCGWindowID: CGWindowID?,
        in _: NSRunningApplication,
        currentWindows: [RuntimeSnapshotProvider.CGWindowEntry]
    ) -> Bool {
        guard let targetCGWindowID else { return true }
        return currentWindows.contains { window in
            window.id == targetCGWindowID
                && window.isOnscreen
                && RuntimeSnapshotProvider.cgWindowPassesValidityConstraints(window)
        }
    }

    private func scheduleFocusRecovery(for request: WindowFocusRequest, in app: NSRunningApplication) {
        guard !focusRecoveryRetryDelaysNanoseconds.isEmpty else { return }
        focusRecoveryTask?.cancel()
        let retryDelays = focusRecoveryRetryDelaysNanoseconds
        RuntimeLog.info(
            "Activation",
            "focus-recovery scheduled pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(request.targetCGWindowID(expectedPID: app.processIdentifier).map(String.init) ?? "nil") delaysNs=\(retryDelays)"
        )
        focusRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.focusRecoveryTask = nil }

            for (attemptIndex, delay) in retryDelays.enumerated() {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard !Task.isCancelled else { return }
                RuntimeLog.info(
                    "Activation",
                    "focus-recovery attempt=\(attemptIndex + 1) pid=\(app.processIdentifier) windowID=\(request.windowID)"
                )
                if self.attemptWindowFocus(request, in: app) {
                    RuntimeLog.info(
                        "Activation",
                        "focus-recovery verified attempt=\(attemptIndex + 1) pid=\(app.processIdentifier) windowID=\(request.windowID)"
                    )
                    return
                }
            }
            RuntimeLog.info(
                "Activation",
                "focus-recovery exhausted pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(request.targetCGWindowID(expectedPID: app.processIdentifier).map(String.init) ?? "nil")"
            )
        }
    }

    private func requestActivation(
        of app: NSRunningApplication,
        completion: ((NSRunningApplication) -> Void)? = nil
    ) {
        if let requestActivationOverride {
            requestActivationOverride(app, completion)
            return
        }
        guard let bundleURL = app.bundleURL else {
            _ = app.activate()
            completeActivation(app, completion: completion)
            return
        }

        // On modern macOS, NSWorkspace participates in cooperative activation
        // and is more reliable than asking the target process to activate itself.
        NSWorkspace.shared.openApplication(
            at: bundleURL,
            configuration: Self.makeOpenConfiguration()
        ) { openedApp, error in
            if let error {
                RuntimeLog.info(
                    "Activation",
                    "openApplication failed pid=\(app.processIdentifier) bundle=\(app.bundleIdentifier ?? "nil") error=\(error.localizedDescription)"
                )
                _ = app.activate()
                self.completeActivation(app, completion: completion)
                return
            }

            self.completeActivation(openedApp ?? app, completion: completion)
        }
    }

    private func completeActivation(
        _ app: NSRunningApplication,
        completion: ((NSRunningApplication) -> Void)?
    ) {
        guard let completion else { return }
        Task { @MainActor in
            completion(app)
        }
    }

    nonisolated static func makeOpenConfiguration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        return configuration
    }

    @discardableResult
    private func activateCurrentAppIfNeeded(_ app: NSRunningApplication) -> Bool {
        if let activateCurrentAppIfNeededOverride {
            return activateCurrentAppIfNeededOverride(app)
        }
        guard app.processIdentifier == ProcessInfo.processInfo.processIdentifier else {
            return false
        }
        AppWindowCoordinator.activateMainWindowOrOpenHomeScene()
        return true
    }

    private func focus(window: AXUIElement, restoreIfMinimized: Bool) -> Bool {
        var hasSuccessfulAction = false
        if restoreIfMinimized {
            let restoreResult = AXUIElementSetAttributeValue(
                window,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            )
            hasSuccessfulAction = hasSuccessfulAction || restoreResult == .success
        }
        let raiseResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        hasSuccessfulAction = hasSuccessfulAction || raiseResult == .success

        let mainResult = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        hasSuccessfulAction = hasSuccessfulAction || mainResult == .success

        let focusResult = AXUIElementSetAttributeValue(
            window,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        hasSuccessfulAction = hasSuccessfulAction || focusResult == .success
        return hasSuccessfulAction
    }

    private func focusAXWindow(
        _ window: AXUIElement,
        restoreIfMinimized: Bool,
        in app: NSRunningApplication
    ) -> Bool {
        guard AXWindowInspector.belongsToProcess(window, pid: app.processIdentifier) else {
            return false
        }
        if let focusAXWindowOverride, focusAXWindowOverride(window, restoreIfMinimized, app) {
            return true
        }
        return focus(window: window, restoreIfMinimized: restoreIfMinimized)
    }

    private func activationTargetApplication(
        for windowContext: RuntimeWindowContext,
        fallback: NSRunningApplication
    ) -> NSRunningApplication {
        guard windowContext.ownerPID != 0 else { return fallback }
        return NSRunningApplication(processIdentifier: windowContext.ownerPID) ?? fallback
    }

    private func currentAXWindows(
        for app: NSRunningApplication,
        includeRemoteWindows: Bool = false
    ) -> [AXUIElement] {
        if let currentAXWindowsOverride {
            return currentAXWindowsOverride(app)
        }
        return AXWindowInspector.windows(for: app, includeRemoteWindows: includeRemoteWindows)
    }

    private func focusCGWindow(
        _ cgWindowID: CGWindowID,
        in app: NSRunningApplication
    ) -> Bool {
        if let focusCGWindowOverride {
            return focusCGWindowOverride(app, cgWindowID)
        }
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return false
        }
        let didFocus = RuntimeCGWindowFocusBridge.focusWindow(
            ownerPID: app.processIdentifier,
            cgWindowID: cgWindowID
        )
        RuntimeLog.info(
            "Activation",
            "cg-window-focus \(didFocus ? "accepted" : "unavailable") pid=\(app.processIdentifier) windowID=\(cgWindowID)"
        )
        return didFocus
    }

    private func currentCGWindows(forPID pid: pid_t) -> [RuntimeSnapshotProvider.CGWindowEntry] {
        if let currentCGWindowsOverride {
            return currentCGWindowsOverride(pid)
        }
        guard
            let rawList = CGWindowListCopyWindowInfo(
                [.optionAll, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return []
        }

        var windowIDs: [CGWindowID] = []
        let windows: [RuntimeSnapshotProvider.CGWindowEntry] = rawList.compactMap { item in
            guard let ownerPID = item[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else {
                return nil
            }
            guard let layer = item[kCGWindowLayer as String] as? Int, layer == 0 else { return nil }
            guard let windowNumber = item[kCGWindowNumber as String] as? NSNumber else { return nil }
            let cgWindowID = CGWindowID(windowNumber.uint32Value)

            let title = (item[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let bounds = (item[kCGWindowBounds as String] as? [String: Any])
                .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }?
                .standardized
            let isOnscreen = (item[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            let alpha = (item[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
            let storeType = (item[kCGWindowStoreType as String] as? NSNumber)?.intValue ?? 1
            windowIDs.append(cgWindowID)
            return RuntimeSnapshotProvider.CGWindowEntry(
                id: cgWindowID,
                title: title,
                bounds: bounds,
                isOnscreen: isOnscreen,
                alpha: alpha,
                storeType: storeType
            )
        }
        let spaceIDsByWindowID = RuntimeCGSpaceInspector.spaceIDsByWindowID(windowIDs)
        guard !spaceIDsByWindowID.isEmpty else { return windows }
        return windows.map { window in
            RuntimeSnapshotProvider.CGWindowEntry(
                id: window.id,
                title: window.title,
                bounds: window.bounds,
                isOnscreen: window.isOnscreen,
                alpha: window.alpha,
                storeType: window.storeType,
                spaceIDs: spaceIDsByWindowID[window.id] ?? window.spaceIDs
            )
        }
    }

    private func axWindowFrame(for window: AXUIElement) -> CGRect? {
        if let axWindowFrameOverride {
            return axWindowFrameOverride(window)
        }
        return AXWindowInspector.frame(for: window)
    }

    private func axWindowTitle(for window: AXUIElement) -> String? {
        if let axWindowTitleOverride {
            return axWindowTitleOverride(window)
        }
        return AXWindowInspector.title(for: window)
    }

    private func resolveAXWindow(
        matchingCGWindowID targetCGWindowID: CGWindowID?,
        expectedTitle: String,
        expectedFrame: CGRect?,
        windows: [AXUIElement],
        in app: NSRunningApplication
    ) -> AXUIElement? {
        let cgWindows = currentCGWindows(forPID: app.processIdentifier)
        let axEntries = windows.enumerated().map { index, window in
            let title = axWindowTitle(for: window)
            return RuntimeSnapshotProvider.AXWindowEntry(
                index: index,
                id: AXWindowInspector.makeWindowID(pid: app.processIdentifier, index: index),
                title: title ?? expectedTitle,
                sourceTitle: title ?? expectedTitle,
                isMinimized: false,
                window: window,
                frame: axWindowFrame(for: window)
            )
        }
        guard let recovery = RuntimeSnapshotProvider.recoverAXWindowFromPublicSourcesWithDiagnostics(
            targetCGWindowID: targetCGWindowID,
            expectedTitle: expectedTitle,
            expectedFrame: expectedFrame,
            windows: axEntries,
            cgWindows: cgWindows,
            appName: app.localizedName ?? app.bundleIdentifier
        ) else {
            return nil
        }
        RuntimeLog.info(
            "Activation",
            "ax-recovery selected pid=\(app.processIdentifier) reason=\(recovery.reason) axID=\(recovery.window.id) title=\(runtimeActivationLogValue(recovery.window.sourceTitle ?? recovery.window.title)) bridgedCG=\(AXWindowInspector.cgWindowID(for: recovery.window.window).map(String.init) ?? "nil") frame=\(runtimeActivationFrameDescription(recovery.window.frame)) role=\(AXWindowInspector.role(for: recovery.window.window) ?? "nil") subrole=\(AXWindowInspector.subrole(for: recovery.window.window) ?? "nil")"
        )
        return recovery.window.window
    }

    nonisolated static func cgWindowID(from windowID: String, expectedPID: pid_t) -> CGWindowID? {
        let parts = windowID.split(separator: ":")
        guard parts.count == 3 else { return nil }
        guard parts[0] == "cg" else { return nil }
        guard let pid = pid_t(parts[1]), pid == expectedPID else { return nil }
        guard let rawWindowID = UInt32(parts[2]) else { return nil }
        return CGWindowID(rawWindowID)
    }

}

private func runtimeActivationFrontmostDescription() -> String {
    guard let app = NSWorkspace.shared.frontmostApplication else { return "nil" }
    return "\(app.bundleIdentifier ?? "nil"):\(app.processIdentifier)"
}

private func runtimeActivationCGWindowSummary(
    _ windows: [RuntimeSnapshotProvider.CGWindowEntry],
    targetCGWindowID: CGWindowID
) -> String {
    let firstOnscreen = windows.first(where: { $0.isOnscreen }).map { window in
        "\(window.id):\(runtimeActivationLogValue(window.title ?? "nil"))"
    } ?? "nil"
    let sample = windows.prefix(10).map { window in
        let marker = window.id == targetCGWindowID ? "*" : ""
        let onscreen = window.isOnscreen ? "on" : "off"
        let title = runtimeActivationLogValue(window.title ?? "nil")
        return "\(marker)\(window.id):\(title):\(onscreen):\(runtimeActivationFrameDescription(window.bounds))"
    }.joined(separator: ",")
    return "firstOnscreen=\(firstOnscreen) all=[\(sample)]"
}

private func runtimeActivationFrameDescription(_ frame: CGRect?) -> String {
    guard let frame else { return "nil" }
    return "\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.size.width))x\(Int(frame.size.height))"
}

private func runtimeActivationLogValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func runtimeCGWindowLooksLikeFullscreenActivationTarget(
    _ window: RuntimeSnapshotProvider.CGWindowEntry
) -> Bool {
    RuntimeWindowTopologyClassifier.hasOffDesktopSpace(spaceIDs: window.spaceIDs)
        && RuntimeWindowTopologyClassifier.isLikelyFullscreenContent(bounds: window.bounds)
}

private func runtimeCGWindowSharesOffDesktopSpace(
    _ lhs: RuntimeSnapshotProvider.CGWindowEntry,
    with rhs: RuntimeSnapshotProvider.CGWindowEntry
) -> Bool {
    let lhsSpaceIDs = Set(
        RuntimeWindowTopologyClassifier.normalizedSpaceIDs(lhs.spaceIDs)
            .filter { $0 != RuntimeWindowTopologyClassifier.desktopSpaceID }
    )
    guard !lhsSpaceIDs.isEmpty else { return false }
    let rhsSpaceIDs = Set(
        RuntimeWindowTopologyClassifier.normalizedSpaceIDs(rhs.spaceIDs)
            .filter { $0 != RuntimeWindowTopologyClassifier.desktopSpaceID }
    )
    guard !rhsSpaceIDs.isEmpty else { return false }
    return !lhsSpaceIDs.isDisjoint(with: rhsSpaceIDs)
}

private func runtimeCGWindowLooksLikeRelatedFullscreenAXSurface(
    _ window: RuntimeSnapshotProvider.CGWindowEntry,
    targetFrame: CGRect?
) -> Bool {
    guard
        let bounds = window.bounds?.standardized,
        let targetFrame = targetFrame?.standardized,
        RuntimeWindowTopologyClassifier.isLikelyFullscreenContent(bounds: targetFrame)
    else {
        return false
    }
    guard bounds.width >= targetFrame.width * 0.7 else { return false }
    guard bounds.height > 0, bounds.height <= targetFrame.height * 0.6 else { return false }
    guard abs(bounds.minX - targetFrame.minX) <= 90 else { return false }
    guard bounds.minY >= targetFrame.minY else { return false }
    guard bounds.minY <= targetFrame.minY + targetFrame.height * 0.6 else { return false }
    return true
}

private func runtimeCGWindowLooksLikeSameSpaceActivationSurface(
    _ window: RuntimeSnapshotProvider.CGWindowEntry,
    targetFrame: CGRect?
) -> Bool {
    guard window.storeType == 1 else { return false }
    guard
        let bounds = window.bounds?.standardized,
        let targetFrame = targetFrame?.standardized,
        RuntimeWindowTopologyClassifier.isLikelyFullscreenContent(bounds: targetFrame)
    else {
        return false
    }
    guard !RuntimeWindowTopologyClassifier.isLikelyFullscreenContent(bounds: bounds) else {
        return false
    }
    guard bounds.width >= targetFrame.width * 0.5 else { return false }
    guard bounds.height > 0, bounds.height <= targetFrame.height * 0.6 else { return false }
    guard abs(bounds.minX - targetFrame.minX) <= 120 else { return false }
    guard bounds.minY >= targetFrame.minY else { return false }
    guard bounds.minY <= targetFrame.minY + targetFrame.height * 0.7 else { return false }
    return true
}

private func runtimeCGSameSpaceActivationCandidateSort(
    _ lhs: RuntimeSnapshotProvider.CGWindowEntry,
    _ rhs: RuntimeSnapshotProvider.CGWindowEntry
) -> Bool {
    let lhsArea = runtimeCGWindowArea(lhs)
    let rhsArea = runtimeCGWindowArea(rhs)
    if lhsArea != rhsArea {
        return lhsArea > rhsArea
    }
    return lhs.id < rhs.id
}

private func runtimeCGWindowArea(_ window: RuntimeSnapshotProvider.CGWindowEntry) -> CGFloat {
    guard let bounds = window.bounds?.standardized else { return 0 }
    return bounds.width * bounds.height
}
