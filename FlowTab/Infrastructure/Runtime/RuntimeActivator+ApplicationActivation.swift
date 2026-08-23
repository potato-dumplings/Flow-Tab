import AppKit
import FlowTabCore

extension RuntimeActivator {
    func activateApp(
        appID: String,
        fallback: AppActivationFallback?,
        generation: UInt64,
        contextsByID: [String: RuntimeAppContext]
    ) {
        guard let context = contextsByID[appID] else {
            RuntimeLog.debug(
                .activation,
                "app-activation result=missing-context appID=\(appID) generation=\(generation)"
            )
            return
        }
        guard applicationIsEligibleForSwitcherActivation(context.runningApp) else {
            logIneligibleApplicationActivation(appID: appID, app: context.runningApp)
            return
        }
        if activateCurrentAppIfNeeded(context.runningApp) {
            return
        }
        guard let fallback else {
            RuntimeLog.info(
                .activation,
                "app-activation route=public appID=\(appID) pid=\(context.runningApp.processIdentifier) generation=\(generation) fallback=nil"
            )
            requestActivation(
                of: context.runningApp,
                generation: generation
            )
            return
        }

        RuntimeLog.info(
            .activation,
            "app-activation route=public appID=\(appID) pid=\(context.runningApp.processIdentifier) generation=\(generation) fallback=\(fallback.windowID) restore=\(fallback.restoreIfMinimized ? 1 : 0)"
        )
        requestActivation(of: context.runningApp, generation: generation) { [weak self] openedApp in
            self?.completeAppActivation(
                appID: appID,
                fallback: fallback,
                generation: generation,
                context: context,
                openedApp: openedApp
            )
        }
    }

    private func completeAppActivation(
        appID: String,
        fallback: AppActivationFallback,
        generation: UInt64,
        context: RuntimeAppContext,
        openedApp: NSRunningApplication
    ) {
        guard activationGeneration == generation else {
            RuntimeLog.debug(
                .activation,
                "app-activation result=stale-generation appID=\(appID) pid=\(openedApp.processIdentifier) generation=\(generation) current=\(activationGeneration)"
            )
            return
        }
        guard applicationIsEligibleForSwitcherActivation(openedApp) else {
            logIneligibleApplicationActivation(appID: appID, app: openedApp)
            return
        }

        let currentWindows = currentCGWindows(forPID: openedApp.processIdentifier)
        let knownCGWindowIDs = Set(context.windowsByID.values.compactMap(\.cgWindowID))
        let visibleKnownCGWindowIDs = currentWindows.compactMap { window -> CGWindowID? in
            guard knownCGWindowIDs.contains(window.id) else { return nil }
            guard window.isOnscreen else { return nil }
            guard RuntimeCGWindowFacts.passesValidityConstraints(window) else { return nil }
            return window.id
        }
        let frontmostApp = frontmostApplication()
        let targetIsFrontmost = frontmostApp?.processIdentifier == openedApp.processIdentifier
        if targetIsFrontmost, !visibleKnownCGWindowIDs.isEmpty {
            RuntimeLog.info(
                .activation,
                "app-activation result=public-visible-window appID=\(appID) pid=\(openedApp.processIdentifier) generation=\(generation) visibleCG=\(visibleKnownCGWindowIDs.map(String.init).joined(separator: ","))"
            )
            return
        }

        guard let windowContext = context.windowsByID[fallback.windowID] else {
            RuntimeLog.debug(
                .activation,
                "app-activation result=missing-fallback-window appID=\(appID) pid=\(openedApp.processIdentifier) generation=\(generation) windowID=\(fallback.windowID)"
            )
            return
        }
        if let targetCGWindowID = windowContext.cgWindowID,
           !currentWindows.contains(where: { $0.id == targetCGWindowID }) {
            RuntimeLog.debug(
                .activation,
                "app-activation result=invalid-fallback-window appID=\(appID) pid=\(openedApp.processIdentifier) generation=\(generation) windowID=\(fallback.windowID) targetCG=\(targetCGWindowID)"
            )
            return
        }

        let targetApp = activationTargetApplication(
            for: windowContext,
            fallback: openedApp
        )
        guard applicationIsEligibleForSwitcherActivation(targetApp) else {
            logIneligibleApplicationActivation(appID: appID, app: targetApp)
            return
        }
        let request = makeWindowFocusRequest(
            appID: appID,
            windowID: fallback.windowID,
            windowContext: windowContext,
            targetApp: targetApp,
            restoreIfMinimized: fallback.restoreIfMinimized
        )
        logWindowFocusRequest(
            request,
            windowContext: windowContext,
            targetApp: targetApp,
            route: "app-fallback"
        )
        RuntimeLog.info(
            .activation,
            "app-activation result=fallback-window appID=\(appID) pid=\(targetApp.processIdentifier) generation=\(generation) windowID=\(fallback.windowID) frontmostPID=\(frontmostApp?.processIdentifier.description ?? "nil") visibleKnown=\(visibleKnownCGWindowIDs.count)"
        )
        focusWindow(request, in: targetApp)
    }

