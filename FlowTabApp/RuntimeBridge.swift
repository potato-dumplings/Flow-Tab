import AppKit
import ApplicationServices
import Foundation
import FlowTabCore
import ScreenCaptureKit

enum WindowTitleBarStyleGuess: String {
    case dark
    case light
}

struct RuntimeSnapshot {
    let apps: [AppSwitchCandidate]
    let contextsByID: [String: RuntimeAppContext]
}

struct RuntimeAppContext {
    let appID: String
    let runningApp: NSRunningApplication
    let windowsByID: [String: RuntimeWindowContext]
}

struct RuntimeWindowContext {
    let id: String
    let title: String
    let isMinimized: Bool
    var cgWindowID: CGWindowID?
    var previewImage: NSImage?
    var inferredTitleBarStyle: WindowTitleBarStyleGuess?
}

@MainActor
final class RuntimeSnapshotProvider {
    private struct WindowListEntry {
        let windowID: String
        let title: String
        let isMinimized: Bool
        let cgWindowID: CGWindowID?
    }

    private struct CGWindowEntry {
        let id: CGWindowID
        let title: String?
    }

    func snapshot() -> RuntimeSnapshot {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && !$0.isTerminated
                && $0.processIdentifier != currentPID
        }

        guard !runningApps.isEmpty else {
            return RuntimeSnapshot(apps: [], contextsByID: [:])
        }

        RuntimeLog.info("Snapshot", "runningApps=\(runningApps.count)")
        let windowData = collectWindowData(for: runningApps)
        let selectedApps = selectPrimaryApps(
            from: runningApps,
            windowsByPID: windowData.windowsByPID,
            rankByPID: windowData.rankByPID
        )
        let hideMinimizedAppsFromAppLayer =
            SwitcherBehaviorPreferencesStore.loadHideMinimizedAppsFromAppLayer()
        let appLayerCandidates = filterAppsForAppLayer(
            selectedApps,
            windowsByPID: windowData.windowsByPID,
            hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
        )
        RuntimeLog.info(
            "Snapshot",
            "selectedApps=\(selectedApps.count) appLayerCandidates=\(appLayerCandidates.count) hideMinimized=\(hideMinimizedAppsFromAppLayer)"
        )

        guard !appLayerCandidates.isEmpty else {
            return RuntimeSnapshot(apps: [], contextsByID: [:])
        }
        let now = Date.timeIntervalSinceReferenceDate

        var rows: [(candidate: AppSwitchCandidate, context: RuntimeAppContext)] = []
        rows.reserveCapacity(appLayerCandidates.count)

        for (index, app) in appLayerCandidates.enumerated() {
            let pid = app.processIdentifier
            let baseAppID = Self.baseAppID(for: app)
            let appID = baseAppID
            let displayName = app.localizedName ?? baseAppID

            let windows = windowData.windowsByPID[pid] ?? []
            RuntimeLog.info(
                "Snapshot",
                "\(displayName) pid=\(pid) appID=\(appID) windows=\(windows.count)"
            )
            let windowCandidates = windows.enumerated().map { entryIndex, entry in
                WindowCandidate(
                    id: entry.windowID,
                    title: entry.title,
                    isMinimized: entry.isMinimized,
                    lastActiveAt: now - Double(entryIndex)
                )
            }

            let rank = windowData.rankByPID[pid] ?? (10_000 + index)
            let candidate = AppSwitchCandidate(
                id: appID,
                displayName: displayName,
                groupID: Self.groupID(for: app.bundleIdentifier, fallbackName: displayName),
                lastActiveAt: now - Double(rank),
                windows: windowCandidates
            )

            let windowContexts = Dictionary(
                uniqueKeysWithValues: windows.map {
                    let id = $0.windowID
                    return (
                        id,
                        RuntimeWindowContext(
                            id: id,
                            title: $0.title,
                            isMinimized: $0.isMinimized,
                            cgWindowID: $0.cgWindowID,
                            previewImage: nil,
                            inferredTitleBarStyle: nil
                        )
                    )
                }
            )
            let context = RuntimeAppContext(
                appID: appID,
                runningApp: app,
                windowsByID: windowContexts
            )
            rows.append((candidate, context))
        }

