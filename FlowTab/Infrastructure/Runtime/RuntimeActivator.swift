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
        if activateCurrentAppIfNeeded(context.runningApp) {
            return
        }
        guard let windowContext = context.windowsByID[windowID] else {
            requestActivation(of: context.runningApp)
            return
        }
        requestActivation(of: context.runningApp) { [weak self] activatedApp in
            guard let self else { return }
            self.focusWindow(
                withID: windowID,
                withTitle: windowContext.title,
                preferredAXWindow: windowContext.axWindow,
                restoreIfMinimized: restoreIfMinimized || windowContext.isMinimized,
                in: activatedApp
            )
        }
    }

    private func focusWindow(
        withID targetWindowID: String,
        withTitle targetTitle: String,
        preferredAXWindow: AXUIElement?,
        restoreIfMinimized: Bool,
        in app: NSRunningApplication
    ) {
        if let focusWindowOverride {
            focusWindowOverride(targetWindowID, targetTitle, restoreIfMinimized, app)
            return
        }

        let windowFromRegistry = liveWindowRegistry.window(
            forWindowID: targetWindowID,
            expectedPID: app.processIdentifier
        )
        if
            let directWindow = preferredAXWindow ?? windowFromRegistry,
            AXWindowInspector.belongsToProcess(directWindow, pid: app.processIdentifier)
        {
            if let focusAXWindowOverride, focusAXWindowOverride(directWindow, restoreIfMinimized, app) {
                return
            }
            focus(window: directWindow, restoreIfMinimized: restoreIfMinimized)
            return
        }

        let windows = AXWindowInspector.windows(for: app)
        guard !windows.isEmpty else { return }

        if
            let index = AXWindowInspector.windowIndex(
                from: targetWindowID,
                expectedPID: app.processIdentifier
            ),
            windows.indices.contains(index)
        {
            focus(
                window: windows[index],
                restoreIfMinimized: restoreIfMinimized
            )
            return
        }

        for window in windows {
            guard let title = AXWindowInspector.title(for: window), title == targetTitle else { continue }
            focus(window: window, restoreIfMinimized: restoreIfMinimized)
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

    private func focus(window: AXUIElement, restoreIfMinimized: Bool) {
        if restoreIfMinimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

}
