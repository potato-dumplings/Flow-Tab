import AppKit
import ApplicationServices
import Foundation
import FlowTabCore

@MainActor
final class RuntimeActivator {
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
    var frontmostApplicationOverride: (() -> NSRunningApplication?)?
    var applicationIsTerminatedOverride: ((NSRunningApplication) -> Bool)?
    var focusRecoveryPolicy: RuntimeFocusRecoveryPolicy = .standard
    let focusRecoveryCoordinator: RuntimeFocusRecoveryCoordinator
    var activationGeneration: UInt64 = 0

    init(
        focusRecoveryScheduler: (any RuntimeFocusRecoveryScheduling)? = nil,
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter =
            NSWorkspace.shared.notificationCenter
    ) {
        focusRecoveryCoordinator = RuntimeFocusRecoveryCoordinator(
            scheduler: focusRecoveryScheduler,
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
    }

    func activate(target: ActivationTarget, contextsByID: [String: RuntimeAppContext]) {
        activationGeneration &+= 1
        let generation = activationGeneration
        focusRecoveryCoordinator.cancel(reason: "newActivation")

        switch target {
        case .app(let appID, let fallback):
            activateApp(
                appID: appID,
                fallback: fallback,
                generation: generation,
                contextsByID: contextsByID
            )
        case .window(let appID, let windowID, let restoreIfMinimized):
            activateWindow(
                appID: appID,
                windowID: windowID,
                restoreIfMinimized: restoreIfMinimized,
                generation: generation,
                contextsByID: contextsByID
            )
        }
    }

    private func activateWindow(
        appID: String,
        windowID: String,
        restoreIfMinimized: Bool,
        generation: UInt64,
        contextsByID: [String: RuntimeAppContext]
    ) {
        guard let context = contextsByID[appID] else { return }
        guard let windowContext = context.windowsByID[windowID] else {
            requestActivation(
                of: context.runningApp,
                generation: generation
            )
            return
        }
        let targetApp = activationTargetApplication(for: windowContext, fallback: context.runningApp)
        if activateCurrentAppIfNeeded(targetApp) {
            return
        }

        let request = makeWindowFocusRequest(
            appID: appID,
            windowID: windowID,
            windowContext: windowContext,
            targetApp: targetApp,
            restoreIfMinimized: restoreIfMinimized
        )
        logWindowFocusRequest(
            request,
            windowContext: windowContext,
            targetApp: targetApp,
            route: "exact-window"
        )
        if request.targetCGWindowID(expectedPID: targetApp.processIdentifier) != nil {
            self.focusWindow(request, in: targetApp)
            return
        }

        requestActivation(of: targetApp, generation: generation) { [weak self] _ in
            guard let self else { return }
            self.focusWindow(request, in: targetApp)
        }
    }

    func focusWindow(_ request: WindowFocusRequest, in app: NSRunningApplication) {
        let allowsChromeInternalBypass =
            bindingAllowsChromeInternalActivationBypass(request, in: app)
        guard request.allowsAnyActivationRoute || allowsChromeInternalBypass else {
            RuntimeLog.debug(
                .activation,
                "focus-attempt skipped pid=\(app.processIdentifier) windowID=\(request.windowID) reason=binding_action_disallowed allowedActions=\(activationAllowedActionsDescription(request.bindingAllowedActions))"
            )
            return
        }
        let recoveryGeneration = startFocusRecovery(for: request, in: app)
        let isVerified: Bool
        if request.allowsAnyActivationRoute {
            isVerified = attemptWindowFocus(
                request,
                in: app,
                allowChromeInternalFocus: true
            )
        } else {
            isVerified = finishChromeInternalWindowFocusIfVerified(
                request,
                in: app
            )
        }
        if isVerified {
            completeFocusRecoveryInitialAction(
                generation: recoveryGeneration
            )
            return
        }
        performFocusRecoveryInitialReadback(
            generation: recoveryGeneration
        )
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
    func attemptWindowFocus(
        _ request: WindowFocusRequest,
        in app: NSRunningApplication,
        allowChromeInternalFocus: Bool
    ) -> Bool {
        if let focusWindowOverride {
            focusWindowOverride(request.windowID, request.title, request.restoreIfMinimized, app)
            guard let readback = verifyFocusAttempt(
                request,
                route: "override",
                in: app
            ) else {
                return false
            }
            return reportWindowFocusVerified(
                request,
                readback: readback,
                in: app
            )
        }

        let cgFocusResult = attemptCGWindowFocus(request, in: app)
        RuntimeLog.debug(
            .activation,
            "focus-attempt route=cg result=\(cgFocusResult.debugName) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(request.targetCGWindowID(expectedPID: app.processIdentifier).map(String.init) ?? "nil") frontmost=\(runtimeActivationFrontmostDescription())"
        )
        let cgFocusReadback: RuntimeWindowFocusReadbackEvidence?
        let cgFocusWasAccepted: Bool
        switch cgFocusResult {
        case let .verified(readback):
            cgFocusReadback = readback
            cgFocusWasAccepted = true
        case .focusedButUnverified:
            cgFocusReadback = nil
            cgFocusWasAccepted = true
        case .noFocusRoute:
            cgFocusReadback = nil
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
            case let .verified(readback):
                return reportWindowFocusVerified(
                    request,
                    readback: readback,
                    in: app
                )
            case .focusedButUnverified:
                if allowChromeInternalFocus, finishChromeInternalWindowFocusIfVerified(request, in: app) {
                    return true
                }
                return false
            case .noFocusRoute:
                if let cgFocusReadback {
                    return reportWindowFocusVerified(
                        request,
                        readback: cgFocusReadback,
                        in: app
                    )
                }
            }
        } else {
            RuntimeLog.debug(
                .activation,
                "ax-direct unavailable pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(request.targetCGWindowID(expectedPID: app.processIdentifier).map(String.init) ?? "nil") handle=\(request.preferredActivationHandleID ?? "nil") preferredAX=0 registryAX=0"
            )
        }

        if let cgFocusReadback {
            return reportWindowFocusVerified(
                request,
                readback: cgFocusReadback,
                in: app
            )
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
        if cgFocusWasAccepted {
            let currentWindows = currentCGWindows(forPID: app.processIdentifier)
            let focusReadback = currentWindowFocusReadbackEvidence(in: app)
            let focusState = RuntimeExactWindowFocusState(
                targetCGWindowID: targetCGWindowID,
                currentWindows: currentWindows,
                focusReadback: focusReadback
            )
            if focusState.isVerified {
                RuntimeLog.debug(
                    .activation,
                    "focus-attempt route=ax-recovery-readback result=verified pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID.map(String.init) ?? "nil")"
                )
                return reportWindowFocusVerified(
                    request,
                    readback: focusReadback,
                    in: app
                )
            }
            if focusState.targetIsVisible {
                RuntimeLog.debug(
                    .activation,
                    "focus-attempt route=ax-recovery-visible result=unverified pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID.map(String.init) ?? "nil")"
                )
            }
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
                case let .verified(readback):
                    return reportWindowFocusVerified(
                        request,
                        readback: readback,
                        in: app
                    )
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
                if let readback = relatedAXFocusResult.verifiedReadback {
                    return reportWindowFocusVerified(
                        request,
                        readback: readback,
                        in: app
                    )
                }
            }
        }

        if let sameSpaceCGFocusResult = attemptSameSpaceCGWindowFocus(request, in: app) {
            RuntimeLog.debug(
                .activation,
                "focus-attempt route=cg-same-space result=\(sameSpaceCGFocusResult.debugName) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID.map(String.init) ?? "nil")"
            )
            if let readback = sameSpaceCGFocusResult.verifiedReadback {
                return reportWindowFocusVerified(
                    request,
                    readback: readback,
                    in: app
                )
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
    ) -> RuntimeWindowFocusAttemptResult {
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
        guard let readback = verifyFocusAttempt(
            request,
            route: "ax-\(route)",
            in: app
        ) else {
            return .focusedButUnverified
        }
        return .verified(readback)
    }

    private func verifyFocusAttempt(
        _ request: WindowFocusRequest,
        route: String,
        in app: NSRunningApplication
    ) -> RuntimeWindowFocusReadbackEvidence? {
        let targetCGWindowID = request.targetCGWindowID(
            expectedPID: app.processIdentifier
        )
        let currentWindows = currentCGWindows(forPID: app.processIdentifier)
        let focusReadback = currentWindowFocusReadbackEvidence(in: app)
        let focusState = RuntimeExactWindowFocusState(
            targetCGWindowID: targetCGWindowID,
            currentWindows: currentWindows,
            focusReadback: focusReadback
        )
        RuntimeLog.debug(
            .activation,
            "focus-verify route=\(route) pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID.map(String.init) ?? "nil") visible=\(focusState.targetIsVisible ? 1 : 0) activationReadback=\(focusState.activationReadbackMatchesTarget ? 1 : 0) focusedCG=\(focusState.focusedCGWindowID.map(String.init) ?? "nil") frontmostCG=\(focusState.frontmostCGWindowID.map(String.init) ?? "nil") windows=\(targetCGWindowID.map { runtimeActivationCGWindowSummary(currentWindows, targetCGWindowID: $0) } ?? "no-target-cg")"
        )
        if let mismatchReason = focusState.mismatchReason {
            reportBindingReadbackMismatch(
                request,
                route: route,
                reason: mismatchReason,
                targetCGWindowID: targetCGWindowID,
                focusedCGWindowID: focusState.focusedCGWindowID,
                currentWindows: currentWindows,
                in: app
            )
        }
        guard focusState.isVerified else { return nil }
        return focusReadback
    }

    private func attemptCGWindowFocus(
        _ request: WindowFocusRequest,
        in app: NSRunningApplication
    ) -> RuntimeWindowFocusAttemptResult {
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
        let focusReadback = currentWindowFocusReadbackEvidence(in: app)
        let focusState = RuntimeExactWindowFocusState(
            targetCGWindowID: targetCGWindowID,
            currentWindows: currentWindows,
            focusReadback: focusReadback
        )
        RuntimeLog.debug(
            .activation,
            "cg-window-focus verify pid=\(app.processIdentifier) targetCG=\(targetCGWindowID) visible=\(focusState.targetIsVisible ? 1 : 0) activationReadback=\(focusState.activationReadbackMatchesTarget ? 1 : 0) frontmostCG=\(focusState.frontmostCGWindowID.map(String.init) ?? "nil") windows=\(runtimeActivationCGWindowSummary(currentWindows, targetCGWindowID: targetCGWindowID))"
        )
        if let mismatchReason = focusState.mismatchReason {
            reportBindingReadbackMismatch(
                request,
                route: "cg",
                reason: mismatchReason,
                targetCGWindowID: targetCGWindowID,
                focusedCGWindowID: focusState.focusedCGWindowID,
                currentWindows: currentWindows,
                in: app
            )
        }
        return focusState.isVerified
            ? .verified(focusReadback)
            : .focusedButUnverified
    }

    private func attemptRelatedAXWindowFocus(
        _ request: WindowFocusRequest,
        publicWindows: [AXUIElement],
        in app: NSRunningApplication
    ) -> RuntimeWindowFocusAttemptResult? {
        guard RuntimeWindowTopologyClassifier.hasOffDesktopSpace(spaceIDs: request.spaceIDs) else {
            return nil
        }
        guard let targetCGWindowID = request.targetCGWindowID(expectedPID: app.processIdentifier) else {
            return nil
        }
        let currentWindows = currentCGWindows(forPID: app.processIdentifier)
        guard
            let targetWindow = currentWindows.first(where: { $0.id == targetCGWindowID }),
            RuntimeWindowTopologyClassifier.isLikelyFullscreenActivationTarget(targetWindow)
        else {
            return nil
        }

        let candidates = publicWindows.compactMap { window -> AXUIElement? in
            guard let cgWindowID = AXWindowInspector.cgWindowID(for: window) else { return nil }
            guard cgWindowID != targetCGWindowID else { return nil }
            guard
                let cgWindow = currentWindows.first(where: { $0.id == cgWindowID }),
                RuntimeCGWindowFacts.passesValidityConstraints(cgWindow)
            else {
                return nil
            }
            guard RuntimeWindowTopologyClassifier.sharesOffDesktopSpace(cgWindow, with: targetWindow) else {
                return nil
            }
            guard RuntimeWindowTopologyClassifier.isLikelyRelatedFullscreenAXSurface(
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
    ) -> RuntimeWindowFocusAttemptResult? {
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
            RuntimeWindowTopologyClassifier.isLikelyFullscreenActivationTarget(targetWindow)
        else {
            return nil
        }

        let candidates = currentWindows.filter { window in
            guard window.id != targetCGWindowID else { return false }
            guard RuntimeWindowTopologyClassifier.sharesOffDesktopSpace(window, with: targetWindow) else {
                return false
            }
            return RuntimeWindowTopologyClassifier.isLikelySameSpaceActivationSurface(
                window,
                targetFrame: targetWindow.bounds ?? request.frame
            )
        }
        RuntimeLog.debug(
            .activation,
            "cg-same-space candidates pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID) count=\(candidates.count) ids=\(candidates.map { String($0.id) }.joined(separator: ","))"
        )
        guard !candidates.isEmpty else { return nil }

        for candidate in candidates.sorted(by: RuntimeWindowTopologyClassifier.activationCandidateSort) {
            guard focusCGWindow(candidate.id, in: app) else { continue }
            let windowsAfterFocus = currentCGWindows(forPID: app.processIdentifier)
            let focusReadback = currentWindowFocusReadbackEvidence(in: app)
            let focusState = RuntimeExactWindowFocusState(
                targetCGWindowID: targetCGWindowID,
                currentWindows: windowsAfterFocus,
                focusReadback: focusReadback
            )
            RuntimeLog.debug(
                .activation,
                "cg-same-space verify pid=\(app.processIdentifier) windowID=\(request.windowID) targetCG=\(targetCGWindowID) candidateCG=\(candidate.id) visible=\(focusState.targetIsVisible ? 1 : 0) activationReadback=\(focusState.activationReadbackMatchesTarget ? 1 : 0) frontmostCG=\(focusState.frontmostCGWindowID.map(String.init) ?? "nil") windows=\(runtimeActivationCGWindowSummary(windowsAfterFocus, targetCGWindowID: targetCGWindowID))"
            )
            if focusState.isVerified {
                return .verified(focusReadback)
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
        guard let readback = result.verifiedReadback else {
            return false
        }
        return reportWindowFocusVerified(
            request,
            readback: readback,
            in: app
        )
    }

    private func attemptChromeInternalWindowFocus(
        _ request: WindowFocusRequest,
        in app: NSRunningApplication
    ) -> RuntimeWindowFocusAttemptResult? {
        guard let browserSpec = RuntimeChromeWindowFocusBridge.scriptableBrowserSpec(for: app) else {
            return nil
        }
        guard let targetCGWindowID = request.targetCGWindowID(expectedPID: app.processIdentifier) else {
            return nil
        }
        let currentWindows = currentCGWindows(forPID: app.processIdentifier)
        let initialFocusReadback = currentWindowFocusReadbackEvidence(in: app)
        let initialFocusState = RuntimeExactWindowFocusState(
            targetCGWindowID: targetCGWindowID,
            currentWindows: currentWindows,
            focusReadback: initialFocusReadback
        )
        if initialFocusState.isVerified {
            return .verified(initialFocusReadback)
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
        guard let readback = verifyFocusAttempt(
            request,
            route: "chrome-internal",
            in: app
        ) else {
            return .focusedButUnverified
        }
        return .verified(readback)
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
            .filter { $0.isOnscreen && RuntimeCGWindowFacts.passesValidityConstraints($0) }
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

    func focusedAXWindow(in app: NSRunningApplication) -> AXUIElement? {
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

    func currentCGWindows(forPID pid: pid_t) -> [RuntimeCGWindowEntry] {
        if let currentCGWindowsOverride {
            return currentCGWindowsOverride(pid)
        }
        let onscreenWindows = cgWindows(
            forPID: pid,
            options: [.optionOnScreenOnly, .excludeDesktopElements]
        )
        let allWindows = cgWindows(
            forPID: pid,
            options: [.optionAll, .excludeDesktopElements]
        )
        let onscreenWindowIDs = Set(onscreenWindows.map(\.id))
        let windows = onscreenWindows + allWindows.filter { !onscreenWindowIDs.contains($0.id) }
        let windowIDs = windows.map(\.id)
        let spaceIDsByWindowID = RuntimeCGSpaceInspector.spaceIDsByWindowID(windowIDs)
        return RuntimeCGWindowFacts.mergingSpaceTopology(
            windows: windows,
            spaceIDsByCGWindowID: spaceIDsByWindowID
        )
    }

    private func cgWindows(
        forPID pid: pid_t,
        options: CGWindowListOption
    ) -> [RuntimeCGWindowEntry] {
        guard let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return rawList.compactMap { item in
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
            return RuntimeCGWindowEntry(
                id: cgWindowID,
                title: title,
                bounds: bounds,
                isOnscreen: isOnscreen,
                alpha: alpha,
                storeType: storeType
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
        guard let recovery = RuntimeAXWindowRecovery.recoverAXWindowFromPublicSourcesWithDiagnostics(
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

func runtimeActivationFrameDescription(_ frame: CGRect?) -> String {
    guard let frame else { return "nil" }
    return "\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.size.width))x\(Int(frame.size.height))"
}

func runtimeActivationLogValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
