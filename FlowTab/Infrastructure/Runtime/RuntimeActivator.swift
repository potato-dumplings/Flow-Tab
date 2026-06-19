import AppKit
import ApplicationServices
import Foundation
import FlowTabCore

struct ActivationConfirmationPolicy: Equatable {
    var retryDelaysNanoseconds: [UInt64]

    static let defaultFocusRecovery = ActivationConfirmationPolicy(
        retryDelaysNanoseconds: [50_000_000, 150_000_000]
    )

    var isEnabled: Bool {
        !retryDelaysNanoseconds.isEmpty
    }
}

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
    var windowFocusVerifiedHandler: ((RuntimeWindowFocusVerification) -> Void)?
    var windowFocusReadbackMismatchHandler: ((WindowBindingReadbackDiagnostic) -> Void)?
    var focusAXWindowOverride: ((AXUIElement, Bool, NSRunningApplication) -> Bool)?
    var liveWindowRegistry: AXLiveWindowRegistry = .shared
    var currentAXWindowsOverride: ((NSRunningApplication) -> [AXUIElement])?
    var currentCGWindowsOverride: ((pid_t) -> [RuntimeCGWindowEntry])?
    var axWindowFrameOverride: ((AXUIElement) -> CGRect?)?
    var axWindowTitleOverride: ((AXUIElement) -> String?)?
    var focusedAXWindowOverride: ((NSRunningApplication) -> AXUIElement?)?
    var focusCGWindowOverride: ((NSRunningApplication, CGWindowID) -> Bool)?
    var activationConfirmationPolicy: ActivationConfirmationPolicy = .defaultFocusRecovery
    var focusRecoveryRetryDelaysNanoseconds: [UInt64] {
        get {
            activationConfirmationPolicy.retryDelaysNanoseconds
        }
        set {
            activationConfirmationPolicy = ActivationConfirmationPolicy(
                retryDelaysNanoseconds: newValue
            )
        }
    }

    private var focusRecoveryTask: Task<Void, Never>?
    private var focusRecoveryGeneration: UInt64 = 0

    func activate(target: ActivationTarget, contextsByID: [String: RuntimeAppContext]) {
        focusRecoveryTask?.cancel()
        focusRecoveryTask = nil
        focusRecoveryGeneration &+= 1

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
            bindingConfidence: windowContext.bindingConfidence,
            bindingAllowedActions: windowContext.bindingAllowedActions,
            restoreIfMinimized: restoreIfMinimized || windowContext.isMinimized
        )
        let mode = RuntimeWindowDiagnostics.displayMode(
            frame: windowContext.frame,
            spaceIDs: windowContext.spaceIDs,
            confirmationSource: windowContext.lastConfirmationSource
        )
        let identity = RuntimeWindowDiagnostics.activationIdentity(
            activationHandleID: windowContext.activationHandleID,
            hasAXWindow: windowContext.axWindow != nil,
            cgWindowID: windowContext.cgWindowID,
            hasStickyBinding: windowContext.hasStickyBinding
        )
        RuntimeLog.info(
            .activation,
            "window-request appID=\(appID) pid=\(targetApp.processIdentifier) windowID=\(windowID) title=\(runtimeActivationLogValue(windowContext.title)) mode=\(mode) identity=\(identity) cg=\(windowContext.cgWindowID.map(String.init) ?? "nil") handle=\(windowContext.activationHandleID ?? "nil") ax=\(windowContext.axWindow == nil ? 0 : 1) fallbackAX=0 spaces=\(windowContext.spaceIDs) frame=\(runtimeActivationFrameDescription(windowContext.frame)) restore=\(request.restoreIfMinimized) sticky=\(windowContext.hasStickyBinding) source=\(windowContext.lastConfirmationSource?.rawValue ?? "nil") publicAXRecovery=\(windowContext.allowsPublicAXRecovery ? 1 : 0)"
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
        guard request.allowsAnyActivationRoute else {
            if bindingAllowsChromeInternalActivationBypass(request, in: app) {
                _ = finishChromeInternalWindowFocusIfVerified(request, in: app)
                return
            }
            RuntimeLog.debug(
                .activation,
                "focus-attempt skipped pid=\(app.processIdentifier) windowID=\(request.windowID) reason=binding_action_disallowed allowedActions=\(activationAllowedActionsDescription(request.bindingAllowedActions))"
            )
            return
        }
        guard !attemptWindowFocus(request, in: app, allowChromeInternalFocus: true) else { return }
        scheduleFocusRecovery(for: request, in: app)
    }

    private func bindingAllowsChromeInternalActivationBypass(
        _ request: WindowFocusRequest,
        in app: NSRunningApplication
    ) -> Bool {
        guard request.bindingConfidence != .ambiguous else { return false }
        guard request.targetCGWindowID(expectedPID: app.processIdentifier) != nil else {
            return false
        }
        return RuntimeChromeWindowFocusBridge.scriptableBrowserSpec(for: app) != nil
    }

    private func bindingAllowsChromeInternalActivationRoute(
        _ request: WindowFocusRequest,
        in app: NSRunningApplication
    ) -> Bool {
        if request.bindingAllowedActions.contains(.useForCGActivationFallback) {
            return true
        }
        if bindingAllowsChromeInternalActivationBypass(request, in: app) {
            RuntimeLog.debug(
                .activation,
                "focus-attempt route=chrome-internal allowed pid=\(app.processIdentifier) windowID=\(request.windowID) reason=chrome_binding_bypass confidence=\(request.bindingConfidence.rawValue) allowedActions=\(activationAllowedActionsDescription(request.bindingAllowedActions))"
            )
            return true
        }
        RuntimeLog.debug(
            .activation,
            "focus-attempt route=chrome-internal skipped pid=\(app.processIdentifier) windowID=\(request.windowID) reason=binding_action_disallowed requiredAction=\(WindowBindingAction.useForCGActivationFallback.rawValue) allowedActions=\(activationAllowedActionsDescription(request.bindingAllowedActions))"
        )
        return false
    }

    @discardableResult
    private func attemptWindowFocus(
        _ request: WindowFocusRequest,
        in app: NSRunningApplication,
        allowChromeInternalFocus: Bool
    ) -> Bool {
        if let focusWindowOverride {
            focusWindowOverride(request.windowID, request.title, request.restoreIfMinimized, app)
            return reportWindowFocusVerified(request, in: app)
        }

        let cgFocusResult = attemptCGWindowFocus(request, in: app)
        RuntimeLog.debug(
            .activation,
            "focus-attempt route=cg result=\(cgFocusResult.debugName) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(request.targetCGWindowID(expectedPID: app.processIdentifier).map(String.init) ?? "nil") frontmost=\(runtimeActivationFrontmostDescription())"
        )
        let cgFocusVerified: Bool
        let cgFocusWasAccepted: Bool
        switch cgFocusResult {
        case .verified:
            cgFocusVerified = true
            cgFocusWasAccepted = true
        case .focusedButUnverified:
            cgFocusVerified = false
            cgFocusWasAccepted = true
        case .noFocusRoute:
            cgFocusVerified = false
            cgFocusWasAccepted = false
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
            RuntimeLog.debug(
                .activation,
                "focus-attempt route=ax-direct result=\(axFocusResult.debugName) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(request.targetCGWindowID(expectedPID: app.processIdentifier).map(String.init) ?? "nil")"
            )
            switch axFocusResult {
            case .verified:
                return reportWindowFocusVerified(request, in: app)
            case .focusedButUnverified:
                if allowChromeInternalFocus, finishChromeInternalWindowFocusIfVerified(request, in: app) {
                    return true
                }
                return false
            case .noFocusRoute:
                if cgFocusVerified {
                    return reportWindowFocusVerified(request, in: app)
                }
            }
        } else {
            RuntimeLog.debug(
                .activation,
                "ax-direct unavailable pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(request.targetCGWindowID(expectedPID: app.processIdentifier).map(String.init) ?? "nil") handle=\(request.preferredActivationHandleID ?? "nil") preferredAX=0 registryAX=0"
            )
        }

        if cgFocusVerified {
            return reportWindowFocusVerified(request, in: app)
        }

        guard request.allowsPublicAXRecovery else {
            RuntimeLog.debug(
                .activation,
                "ax-recovery skipped pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(request.targetCGWindowID(expectedPID: app.processIdentifier).map(String.init) ?? "nil") reason=disabled"
            )
            return false
        }

        let targetCGWindowID = request.targetCGWindowID(expectedPID: app.processIdentifier)
        let includeRemoteWindows = RuntimeWindowTopologyClassifier.hasOffDesktopSpace(
            spaceIDs: request.spaceIDs
        )
        RuntimeLog.debug(
            .activation,
            "ax-recovery scan pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID.map(String.init) ?? "nil") includeRemote=\(includeRemoteWindows ? 1 : 0) spaces=\(request.spaceIDs) expectedTitle=\(runtimeActivationLogValue(request.title)) expectedFrame=\(runtimeActivationFrameDescription(request.frame))"
        )
        let windows = currentAXWindows(
            for: app,
            includeRemoteWindows: includeRemoteWindows
        )
        RuntimeLog.debug(
            .activation,
            "ax-recovery fetched pid=\(app.processIdentifier) windowID=\(request.windowID) count=\(windows.count)"
        )
        if cgFocusWasAccepted, targetCGWindowIsVisible(
            targetCGWindowID,
            in: app,
            currentWindows: currentCGWindows(forPID: app.processIdentifier)
        ) {
            RuntimeLog.debug(
                .activation,
                "focus-attempt route=ax-recovery-visible result=verified pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID.map(String.init) ?? "nil")"
            )
            return reportWindowFocusVerified(request, in: app)
        }
        if windows.isEmpty {
            RuntimeLog.debug(
                .activation,
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
                RuntimeLog.debug(
                    .activation,
                    "focus-attempt route=ax-public-recovery result=\(axFocusResult.debugName) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID.map(String.init) ?? "nil")"
                )
                switch axFocusResult {
                case .verified:
                    return reportWindowFocusVerified(request, in: app)
                case .focusedButUnverified, .noFocusRoute:
                    if allowChromeInternalFocus, finishChromeInternalWindowFocusIfVerified(request, in: app) {
                        return true
                    }
                    return false
                }
            }

            if let relatedAXFocusResult = attemptRelatedAXWindowFocus(
                request,
                publicWindows: windows,
                in: app
            ) {
                RuntimeLog.debug(
                    .activation,
                    "focus-attempt route=ax-related result=\(relatedAXFocusResult.debugName) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID.map(String.init) ?? "nil")"
                )
                if relatedAXFocusResult == .verified {
                    return reportWindowFocusVerified(request, in: app)
                }
            }
        }

        if let sameSpaceCGFocusResult = attemptSameSpaceCGWindowFocus(request, in: app) {
            RuntimeLog.debug(
                .activation,
                "focus-attempt route=cg-same-space result=\(sameSpaceCGFocusResult.debugName) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID.map(String.init) ?? "nil")"
            )
            if sameSpaceCGFocusResult == .verified {
                return reportWindowFocusVerified(request, in: app)
            }
        }

        if allowChromeInternalFocus, finishChromeInternalWindowFocusIfVerified(request, in: app) {
            return true
        }

        RuntimeLog.debug(
            .activation,
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
        guard bindingAllowsAXFocusRoute(route, request: request, window: window, app: app) else {
            return .noFocusRoute
        }
        guard focusAXWindow(window, restoreIfMinimized: request.restoreIfMinimized, in: app) else {
            RuntimeLog.debug(
                .activation,
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
            RuntimeLog.debug(
                .activation,
                "focus-verify route=\(route) skipped=empty-spaces pid=\(app.processIdentifier) windowID=\(request.windowID)"
            )
            return true
        }

        guard let targetCGWindowID = request.targetCGWindowID(expectedPID: app.processIdentifier) else {
            RuntimeLog.debug(
                .activation,
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
        let focusedCGWindowID = focusedAXWindowCGWindowID(in: app)
        let focusedCGWindowMatches = focusedCGWindowID.map { $0 == targetCGWindowID } ?? true
        let hasFocusedCGWindowMatch = focusedCGWindowID == targetCGWindowID
        RuntimeLog.debug(
            .activation,
            "focus-verify route=\(route) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID) visible=\(isVisible ? 1 : 0) focusedCG=\(focusedCGWindowID.map(String.init) ?? "nil") windows=\(runtimeActivationCGWindowSummary(currentWindows, targetCGWindowID: targetCGWindowID))"
        )
        if !isVisible, !hasFocusedCGWindowMatch {
            reportBindingReadbackMismatch(
                request,
                route: route,
                reason: .targetCGNotVisible,
                targetCGWindowID: targetCGWindowID,
                focusedCGWindowID: focusedCGWindowID,
                currentWindows: currentWindows,
                in: app
            )
        }
        if isVisible, !focusedCGWindowMatches {
            reportBindingReadbackMismatch(
                request,
                route: route,
                reason: .focusedAXCGWindowMismatch,
                targetCGWindowID: targetCGWindowID,
                focusedCGWindowID: focusedCGWindowID,
                currentWindows: currentWindows,
                in: app
            )
        }
        return (isVisible && focusedCGWindowMatches) || hasFocusedCGWindowMatch
    }

    private func attemptCGWindowFocus(
        _ request: WindowFocusRequest,
        in app: NSRunningApplication
    ) -> WindowFocusAttemptResult {
        guard bindingAllowsActivationAction(
            .useForCGActivationFallback,
            route: "cg",
            request: request,
            app: app
        ) else {
            return .noFocusRoute
        }
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
        RuntimeLog.debug(
            .activation,
            "cg-window-focus verify pid=\(app.processIdentifier) targetCG=\(targetCGWindowID) visible=\(isVisible ? 1 : 0) windows=\(runtimeActivationCGWindowSummary(currentWindows, targetCGWindowID: targetCGWindowID))"
        )
        if !isVisible {
            reportBindingReadbackMismatch(
                request,
                route: "cg",
                reason: .targetCGNotVisible,
                targetCGWindowID: targetCGWindowID,
                focusedCGWindowID: nil,
                currentWindows: currentWindows,
                in: app
            )
        }
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
        RuntimeLog.debug(
            .activation,
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
        RuntimeLog.debug(
            .activation,
            "ax-related verify pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID) candidateCG=\(AXWindowInspector.cgWindowID(for: candidate).map(String.init) ?? "nil") result=\(result.debugName)"
        )
        return result
    }

    private func attemptSameSpaceCGWindowFocus(
        _ request: WindowFocusRequest,
        in app: NSRunningApplication
    ) -> WindowFocusAttemptResult? {
        guard bindingAllowsActivationAction(
            .useForCGActivationFallback,
            route: "cg-same-space",
            request: request,
            app: app
        ) else {
            return nil
        }
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
        RuntimeLog.debug(
            .activation,
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
            RuntimeLog.debug(
                .activation,
                "cg-same-space verify pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID) candidateCG=\(candidate.id) visible=\(isVisible ? 1 : 0) windows=\(runtimeActivationCGWindowSummary(windowsAfterFocus, targetCGWindowID: targetCGWindowID))"
            )
            if isVisible {
                return .verified
            }
        }
        return .focusedButUnverified
    }

    private func finishChromeInternalWindowFocusIfVerified(
        _ request: WindowFocusRequest,
        in app: NSRunningApplication
    ) -> Bool {
        guard bindingAllowsChromeInternalActivationRoute(request, in: app) else {
            return false
        }
        guard let result = attemptChromeInternalWindowFocus(request, in: app) else {
            return false
        }
        RuntimeLog.debug(
            .activation,
            "focus-attempt route=chrome-internal result=\(result.debugName) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(request.targetCGWindowID(expectedPID: app.processIdentifier).map(String.init) ?? "nil")"
        )
        guard result == .verified else {
            return false
        }
        return reportWindowFocusVerified(request, in: app)
    }

    private func attemptChromeInternalWindowFocus(
        _ request: WindowFocusRequest,
        in app: NSRunningApplication
    ) -> WindowFocusAttemptResult? {
        guard let browserSpec = RuntimeChromeWindowFocusBridge.scriptableBrowserSpec(for: app) else {
            return nil
        }
        guard let targetCGWindowID = request.targetCGWindowID(expectedPID: app.processIdentifier) else {
            return nil
        }
        let currentWindows = currentCGWindows(forPID: app.processIdentifier)
        if targetCGWindowIsVisible(
            targetCGWindowID,
            in: app,
            currentWindows: currentWindows
        ) {
            return .verified
        }

        let query = RuntimeChromeWindowFocusBridge.candidateQuery(
            browser: browserSpec,
            expectedTitle: request.title,
            expectedFrame: request.frame
        )
        let candidates = query.candidates
        RuntimeLog.debug(
            .activation,
            "chrome-internal candidates browser=\(browserSpec.debugName) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID) chromeWindows=\(query.chromeWindowCount) count=\(candidates.count) error=\(runtimeActivationLogValue(query.error ?? "nil")) items=\(candidates.prefix(5).map(\.logDescription).joined(separator: ","))"
        )

        let candidateDecision = RuntimeChromeWindowFocusBridge.candidateDecision(
            query,
            targetCGWindowID: targetCGWindowID,
            fallbackTitle: request.title,
            fallbackFrame: request.frame,
            currentCGWindows: currentWindows
        )
        RuntimeLog.debug(
            .activation,
            "chrome-internal candidate-decision browser=\(browserSpec.debugName) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID) decision=\(candidateDecision.logDescription)"
        )
        guard let candidate = candidateDecision.selectedCandidate else {
            return .noFocusRoute
        }
        let focusResult = RuntimeChromeWindowFocusBridge.focusWindow(
            windowID: candidate.windowID,
            browser: browserSpec
        )
        RuntimeLog.debug(
            .activation,
            "chrome-internal focus browser=\(browserSpec.debugName) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID) candidate=\(candidate.windowID) accepted=\(focusResult.accepted ? 1 : 0) front=\(focusResult.frontWindowID.map(String.init) ?? "nil") error=\(runtimeActivationLogValue(focusResult.error ?? "nil"))"
        )
        guard focusResult.accepted else {
            return .noFocusRoute
        }
        guard verifyFocusAttempt(request, route: "chrome-internal", in: app) else {
            return .focusedButUnverified
        }
        return .verified
    }

    private func bindingAllowsAXFocusRoute(
        _ route: String,
        request: WindowFocusRequest,
        window: AXUIElement,
        app: NSRunningApplication
    ) -> Bool {
        let acceptedActions: Set<WindowBindingAction> = route == "direct"
            ? [.useForAXActivation]
            : [.useForAXActivation, .useForCGActivationFallback]
        if route == "direct",
           bindingAllowsVerifiedStickyDirectAXFallback(window, request: request, app: app) {
            RuntimeLog.debug(
                .activation,
                "focus-attempt route=ax-direct allowed pid=\(app.processIdentifier) windowID=\(request.windowID) reason=verified_sticky_cg_bridge targetCG=\(request.targetCGWindowID(expectedPID: app.processIdentifier).map(String.init) ?? "nil") allowedActions=\(activationAllowedActionsDescription(request.bindingAllowedActions))"
            )
            return true
        }
        guard !request.bindingAllowedActions.isDisjoint(with: acceptedActions) else {
            RuntimeLog.debug(
                .activation,
                "focus-attempt route=ax-\(route) skipped pid=\(app.processIdentifier) windowID=\(request.windowID) reason=binding_action_disallowed requiredActions=\(activationAllowedActionsDescription(acceptedActions)) allowedActions=\(activationAllowedActionsDescription(request.bindingAllowedActions))"
            )
            return false
        }
        return true
    }

    private func bindingAllowsVerifiedStickyDirectAXFallback(
        _ window: AXUIElement,
        request: WindowFocusRequest,
        app: NSRunningApplication
    ) -> Bool {
        guard request.bindingConfidence == .sticky else { return false }
        guard request.bindingAllowedActions.contains(.useForCGActivationFallback) else { return false }
        guard let targetCGWindowID = request.targetCGWindowID(expectedPID: app.processIdentifier) else {
            return false
        }
        return AXWindowInspector.cgWindowID(for: window) == targetCGWindowID
    }

    private func bindingAllowsActivationAction(
        _ action: WindowBindingAction,
        route: String,
        request: WindowFocusRequest,
        app: NSRunningApplication
    ) -> Bool {
        guard request.bindingAllowedActions.contains(action) else {
            RuntimeLog.debug(
                .activation,
                "focus-attempt route=\(route) skipped pid=\(app.processIdentifier) windowID=\(request.windowID) reason=binding_action_disallowed requiredAction=\(action.rawValue) allowedActions=\(activationAllowedActionsDescription(request.bindingAllowedActions))"
            )
            return false
        }
        return true
    }

    private func activationAllowedActionsDescription(
        _ allowedActions: Set<WindowBindingAction>
    ) -> String {
        allowedActions
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
    }

    private func reportBindingReadbackMismatch(
        _ request: WindowFocusRequest,
        route: String,
        reason: WindowBindingReadbackMismatchReason,
        targetCGWindowID: CGWindowID?,
        focusedCGWindowID: CGWindowID? = nil,
        currentWindows: [RuntimeCGWindowEntry],
        in app: NSRunningApplication
    ) {
        let visibleCGWindowIDs = currentWindows
            .filter { $0.isOnscreen && RuntimeSnapshotProvider.cgWindowPassesValidityConstraints($0) }
            .map(\.id)
        let diagnostic = WindowBindingReadbackDiagnostic(
            appID: request.appID,
            windowID: request.windowID,
            ownerPID: request.ownerPID,
            route: route,
            reason: reason,
            targetCGWindowID: targetCGWindowID,
            focusedCGWindowID: focusedCGWindowID,
            visibleCGWindowIDs: visibleCGWindowIDs,
            bindingConfidence: request.bindingConfidence,
            allowedActions: request.bindingAllowedActions
        )
        windowFocusReadbackMismatchHandler?(diagnostic)
        RuntimeLog.debug(
            .activation,
            "binding-readback-mismatch route=\(route) pid=\(app.processIdentifier) windowID=\(request.windowID) reason=\(reason.rawValue) targetCG=\(targetCGWindowID.map(String.init) ?? "nil") focusedCG=\(focusedCGWindowID.map(String.init) ?? "nil") confidence=\(request.bindingConfidence.rawValue) allowedActions=\(activationAllowedActionsDescription(request.bindingAllowedActions)) visibleCG=\(visibleCGWindowIDs.map(String.init).joined(separator: ","))"
        )
    }

    private func focusedAXWindowCGWindowID(in app: NSRunningApplication) -> CGWindowID? {
        focusedAXWindow(in: app).flatMap { AXWindowInspector.cgWindowID(for: $0) }
    }

    private func focusedAXWindow(in app: NSRunningApplication) -> AXUIElement? {
        if let focusedAXWindowOverride {
            return focusedAXWindowOverride(app)
        }
        guard AccessibilityPermissionChecker.isTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard case .success(let focusedWindow) = AXTypedAttributeReader.elementAttribute(
            appElement,
            kAXFocusedWindowAttribute as CFString
        ) else {
            return nil
        }
        return focusedWindow
    }

    func currentFocusedAXWindowCGWindowIDForReconciliation(in app: NSRunningApplication) -> CGWindowID? {
        focusedAXWindowCGWindowID(in: app)
    }

    func currentFocusedAXWindowForReconciliation(in app: NSRunningApplication) -> AXUIElement? {
        focusedAXWindow(in: app)
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
        currentWindows: [RuntimeCGWindowEntry]
    ) -> Bool {
        guard let targetCGWindowID else { return true }
        return currentWindows.contains { window in
            window.id == targetCGWindowID
                && window.isOnscreen
                && RuntimeSnapshotProvider.cgWindowPassesValidityConstraints(window)
        }
    }

    private func scheduleFocusRecovery(for request: WindowFocusRequest, in app: NSRunningApplication) {
        let policy = activationConfirmationPolicy
        guard policy.isEnabled else { return }
        focusRecoveryTask?.cancel()
        focusRecoveryGeneration &+= 1
        let generation = focusRecoveryGeneration
        let retryDelays = policy.retryDelaysNanoseconds
        RuntimeLog.info(
            .activation,
            "focus-recovery scheduled generation=\(generation) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(request.targetCGWindowID(expectedPID: app.processIdentifier).map(String.init) ?? "nil") attempts=\(policy.retryDelaysNanoseconds.count) delaysNs=\(retryDelays)"
        )
        focusRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.focusRecoveryGeneration == generation {
                    self.focusRecoveryTask = nil
                }
            }

            for (attemptIndex, delay) in retryDelays.enumerated() {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard !Task.isCancelled else { return }
                guard self.focusRecoveryGeneration == generation else { return }
                RuntimeLog.debug(
                    .activation,
                    "focus-recovery attempt=\(attemptIndex + 1) generation=\(generation) delayNs=\(delay) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(request.targetCGWindowID(expectedPID: app.processIdentifier).map(String.init) ?? "nil")"
                )
                if self.attemptWindowFocus(request, in: app, allowChromeInternalFocus: false) {
                    RuntimeLog.info(
                        .activation,
                        "focus-recovery verified attempt=\(attemptIndex + 1) generation=\(generation) pid=\(app.processIdentifier) windowID=\(request.windowID)"
                    )
                    return
                }
            }
            RuntimeLog.error(
                .activation,
                "focus-recovery exhausted generation=\(generation) attempts=\(retryDelays.count) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(request.targetCGWindowID(expectedPID: app.processIdentifier).map(String.init) ?? "nil")"
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
                    .activation,
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
        let focusResult = RuntimeCGWindowFocusBridge.focusWindowDetailed(
            ownerPID: app.processIdentifier,
            cgWindowID: cgWindowID
        )
        RuntimeLog.debug(
            .activation,
            "cg-window-focus result=\(focusResult.debugName) accepted=\(focusResult.isAccepted ? 1 : 0) pid=\(app.processIdentifier) windowID=\(cgWindowID)"
        )
        return focusResult.isAccepted
    }

    private func currentCGWindows(forPID pid: pid_t) -> [RuntimeCGWindowEntry] {
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
        let windows: [RuntimeCGWindowEntry] = rawList.compactMap { item in
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
            return RuntimeCGWindowEntry(
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
            RuntimeCGWindowEntry(
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
            return RuntimeAXWindowEntry(
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
        RuntimeLog.debug(
            .activation,
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
    _ windows: [RuntimeCGWindowEntry],
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
    _ window: RuntimeCGWindowEntry
) -> Bool {
    RuntimeWindowTopologyClassifier.hasOffDesktopSpace(spaceIDs: window.spaceIDs)
        && RuntimeWindowTopologyClassifier.isLikelyFullscreenContent(bounds: window.bounds)
}

private func runtimeCGWindowSharesOffDesktopSpace(
    _ lhs: RuntimeCGWindowEntry,
    with rhs: RuntimeCGWindowEntry
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
    _ window: RuntimeCGWindowEntry,
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
    _ window: RuntimeCGWindowEntry,
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
    _ lhs: RuntimeCGWindowEntry,
    _ rhs: RuntimeCGWindowEntry
) -> Bool {
    let lhsArea = runtimeCGWindowArea(lhs)
    let rhsArea = runtimeCGWindowArea(rhs)
    if lhsArea != rhsArea {
        return lhsArea > rhsArea
    }
    return lhs.id < rhs.id
}

private func runtimeCGWindowArea(_ window: RuntimeCGWindowEntry) -> CGFloat {
    guard let bounds = window.bounds?.standardized else { return 0 }
    return bounds.width * bounds.height
}
