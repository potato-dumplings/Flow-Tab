import AppKit
import Foundation

struct RuntimeAppWindowStats {
    let windowCount: Int
    let hasVisibleWindow: Bool
}

struct RuntimeAppDirectory {
    private let apps: [NSRunningApplication]
    private let candidateAppBundlePaths: Set<String>

    init(apps: [NSRunningApplication]) {
        self.apps = apps
        candidateAppBundlePaths = Set(apps.compactMap { Self.standardizedAppBundlePath(for: $0.bundleURL) })
    }

    func filterAppLayerCandidates(
        windowStatsByPID: [pid_t: RuntimeAppWindowStats],
        hideMinimizedAppsFromAppLayer: Bool
    ) -> [NSRunningApplication] {
        apps.filter { app in
            let stats = windowStatsByPID[app.processIdentifier]
                ?? RuntimeAppWindowStats(windowCount: 0, hasVisibleWindow: false)
            guard !Self.shouldHideZeroWindowNestedApp(
                hasWindows: stats.windowCount > 0,
                bundleURL: app.bundleURL,
                candidateAppBundlePaths: candidateAppBundlePaths
            ) else {
                logSkippedApp(app, reason: "nested zero-window")
                return false
            }
            guard RuntimeAppLayerProjectionFilter.shouldIncludeAppInAppLayer(
                hasWindows: stats.windowCount > 0,
                hasVisibleWindow: stats.hasVisibleWindow,
                hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
            ) else {
                logSkippedApp(app, reason: "minimized-only")
                return false
            }
            return true
        }
    }

    static func shouldHideZeroWindowNestedApp(
        hasWindows: Bool,
        bundleURL: URL?,
        candidateAppBundlePaths: Set<String>
    ) -> Bool {
        guard !hasWindows else { return false }
        guard
            let bundlePath = standardizedAppBundlePath(for: bundleURL),
            candidateAppBundlePaths.count > 1
        else {
            return false
        }

        return appBundleAncestorPaths(for: bundlePath).contains { candidateAppBundlePaths.contains($0) }
    }

    static func standardizedAppBundlePath(for bundleURL: URL?) -> String? {
        guard let bundleURL else { return nil }
        let standardizedURL = bundleURL.standardizedFileURL
        guard standardizedURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            return nil
        }
        return standardizedURL.path
    }

    private static func appBundleAncestorPaths(for bundlePath: String) -> [String] {
        var ancestorPaths: [String] = []
        var currentURL = URL(fileURLWithPath: bundlePath).deletingLastPathComponent()

        while currentURL.path != "/" {
            let standardizedURL = currentURL.standardizedFileURL
            if standardizedURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                ancestorPaths.append(standardizedURL.path)
            }

            let parentURL = currentURL.deletingLastPathComponent()
            guard parentURL.path != currentURL.path else { break }
            currentURL = parentURL
        }

        return ancestorPaths
    }

    private func logSkippedApp(_ app: NSRunningApplication, reason: String) {
        let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        RuntimeLog.debug(.projection, "skip \(reason) app=\(appName) pid=\(app.processIdentifier)")
    }
}
