import AppKit
import ApplicationServices
import Foundation
import FlowTabCore

@MainActor
final class RuntimeActivator {
    private struct WindowFocusRequest {
        let windowID: String
        let title: String
        let frame: CGRect?
        let preferredAXWindow: AXUIElement?
        let preferredActivationHandleID: String?
        let preferredCGWindowID: CGWindowID?
        let spaceIDs: [Int]
        let allowsPublicAXRecovery: Bool
        let restoreIfMinimized: Bool

        func targetCGWindowID(expectedPID: pid_t) -> CGWindowID? {
            preferredCGWindowID ?? RuntimeActivator.cgWindowID(from: windowID, expectedPID: expectedPID)
        }
    }

    private enum WindowFocusAttemptResult {
        case verified
        case focusedButUnverified
        case noFocusRoute
    }

    var activateCurrentAppIfNeededOverride: ((NSRunningApplication) -> Bool)?
    var requestActivationOverride: ((NSRunningApplication, ((NSRunningApplication) -> Void)?) -> Void)?
    var focusWindowOverride: ((String, String, Bool, NSRunningApplication) -> Void)?
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
            windowID: windowID,
            title: windowContext.title,
            frame: windowContext.frame,
            preferredAXWindow: windowContext.axWindow,
            preferredActivationHandleID: windowContext.activationHandleID,
            preferredCGWindowID: windowContext.cgWindowID,
            spaceIDs: windowContext.spaceIDs,
            allowsPublicAXRecovery: windowContext.allowsPublicAXRecovery,
            restoreIfMinimized: restoreIfMinimized || windowContext.isMinimized
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
            return true
        }

        let cgFocusResult = attemptCGWindowFocus(request, in: app)
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
            switch attemptAXWindowFocus(directWindow, request: request, in: app) {
            case .verified:
                return true
            case .focusedButUnverified:
                return false
            case .noFocusRoute:
                if cgFocusVerified {
                    return true
                }
            }
        }

        if cgFocusVerified {
            return true
        }

        guard request.allowsPublicAXRecovery else { return false }

        let targetCGWindowID = request.targetCGWindowID(expectedPID: app.processIdentifier)
        let windows = currentAXWindows(
            for: app,
            includeRemoteWindows: RuntimeWindowTopologyClassifier.hasOffDesktopSpace(
                spaceIDs: request.spaceIDs
            )
        )
        guard !windows.isEmpty else { return false }

        if let matchedWindow = resolveAXWindow(
            matchingCGWindowID: targetCGWindowID,
            expectedTitle: request.title,
            expectedFrame: request.frame,
            windows: windows,
            in: app
        ) {
            switch attemptAXWindowFocus(matchedWindow, request: request, in: app) {
            case .verified:
                return true
            case .focusedButUnverified, .noFocusRoute:
                return false
            }
        }

        return false
    }

    private func attemptAXWindowFocus(
        _ window: AXUIElement,
        request: WindowFocusRequest,
        in app: NSRunningApplication
    ) -> WindowFocusAttemptResult {
        guard focusAXWindow(window, restoreIfMinimized: request.restoreIfMinimized, in: app) else {
            return .noFocusRoute
        }
        guard focusAttemptVerified(request, in: app) else {
            return .focusedButUnverified
        }
        return .verified
    }

    private func focusAttemptVerified(
        _ request: WindowFocusRequest,
        in app: NSRunningApplication
    ) -> Bool {
        guard !request.spaceIDs.isEmpty else {
            return true
        }

        guard let targetCGWindowID = request.targetCGWindowID(expectedPID: app.processIdentifier) else {
            return true
        }

        return targetCGWindowIsVisible(targetCGWindowID, in: app)
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
        return targetCGWindowIsVisible(targetCGWindowID, in: app) ? .verified : .focusedButUnverified
    }

    private func targetCGWindowIsVisible(
        _ targetCGWindowID: CGWindowID?,
        in app: NSRunningApplication
    ) -> Bool {
        guard let targetCGWindowID else { return true }
        return currentCGWindows(forPID: app.processIdentifier).contains { window in
            window.id == targetCGWindowID
                && window.isOnscreen
                && RuntimeSnapshotProvider.cgWindowPassesValidityConstraints(window)
        }
    }

    private func scheduleFocusRecovery(for request: WindowFocusRequest, in app: NSRunningApplication) {
        guard !focusRecoveryRetryDelaysNanoseconds.isEmpty else { return }
        focusRecoveryTask?.cancel()
        let retryDelays = focusRecoveryRetryDelaysNanoseconds
        focusRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.focusRecoveryTask = nil }

            for delay in retryDelays {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard !Task.isCancelled else { return }
                if self.attemptWindowFocus(request, in: app) {
                    return
                }
            }
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

    nonisolated private static func cgWindowID(from windowID: String, expectedPID: pid_t) -> CGWindowID? {
        let parts = windowID.split(separator: ":")
        guard parts.count == 3 else { return nil }
        guard parts[0] == "cg" else { return nil }
        guard let pid = pid_t(parts[1]), pid == expectedPID else { return nil }
        guard let rawWindowID = UInt32(parts[2]) else { return nil }
        return CGWindowID(rawWindowID)
    }

}
