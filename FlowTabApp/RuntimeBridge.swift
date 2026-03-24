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
}

@MainActor
final class RuntimeSnapshotProvider {
    private struct WindowListEntry {
        let windowID: CGWindowID
        let title: String
        let isMinimized: Bool
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

        let windowData = collectWindowData()
        let now = Date.timeIntervalSinceReferenceDate

        var rows: [(candidate: AppSwitchCandidate, context: RuntimeAppContext)] = []
        rows.reserveCapacity(runningApps.count)

        for (index, app) in runningApps.enumerated() {
            let pid = app.processIdentifier
            let appID = app.bundleIdentifier ?? "pid:\(pid)"
            let displayName = app.localizedName ?? appID

            let windows = windowData.windowsByPID[pid] ?? []
            let windowCandidates = windows.enumerated().map { entryIndex, entry in
                WindowCandidate(
                    id: String(entry.windowID),
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
                    let id = String($0.windowID)
                    return (
                        id,
                        RuntimeWindowContext(
                            id: id,
                            title: $0.title,
                            isMinimized: $0.isMinimized
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

        return RuntimeSnapshot(
            apps: rows.map(\.candidate),
            contextsByID: Dictionary(uniqueKeysWithValues: rows.map { ($0.context.appID, $0.context) })
        )
    }

    private func collectWindowData() -> (
        windowsByPID: [pid_t: [WindowListEntry]],
        rankByPID: [pid_t: Int]
    ) {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard
            let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else {
            return ([:], [:])
        }

        var windowsByPID: [pid_t: [WindowListEntry]] = [:]
        var rankByPID: [pid_t: Int] = [:]

        for (rank, item) in rawList.enumerated() {
            guard let ownerPID = item[kCGWindowOwnerPID as String] as? pid_t else { continue }
            guard let layer = item[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let windowNumber = item[kCGWindowNumber as String] as? UInt32 else { continue }

            let title = Self.windowTitle(from: item)
            guard !title.isEmpty else { continue }
            let isOnScreen = (item[kCGWindowIsOnscreen as String] as? Int) == 1

            if rankByPID[ownerPID] == nil {
                rankByPID[ownerPID] = rank
            }

            windowsByPID[ownerPID, default: []].append(
                WindowListEntry(windowID: windowNumber, title: title, isMinimized: !isOnScreen)
            )
        }

        return (windowsByPID, rankByPID)
    }

    private static func windowTitle(from windowInfo: [String: Any]) -> String {
        let rawTitle = (windowInfo[kCGWindowName as String] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let rawTitle, !rawTitle.isEmpty {
            return rawTitle
        }

        let ownerName = (windowInfo[kCGWindowOwnerName as String] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ownerName ?? ""
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
            withTitle: windowContext.title,
            restoreIfMinimized: restoreIfMinimized || windowContext.isMinimized,
            in: context.runningApp
        )
    }

    private func focusWindow(
        withTitle targetTitle: String,
        restoreIfMinimized: Bool,
        in app: NSRunningApplication
    ) {
        guard AXIsProcessTrusted() else { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
                == .success,
            let windows = windowsValue as? [AXUIElement]
        else {
            return
        }

        for window in windows {
            guard let title = windowTitle(for: window), title == targetTitle else { continue }
            if restoreIfMinimized {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            return
        }
    }

    private func windowTitle(for window: AXUIElement) -> String? {
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
