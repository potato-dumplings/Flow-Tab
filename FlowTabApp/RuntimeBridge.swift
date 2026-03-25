import AppKit
import ApplicationServices
import Foundation
import FlowTabCore

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

        let appIDDuplicateCounts = Dictionary(
            runningApps.map { (Self.baseAppID(for: $0), 1) },
            uniquingKeysWith: +
        )

        RuntimeLog.info("Snapshot", "runningApps=\(runningApps.count)")
        let windowData = collectWindowData(for: runningApps)
        let now = Date.timeIntervalSinceReferenceDate

        var rows: [(candidate: AppSwitchCandidate, context: RuntimeAppContext)] = []
        rows.reserveCapacity(runningApps.count)

        for (index, app) in runningApps.enumerated() {
            let pid = app.processIdentifier
            let baseAppID = Self.baseAppID(for: app)
            let duplicateCount = appIDDuplicateCounts[baseAppID, default: 1]
            let appID = Self.resolvedAppID(
                baseAppID: baseAppID,
                pid: pid,
                duplicateCount: duplicateCount
            )
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
                            previewImage: nil
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

    private static func baseAppID(for app: NSRunningApplication) -> String {
        let pid = app.processIdentifier
        return app.bundleIdentifier ?? "pid:\(pid)"
    }

    private static func resolvedAppID(
        baseAppID: String,
        pid: pid_t,
        duplicateCount: Int
    ) -> String {
        guard duplicateCount > 1 else { return baseAppID }
        return "\(baseAppID)#\(pid)"
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

    private static var hasLoggedScreenCapturePermissionWarning = false

    static func captureWindowPreview(
        preferredWindowID: CGWindowID?,
        ownerPID: pid_t,
        preferredTitle: String?
    ) -> (image: NSImage, resolvedWindowID: CGWindowID)? {
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

        for candidateID in candidateIDs {
            guard let image = captureWindow(windowID: candidateID) else { continue }
            RuntimeLog.info(
                "Preview",
                "capture success pid=\(ownerPID) windowID=\(candidateID) candidates=\(candidateIDs.count)"
            )
            return (image: image, resolvedWindowID: candidateID)
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

    private static func captureWindow(windowID: CGWindowID) -> NSImage? {
        guard
            let cgImage = CGWindowListCreateImage(
                .null,
                [.optionIncludingWindow, .excludeDesktopElements],
                windowID,
                [.boundsIgnoreFraming, .bestResolution]
            )
        else {
            return nil
        }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
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