        rows.sort { lhs, rhs in
            if lhs.candidate.lastActiveAt == rhs.candidate.lastActiveAt {
                return lhs.candidate.displayName.localizedCaseInsensitiveCompare(
                    rhs.candidate.displayName
                ) == .orderedAscending
            }
            return lhs.candidate.lastActiveAt > rhs.candidate.lastActiveAt
        }

        var contextsByID: [String: RuntimeAppContext] = [:]
        for row in rows {
            if contextsByID[row.context.appID] != nil {
                RuntimeLog.info("Snapshot", "duplicate appID fallback overwrite=\(row.context.appID)")
            }
            contextsByID[row.context.appID] = row.context
        }

        return RuntimeSnapshot(
            apps: rows.map(\.candidate),
            contextsByID: contextsByID
        )
    }

    private func filterAppsForAppLayer(
        _ apps: [NSRunningApplication],
        windowsByPID: [pid_t: [WindowListEntry]],
        hideMinimizedAppsFromAppLayer: Bool
    ) -> [NSRunningApplication] {
        guard hideMinimizedAppsFromAppLayer else { return apps }

        return apps.filter { app in
            let windows = windowsByPID[app.processIdentifier] ?? []
            guard !windows.isEmpty else { return true }
            let hasVisibleWindow = windows.contains(where: { !$0.isMinimized })
            if !hasVisibleWindow {
                let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
                RuntimeLog.info("Snapshot", "skip minimized-only app=\(appName) pid=\(app.processIdentifier)")
            }
            return hasVisibleWindow
        }
    }

    private func collectWindowData(for runningApps: [NSRunningApplication]) -> (
        windowsByPID: [pid_t: [WindowListEntry]],
        rankByPID: [pid_t: Int]
    ) {
        let cgWindowsByPID = collectCGWindowsByPID()
        // Keep a single source of truth for window counting and selection: AX window list.
        return (
            windowsByPID: collectAXWindowData(for: runningApps, cgWindowsByPID: cgWindowsByPID),
            rankByPID: collectAppRankByPID()
        )
    }

    private func collectAXWindowData(
        for runningApps: [NSRunningApplication],
        cgWindowsByPID: [pid_t: [CGWindowEntry]]
    ) -> [pid_t: [WindowListEntry]] {
        guard AXIsProcessTrusted() else {
            RuntimeLog.info("AX", "not trusted; all app windows will be reported as 0")
            return [:]
        }

        var windowsByPID: [pid_t: [WindowListEntry]] = [:]
        for app in runningApps {
            let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
            let windows = AXWindowInspector.windows(for: app)
            let cgWindows = cgWindowsByPID[app.processIdentifier] ?? []
            var matchedCGWindowIndexes: Set<Int> = []
            RuntimeLog.info("AX", "\(appName) rawWindows=\(windows.count)")
            guard !windows.isEmpty else { continue }

            let entries = windows.enumerated().compactMap { index, window -> WindowListEntry? in
                guard AXWindowInspector.isSwitchable(window) else {
                    let role = AXWindowInspector.role(for: window) ?? "unknown"
                    RuntimeLog.info("AX", "\(appName) skip[\(index)] role=\(role)")
                    return nil
                }
                let windowID = AXWindowInspector.makeWindowID(
                    pid: app.processIdentifier,
                    index: index
                )
                let titleFromAX = AXWindowInspector.title(for: window)
                let title = titleFromAX ?? {
                    RuntimeLog.info("AX", "\(appName) untitled[\(index)] use fallback")
                    return AXWindowInspector.fallbackTitle(index: index)
                }()
                let cgWindowID = resolveCGWindowID(
                    preferredTitle: titleFromAX,
                    fallbackIndex: index,
                    cgWindows: cgWindows,
                    usedIndexes: &matchedCGWindowIndexes
                )
                return WindowListEntry(
                    windowID: windowID,
                    title: title,
                    isMinimized: AXWindowInspector.isMinimized(window),
                    cgWindowID: cgWindowID
                )
            }

            guard !entries.isEmpty else { continue }
            RuntimeLog.info("AX", "\(appName) switchableWindows=\(entries.count)")
            windowsByPID[app.processIdentifier] = entries
        }
        return windowsByPID
    }

    private func collectCGWindowsByPID() -> [pid_t: [CGWindowEntry]] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard
            let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else {
            return [:]
        }

        var windowsByPID: [pid_t: [CGWindowEntry]] = [:]
        for item in rawList {
            guard let ownerPID = item[kCGWindowOwnerPID as String] as? pid_t else { continue }
            guard let layer = item[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let windowNumber = item[kCGWindowNumber as String] as? NSNumber else { continue }
            let title = (item[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            windowsByPID[ownerPID, default: []].append(
                CGWindowEntry(
                    id: CGWindowID(windowNumber.uint32Value),
                    title: title
                )
            )
        }
        return windowsByPID
    }

    private func resolveCGWindowID(
        preferredTitle: String?,
        fallbackIndex: Int,
        cgWindows: [CGWindowEntry],
        usedIndexes: inout Set<Int>
    ) -> CGWindowID? {
        if let preferredTitle, !preferredTitle.isEmpty {
            if let exactMatchIndex = cgWindows.indices.first(where: { index in
                !usedIndexes.contains(index) && cgWindows[index].title == preferredTitle
            }) {
                usedIndexes.insert(exactMatchIndex)
                return cgWindows[exactMatchIndex].id
            }
            if let insensitiveMatchIndex = cgWindows.indices.first(where: { index in
                guard !usedIndexes.contains(index), let title = cgWindows[index].title else { return false }
                return title.caseInsensitiveCompare(preferredTitle) == .orderedSame
            }) {
                usedIndexes.insert(insensitiveMatchIndex)
                return cgWindows[insensitiveMatchIndex].id
            }
        }

        if cgWindows.indices.contains(fallbackIndex), !usedIndexes.contains(fallbackIndex) {
            usedIndexes.insert(fallbackIndex)
            return cgWindows[fallbackIndex].id
        }

        guard let firstUnmatchedIndex = cgWindows.indices.first(where: { !usedIndexes.contains($0) }) else {
            return nil
        }
        usedIndexes.insert(firstUnmatchedIndex)
        return cgWindows[firstUnmatchedIndex].id
    }

    private func collectAppRankByPID() -> [pid_t: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard
            let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else {
            return [:]
        }

        var rankByPID: [pid_t: Int] = [:]
        for (rank, item) in rawList.enumerated() {
            guard let ownerPID = item[kCGWindowOwnerPID as String] as? pid_t else { continue }
            guard let layer = item[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            if rankByPID[ownerPID] == nil {
                rankByPID[ownerPID] = rank
            }
        }
        return rankByPID
    }

    private static func groupID(for bundleIdentifier: String?, fallbackName: String) -> String {
        guard let bundleIdentifier else {
            return String(fallbackName.prefix(1)).lowercased()
        }

        let components = bundleIdentifier.split(separator: ".")
        if components.count >= 2 {
            return String(components[1])
        }
        if let first = components.first {
            return String(first)
        }
        return "apps"
    }

    private func selectPrimaryApps(
        from runningApps: [NSRunningApplication],
        windowsByPID: [pid_t: [WindowListEntry]],
        rankByPID: [pid_t: Int]
    ) -> [NSRunningApplication] {
        let grouped = Dictionary(grouping: runningApps, by: Self.baseAppID(for:))
        var selected: [NSRunningApplication] = []
        selected.reserveCapacity(grouped.count)

        for (baseAppID, apps) in grouped {
            guard apps.count > 1 else {
                if let app = apps.first {
                    selected.append(app)
                }
                continue
            }

            let sorted = apps.sorted { lhs, rhs in
                score(
                    for: lhs,
                    windowsByPID: windowsByPID,
                    rankByPID: rankByPID
                ) > score(
                    for: rhs,
                    windowsByPID: windowsByPID,
                    rankByPID: rankByPID
                )
            }

            guard let primary = sorted.first else { continue }
            selected.append(primary)

            let droppedPIDs = sorted.dropFirst().map(\.processIdentifier)
            RuntimeLog.info(
                "Snapshot",
                "dedupe baseAppID=\(baseAppID) keepPID=\(primary.processIdentifier) dropPIDs=\(droppedPIDs)"
            )
        }

        return selected
    }

    private func score(
        for app: NSRunningApplication,
        windowsByPID: [pid_t: [WindowListEntry]],
        rankByPID: [pid_t: Int]
    ) -> Int {
        let pid = app.processIdentifier
        let windowCount = windowsByPID[pid]?.count ?? 0
        let hasWindowsScore = windowCount > 0 ? 1_000_000 : 0
        let windowCountScore = min(windowCount, 9_999) * 100
        let rankScore = 10_000 - min(rankByPID[pid] ?? 10_000, 10_000)
        let launchScore = Int(app.launchDate?.timeIntervalSince1970 ?? 0) % 10_000
        return hasWindowsScore + windowCountScore + rankScore + launchScore
    }

    private static func baseAppID(for app: NSRunningApplication) -> String {
        let pid = app.processIdentifier
        return app.bundleIdentifier ?? "pid:\(pid)"
    }
}

@MainActor
final class RuntimeActivator {
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
        context.runningApp.activate(options: [.activateAllWindows])
    }

    private func activateWindow(
        appID: String,
        windowID: String,
        restoreIfMinimized: Bool,
        contextsByID: [String: RuntimeAppContext]
    ) {
        guard let context = contextsByID[appID] else { return }
        context.runningApp.activate(options: [.activateAllWindows])
        guard let windowContext = context.windowsByID[windowID] else { return }
        focusWindow(
            withID: windowID,
            withTitle: windowContext.title,
            restoreIfMinimized: restoreIfMinimized || windowContext.isMinimized,
            in: context.runningApp
        )
    }

    private func focusWindow(
        withID targetWindowID: String,
        withTitle targetTitle: String,
        restoreIfMinimized: Bool,
        in app: NSRunningApplication
    ) {
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

    private func focus(window: AXUIElement, restoreIfMinimized: Bool) {
        if restoreIfMinimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

}

private enum AXWindowInspector {
    private static let windowIDPrefix = "ax"

    static func windows(for app: NSRunningApplication) -> [AXUIElement] {
        guard AXIsProcessTrusted() else { return [] }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
                == .success,
            let windows = windowsValue as? [AXUIElement]
        else {
            return []
        }
        return windows
    }

    static func makeWindowID(pid: pid_t, index: Int) -> String {
        "\(windowIDPrefix):\(pid):\(index)"
    }

    static func windowIndex(from windowID: String, expectedPID: pid_t) -> Int? {
        let parts = windowID.split(separator: ":")
        guard parts.count == 3 else { return nil }
        guard parts[0] == Substring(windowIDPrefix) else { return nil }
        guard let pid = pid_t(parts[1]), pid == expectedPID else { return nil }
        return Int(parts[2])
    }

    static func fallbackTitle(index: Int) -> String {
        "Window #\(index + 1)"
    }

    static func title(for window: AXUIElement) -> String? {
        var titleValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
                == .success,
            let title = (titleValue as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty
        else {
            return nil
        }
        return title
    }

    static func isSwitchable(_ window: AXUIElement) -> Bool {
        guard let role = role(for: window) else { return true }
        return role == kAXWindowRole as String
    }

    static func role(for window: AXUIElement) -> String? {
        var roleValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleValue)
                == .success,
            let role = roleValue as? String
        else {
            return nil
        }
        return role
    }

    static func isMinimized(_ window: AXUIElement) -> Bool {
        var minimizedValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
                == .success,
            let number = minimizedValue as? NSNumber
        else {
            return false
        }
        return number.boolValue
    }
}

enum RuntimeWindowPreviewProvider {
    private struct LiveCGWindowEntry {
        let id: CGWindowID
        let title: String?
    }

    private struct StripStats {
        let meanLuminance: Double
        let stdLuminance: Double
        let meanSaturation: Double
        let sampleCount: Int

        var uniformityScore: Double {
            stdLuminance + meanSaturation * 0.6
        }
    }

    private static var hasLoggedScreenCapturePermissionWarning = false
    private static let shareableContentLookupTimeout: TimeInterval = 1.0
    private static let screenshotCaptureTimeout: TimeInterval = 1.0

    static func captureWindowPreview(
        preferredWindowID: CGWindowID?,
        ownerPID: pid_t,
        preferredTitle: String?,
        inferTitleBarStyle: Bool
    ) -> (image: NSImage, resolvedWindowID: CGWindowID, titleBarStyle: WindowTitleBarStyleGuess?)? {
        guard ScreenCapturePermissionChecker.hasScreenCapturePermission else {
            if !hasLoggedScreenCapturePermissionWarning {
                RuntimeLog.info("Preview", "screen recording permission missing; window preview unavailable")
                hasLoggedScreenCapturePermissionWarning = true
            }
            return nil
        }

        let candidateIDs = candidateWindowIDs(
            preferredWindowID: preferredWindowID,
            ownerPID: ownerPID,
            preferredTitle: preferredTitle
        )
        guard !candidateIDs.isEmpty else {
            RuntimeLog.info(
                "Preview",
                "no candidate windows pid=\(ownerPID) preferredID=\(preferredWindowID.map(String.init) ?? "nil") title=\(preferredTitle ?? "<empty>")"
            )
            return nil
        }

        let shareableWindowsByID = fetchShareableWindowsByID()
        for candidateID in candidateIDs {
            guard let shareableWindow = shareableWindowsByID[candidateID] else { continue }
            guard let cgImage = captureWindow(shareableWindow: shareableWindow) else { continue }
            let titleBarStyle = inferTitleBarStyle ? estimateTitleBarStyle(from: cgImage) : nil
            let image = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
            RuntimeLog.info(
                "Preview",
                "capture success pid=\(ownerPID) windowID=\(candidateID) candidates=\(candidateIDs.count) titleBarStyle=\(titleBarStyle?.rawValue ?? "nil")"
            )
            return (image: image, resolvedWindowID: candidateID, titleBarStyle: titleBarStyle)
        }

        RuntimeLog.info(
            "Preview",
            "capture failed pid=\(ownerPID) preferredID=\(preferredWindowID.map(String.init) ?? "nil") title=\(preferredTitle ?? "<empty>") candidates=\(candidateIDs.map(String.init).joined(separator: ","))"
        )
        return nil
    }

    private static func candidateWindowIDs(
        preferredWindowID: CGWindowID?,
        ownerPID: pid_t,
        preferredTitle: String?
    ) -> [CGWindowID] {
        let liveWindows = collectLiveCGWindows(ownerPID: ownerPID)
        var candidateIDs: [CGWindowID] = []
        var seen: Set<CGWindowID> = []

        func appendCandidate(_ id: CGWindowID) {
            guard !seen.contains(id) else { return }
            seen.insert(id)
            candidateIDs.append(id)
        }

        if let preferredWindowID {
            appendCandidate(preferredWindowID)
        }

        let trimmedTitle = preferredTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedTitle, !trimmedTitle.isEmpty {
            for window in liveWindows {
                guard let title = window.title else { continue }
                if title == trimmedTitle {
                    appendCandidate(window.id)
                }
            }
            for window in liveWindows {
                guard let title = window.title else { continue }
                if title.caseInsensitiveCompare(trimmedTitle) == .orderedSame {
                    appendCandidate(window.id)
                }
            }
        }

        for window in liveWindows {
            appendCandidate(window.id)
        }
        return candidateIDs
    }

    private static func collectLiveCGWindows(ownerPID: pid_t) -> [LiveCGWindowEntry] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard
            let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }

        var windows: [LiveCGWindowEntry] = []
        windows.reserveCapacity(rawList.count)
        for item in rawList {
            guard let pid = item[kCGWindowOwnerPID as String] as? pid_t, pid == ownerPID else { continue }
            guard let layer = item[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let windowNumber = item[kCGWindowNumber as String] as? NSNumber else { continue }
            let title = (item[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            windows.append(
                LiveCGWindowEntry(
                    id: CGWindowID(windowNumber.uint32Value),
                    title: title
                )
            )
        }
        return windows
    }

    private static func fetchShareableWindowsByID() -> [CGWindowID: SCWindow] {
        var shareableContent: SCShareableContent?
        var capturedError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
            shareableContent = content
            capturedError = error
            semaphore.signal()
        }

        let timeoutDate = DispatchTime.now() + shareableContentLookupTimeout
        guard semaphore.wait(timeout: timeoutDate) == .success else {
            RuntimeLog.info("Preview", "shareable-content lookup timed out")
            return [:]
        }
        if let capturedError {
            RuntimeLog.info("Preview", "shareable-content lookup failed error=\(capturedError.localizedDescription)")
            return [:]
        }
        guard let shareableContent else { return [:] }

        var windowsByID: [CGWindowID: SCWindow] = [:]
        windowsByID.reserveCapacity(shareableContent.windows.count)
        for window in shareableContent.windows {
            windowsByID[window.windowID] = window
        }
        return windowsByID
    }

    private static func captureWindow(shareableWindow: SCWindow) -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: shareableWindow)
        let configuration = SCStreamConfiguration()
        let width = max(1, Int(ceil(shareableWindow.frame.width)))
        let height = max(1, Int(ceil(shareableWindow.frame.height)))
        configuration.width = width
        configuration.height = height
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        var capturedImage: CGImage?
        var capturedError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
            capturedImage = image
            capturedError = error
            semaphore.signal()
        }

        let timeoutDate = DispatchTime.now() + screenshotCaptureTimeout
        guard semaphore.wait(timeout: timeoutDate) == .success else {
            RuntimeLog.info("Preview", "screenshot capture timed out windowID=\(shareableWindow.windowID)")
            return nil
        }
        if let capturedError {
            RuntimeLog.info(
                "Preview",
                "screenshot capture failed windowID=\(shareableWindow.windowID) error=\(capturedError.localizedDescription)"
            )
        }
        return capturedImage
    }

    private static func estimateTitleBarStyle(from image: CGImage) -> WindowTitleBarStyleGuess? {
        let sourceWidth = image.width
        let sourceHeight = image.height
        guard sourceWidth >= 24, sourceHeight >= 24 else { return nil }

        let targetWidth = min(sourceWidth, 720)
        let scale = Double(targetWidth) / Double(sourceWidth)
        let targetHeight = max(
            1,
            Int((Double(sourceHeight) * scale).rounded(.toNearestOrAwayFromZero))
        )
        let bytesPerPixel = 4
        let bytesPerRow = targetWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: targetHeight * bytesPerRow)

        let didRender = pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return false }
            guard
                let context = CGContext(
                    data: baseAddress,
                    width: targetWidth,
                    height: targetHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else {
                return false
            }
            context.interpolationQuality = .low
            context.draw(
                image,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: targetWidth,
                    height: targetHeight
                )
            )
            return true
        }
        guard didRender else { return nil }

        let bandHeight = max(8, min(48, Int(Double(targetHeight) * 0.11)))
        let horizontalInset = min(
            max(4, Int(Double(targetWidth) * 0.10)),
            max(0, targetWidth / 2 - 1)
        )
        let xStart = horizontalInset
        let xEnd = targetWidth - horizontalInset
        guard xEnd > xStart else { return nil }

        let topStrip = analyzeStrip(
            pixels: pixels,
            bytesPerRow: bytesPerRow,
            yRange: (targetHeight - bandHeight)..<targetHeight,
            xRange: xStart..<xEnd
        )
        let bottomStrip = analyzeStrip(
            pixels: pixels,
            bytesPerRow: bytesPerRow,
            yRange: 0..<bandHeight,
            xRange: xStart..<xEnd
        )
        guard
            let strip = preferredStrip(top: topStrip, bottom: bottomStrip),
            strip.sampleCount >= 160
        else {
            return nil
        }
        guard strip.uniformityScore <= 0.30 else { return nil }

        if strip.meanLuminance <= 0.47 {
            return .dark
        }
        if strip.meanLuminance >= 0.60 {
            return .light
        }
        if strip.stdLuminance <= 0.10, strip.meanSaturation <= 0.17 {
            return strip.meanLuminance < 0.53 ? .dark : .light
        }
        return nil
    }

    private static func preferredStrip(
        top: StripStats?,
        bottom: StripStats?
    ) -> StripStats? {
        switch (top, bottom) {
        case (nil, nil):
            return nil
        case let (top?, nil):
            return top
        case let (nil, bottom?):
            return bottom
        case let (top?, bottom?):
            return top.uniformityScore <= bottom.uniformityScore ? top : bottom
        }
    }

    private static func analyzeStrip(
        pixels: [UInt8],
        bytesPerRow: Int,
        yRange: Range<Int>,
        xRange: Range<Int>
    ) -> StripStats? {
        var luminanceSum = 0.0
        var luminanceSquareSum = 0.0
        var saturationSum = 0.0
        var sampleCount = 0

        for y in yRange {
            let rowOffset = y * bytesPerRow
            for x in xRange {
                let base = rowOffset + x * 4
                let alpha = Double(pixels[base + 3]) / 255.0
                guard alpha >= 0.90 else { continue }

                let normalizer = max(alpha, 0.0001)
                let red = min(1.0, Double(pixels[base]) / 255.0 / normalizer)
                let green = min(1.0, Double(pixels[base + 1]) / 255.0 / normalizer)
                let blue = min(1.0, Double(pixels[base + 2]) / 255.0 / normalizer)
                let maxChannel = max(red, max(green, blue))
                let minChannel = min(red, min(green, blue))
                let saturation = maxChannel > 0 ? (maxChannel - minChannel) / maxChannel : 0
                let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue

                luminanceSum += luminance
                luminanceSquareSum += luminance * luminance
                saturationSum += saturation
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return nil }
        let meanLuminance = luminanceSum / Double(sampleCount)
        let variance = max(
            0,
            luminanceSquareSum / Double(sampleCount) - meanLuminance * meanLuminance
        )
        return StripStats(
            meanLuminance: meanLuminance,
            stdLuminance: sqrt(variance),
            meanSaturation: saturationSum / Double(sampleCount),
            sampleCount: sampleCount
        )
    }
}

enum ScreenCapturePermissionChecker {
    static var hasScreenCapturePermission: Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    @discardableResult
    static func requestScreenCapturePermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CGRequestScreenCaptureAccess()
        }
        return true
    }
}

final class AppIconProvider {
    private var cache: [String: NSImage] = [:]

    func icon(for app: AppSwitchCandidate, context: RuntimeAppContext?) -> NSImage? {
        if let cached = cache[app.id] {
            return cached
        }

        if let runtimeIcon = context?.runningApp.icon {
            cache[app.id] = runtimeIcon
            return runtimeIcon
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id) else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[app.id] = icon
        return icon
    }
}
