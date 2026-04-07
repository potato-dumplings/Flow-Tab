import AppKit
import ApplicationServices
import Foundation
import FlowTabCore

@MainActor
final class RuntimeActivator {
    var activateCurrentAppIfNeededOverride: ((NSRunningApplication) -> Bool)?
    var requestActivationOverride: ((NSRunningApplication, ((NSRunningApplication) -> Void)?) -> Void)?
    var focusWindowOverride: ((String, String, Bool, NSRunningApplication) -> Void)?
    var focusAXWindowOverride: ((AXUIElement, Bool, NSRunningApplication) -> Bool)?
    var liveWindowRegistry: AXLiveWindowRegistry = .shared
    var currentAXWindowsOverride: ((NSRunningApplication) -> [AXUIElement])?
    var currentCGWindowsOverride: ((pid_t) -> [RuntimeSnapshotProvider.CGWindowEntry])?
    var axWindowFrameOverride: ((AXUIElement) -> CGRect?)?
    var axWindowTitleOverride: ((AXUIElement) -> String?)?

    func activate(target: ActivationTarget, contextsByID: [String: RuntimeAppContext]) {
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
        requestActivation(of: targetApp) { [weak self] _ in
            guard let self else { return }
            self.focusWindow(
                withID: windowID,
                withTitle: windowContext.title,
                targetFrame: windowContext.frame,
                preferredAXWindow: windowContext.axWindow,
                preferredActivationHandleID: windowContext.activationHandleID,
                preferredCGWindowID: windowContext.cgWindowID,
                allowsPublicAXRecovery: windowContext.allowsPublicAXRecovery,
                restoreIfMinimized: restoreIfMinimized || windowContext.isMinimized,
                in: targetApp
            )
        }
    }

    private func focusWindow(
        withID targetWindowID: String,
        withTitle targetTitle: String,
        targetFrame: CGRect?,
        preferredAXWindow: AXUIElement?,
        preferredActivationHandleID: String?,
        preferredCGWindowID: CGWindowID?,
        allowsPublicAXRecovery: Bool,
        restoreIfMinimized: Bool,
        in app: NSRunningApplication
    ) {
        if let focusWindowOverride {
            focusWindowOverride(targetWindowID, targetTitle, restoreIfMinimized, app)
            return
        }

        let windowFromRegistry = liveWindowRegistry.window(
            forWindowID: preferredActivationHandleID ?? targetWindowID,
            expectedPID: app.processIdentifier
        )
        if let directWindow = preferredAXWindow ?? windowFromRegistry,
            focusAXWindow(directWindow, restoreIfMinimized: restoreIfMinimized, in: app)
        {
            return
        }

        let windows = currentAXWindows(for: app)
        guard !windows.isEmpty else { return }
        guard allowsPublicAXRecovery else { return }

        let targetCGWindowID = preferredCGWindowID
            ?? Self.cgWindowID(from: targetWindowID, expectedPID: app.processIdentifier)
        if let matchedWindow = resolveAXWindow(
            matchingCGWindowID: targetCGWindowID,
            expectedTitle: targetTitle,
            expectedFrame: targetFrame,
            windows: windows,
            in: app
        ),
            focusAXWindow(matchedWindow, restoreIfMinimized: restoreIfMinimized, in: app)
        {
            return
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

    private func currentAXWindows(for app: NSRunningApplication) -> [AXUIElement] {
        if let currentAXWindowsOverride {
            return currentAXWindowsOverride(app)
        }
        return AXWindowInspector.windows(for: app)
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

        return rawList.compactMap { item in
            guard let ownerPID = item[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else {
                return nil
            }
            guard let layer = item[kCGWindowLayer as String] as? Int, layer == 0 else { return nil }
            guard let windowNumber = item[kCGWindowNumber as String] as? NSNumber else { return nil }

            let title = (item[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let bounds = (item[kCGWindowBounds as String] as? [String: Any])
                .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }?
                .standardized
            let isOnscreen = (item[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            let alpha = (item[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
            let storeType = (item[kCGWindowStoreType as String] as? NSNumber)?.intValue ?? 1
            return RuntimeSnapshotProvider.CGWindowEntry(
                id: CGWindowID(windowNumber.uint32Value),
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
        return RuntimeSnapshotProvider.recoverAXWindowFromPublicSources(
            targetCGWindowID: targetCGWindowID,
            expectedTitle: expectedTitle,
            expectedFrame: expectedFrame,
            windows: axEntries,
            cgWindows: cgWindows,
            appName: app.localizedName ?? app.bundleIdentifier
        )?.window
    }

    private static func cgWindowID(from windowID: String, expectedPID: pid_t) -> CGWindowID? {
        let parts = windowID.split(separator: ":")
        guard parts.count == 3 else { return nil }
        guard parts[0] == "cg" else { return nil }
        guard let pid = pid_t(parts[1]), pid == expectedPID else { return nil }
        guard let rawWindowID = UInt32(parts[2]) else { return nil }
        return CGWindowID(rawWindowID)
    }

}