    func makeWindowFocusRequest(
        appID: String,
        windowID: String,
        windowContext: RuntimeWindowContext,
        targetApp: NSRunningApplication,
        restoreIfMinimized: Bool
    ) -> WindowFocusRequest {
        WindowFocusRequest(
            appID: appID,
            windowID: windowID,
            title: windowContext.title,
            frame: windowContext.frame,
            ownerPID: windowContext.ownerPID == 0
                ? targetApp.processIdentifier
                : windowContext.ownerPID,
            preferredAXWindow: windowContext.axWindow,
            preferredActivationHandleID: windowContext.activationHandleID,
            preferredCGWindowID: windowContext.cgWindowID,
            spaceIDs: windowContext.spaceIDs,
            allowsPublicAXRecovery: windowContext.allowsPublicAXRecovery,
            bindingConfidence: windowContext.bindingConfidence,
            bindingAllowedActions: windowContext.bindingAllowedActions,
            restoreIfMinimized: restoreIfMinimized || windowContext.isMinimized
        )
    }

    func logWindowFocusRequest(
        _ request: WindowFocusRequest,
        windowContext: RuntimeWindowContext,
        targetApp: NSRunningApplication,
        route: String
    ) {
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
            "window-request appID=\(request.appID) pid=\(targetApp.processIdentifier) windowID=\(request.windowID) title=\(runtimeActivationLogValue(windowContext.title)) mode=\(mode) identity=\(identity) cg=\(windowContext.cgWindowID.map(String.init) ?? "nil") handle=\(windowContext.activationHandleID ?? "nil") ax=\(windowContext.axWindow == nil ? 0 : 1) fallbackAX=0 spaces=\(windowContext.spaceIDs) frame=\(runtimeActivationFrameDescription(windowContext.frame)) restore=\(request.restoreIfMinimized) sticky=\(windowContext.hasStickyBinding) source=\(windowContext.lastConfirmationSource?.rawValue ?? "nil") publicAXRecovery=\(windowContext.allowsPublicAXRecovery ? 1 : 0) route=\(route)"
        )
    }

    func requestActivation(
        of app: NSRunningApplication,
        generation: UInt64,
        completion: ((NSRunningApplication) -> Void)? = nil
    ) {
        guard applicationIsEligibleForSwitcherActivation(app) else {
            logIneligibleApplicationActivation(
                appID: app.bundleIdentifier ?? "unknown",
                app: app
            )
            return
        }
        let guardedCompletion = completion.map { completion in
            { [weak self] (openedApp: NSRunningApplication) in
                guard let self else { return }
                guard self.activationGeneration == generation else {
                    RuntimeLog.debug(
                        .activation,
                        "app-activation result=stale-completion pid=\(openedApp.processIdentifier) generation=\(generation) current=\(self.activationGeneration)"
                    )
                    return
                }
                guard self.applicationIsEligibleForSwitcherActivation(openedApp) else {
                    self.logIneligibleApplicationActivation(
                        appID: openedApp.bundleIdentifier ?? "unknown",
                        app: openedApp
                    )
                    return
                }
                completion(openedApp)
            }
        }
        if let requestActivationOverride {
            requestActivationOverride(app, guardedCompletion)
            return
        }
        guard let bundleURL = app.bundleURL else {
            _ = app.activate()
            completeActivation(app, completion: guardedCompletion)
            return
        }

        NSWorkspace.shared.openApplication(
            at: bundleURL,
            configuration: Self.makeOpenConfiguration()
        ) { [weak self] openedApp, error in
            Task { @MainActor in
                guard let self else { return }
                guard self.activationGeneration == generation else {
                    RuntimeLog.debug(
                        .activation,
                        "app-activation result=stale-open-completion pid=\(app.processIdentifier) generation=\(generation) current=\(self.activationGeneration)"
                    )
                    return
                }
                if let error {
                    RuntimeLog.info(
                        .activation,
                        "openApplication failed pid=\(app.processIdentifier) bundle=\(app.bundleIdentifier ?? "nil") error=\(error.localizedDescription)"
                    )
                    _ = app.activate()
                    self.completeActivation(app, completion: guardedCompletion)
                    return
                }
                self.completeActivation(
                    openedApp ?? app,
                    completion: guardedCompletion
                )
            }
        }
    }

    private func completeActivation(
        _ app: NSRunningApplication,
        completion: ((NSRunningApplication) -> Void)?
    ) {
        guard let completion else { return }
        Task { @MainActor in
            guard self.applicationIsEligibleForSwitcherActivation(app) else {
                self.logIneligibleApplicationActivation(
                    appID: app.bundleIdentifier ?? "unknown",
                    app: app
                )
                return
            }
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
    func activateCurrentAppIfNeeded(_ app: NSRunningApplication) -> Bool {
        if let activateCurrentAppIfNeededOverride {
            return activateCurrentAppIfNeededOverride(app)
        }
        guard app.processIdentifier == ProcessInfo.processInfo.processIdentifier else {
            return false
        }
        AppWindowCoordinator.activateMainWindowOrOpenHomeScene()
        return true
    }

    func activationTargetApplication(
        for windowContext: RuntimeWindowContext,
        fallback: NSRunningApplication
    ) -> NSRunningApplication {
        guard windowContext.ownerPID != 0 else { return fallback }
        return NSRunningApplication(processIdentifier: windowContext.ownerPID) ?? fallback
    }

    private func frontmostApplication() -> NSRunningApplication? {
        frontmostApplicationOverride?() ?? NSWorkspace.shared.frontmostApplication
    }

    func applicationIsTerminated(_ app: NSRunningApplication) -> Bool {
        applicationIsTerminatedOverride?(app) ?? app.isTerminated
    }
}
