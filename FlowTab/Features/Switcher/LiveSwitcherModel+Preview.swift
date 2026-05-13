import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

extension LiveSwitcherModel {
    private static let eagerWindowPreviewCaptureLimit = 24
    private static let eagerWindowPreviewCaptureRadius = 6

    func handleSessionPreviewSnapshotLifecycle(_ session: SwitcherSession) {
        guard case .windowCycle(let appID) = session.mode else { return }
        freezeWindowPreviewSnapshotIfNeeded(for: appID, session: session)
    }

    func clearPreviewSnapshotState() {
        previewImageCache.removeAll()
        previewCaptureAttemptedKeys = []
        previewSnapshotFrozenAppIDs = []
    }

    func freezeWindowPreviewSnapshotIfNeeded(
        for appID: String,
        session: SwitcherSession? = nil
    ) {
        let resolvedSession = session ?? self.session
        guard let app = resolvedSession?.apps.first(where: { $0.id == appID }) else { return }
        let selectedIndex = resolvedSession?.selectedWindowIndexByAppID[appID] ?? 0
        let windowsToCapture = app.windows.count > Self.eagerWindowPreviewCaptureLimit
            ? []
            : eagerPreviewWindows(for: app, selectedIndex: selectedIndex)
        if windowsToCapture.count == app.windows.count, previewSnapshotFrozenAppIDs.contains(appID) {
            return
        }

        for window in windowsToCapture {
            _ = previewData(for: appID, window: window)
        }
        if windowsToCapture.count == app.windows.count {
            previewSnapshotFrozenAppIDs.insert(appID)
        }
    }

    func windowPreviewPageSummary() -> WindowPreviewPageSummary {
        guard let session else {
            return WindowPreviewPageSummary(itemCount: 0, selectedIndex: nil)
        }
        guard case .windowCycle(let appID) = session.mode else {
            return WindowPreviewPageSummary(itemCount: 0, selectedIndex: nil)
        }
        guard let app = session.apps.first(where: { $0.id == appID }) else {
            return WindowPreviewPageSummary(itemCount: 0, selectedIndex: nil)
        }
        let selectedIndex = session.selectedWindowIndexByAppID[appID]
            .map { min(max(0, $0), max(app.windows.count - 1, 0)) }
        return WindowPreviewPageSummary(
            itemCount: app.windows.count,
            selectedIndex: selectedIndex
        )
    }

    func shouldBumpSearchResultScrollRevision(
        from oldState: SwitcherSearchViewState,
        to newState: SwitcherSearchViewState
    ) -> Bool {
        guard newState.isActive else { return false }
        return oldState.isInputFocused != newState.isInputFocused
            || oldState.selectedResultIndex != newState.selectedResultIndex
            || oldState.results.map(\.id) != newState.results.map(\.id)
    }

    func previewData(
        for appID: String,
        window: WindowCandidate
    ) -> (image: NSImage?, titleBarStyle: WindowTitleBarStyleGuess?) {
        guard var appContext = runtimeContextsByID[appID] else {
            return (image: nil, titleBarStyle: nil)
        }
        guard var windowContext = appContext.windowsByID[window.id] else {
            return (image: nil, titleBarStyle: nil)
        }
        let previewCacheKey = "\(appID)#\(window.id)"
        if let cached = previewImageCache.image(forKey: previewCacheKey) {
            return (
                image: cached,
                titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
            )
        }

        if previewCaptureAttemptedKeys.contains(previewCacheKey) {
            return (
                image: nil,
                titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
            )
        }
        previewCaptureAttemptedKeys.insert(previewCacheKey)
        let ownerPID = windowContext.ownerPID == 0
            ? appContext.runningApp.processIdentifier
            : windowContext.ownerPID

        RuntimeLog.info(
            "Preview",
            "attempt appID=\(appID) pid=\(ownerPID) windowID=\(window.id) mappedCG=\(windowContext.cgWindowID.map(String.init) ?? "nil") title=\(windowContext.title)"
        )
        guard
            let capture = {
                if let previewCaptureOverride {
                    return previewCaptureOverride(
                        windowContext.cgWindowID,
                        ownerPID,
                        windowContext.title,
                        titleBarStyleInferenceEnabled
                    )
                }
                return RuntimeWindowPreviewProvider.captureWindowPreview(
                    preferredWindowID: windowContext.cgWindowID,
                    ownerPID: ownerPID,
                    preferredTitle: windowContext.title,
                    inferTitleBarStyle: titleBarStyleInferenceEnabled
                )
            }()
        else {
            RuntimeLog.info("Preview", "attempt failed appID=\(appID) windowID=\(window.id)")
            return (
                image: nil,
                titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
            )
        }

        windowContext.cgWindowID = capture.resolvedWindowID
        windowContext.inferredTitleBarStyle = capture.titleBarStyle
        previewImageCache.insert(capture.image, forKey: previewCacheKey)
        var windowsByID = appContext.windowsByID
        windowsByID[window.id] = windowContext
        appContext = RuntimeAppContext(
            appID: appContext.appID,
            runningApp: appContext.runningApp,
            windowsByID: windowsByID
        )
        runtimeContextsByID[appID] = appContext
        RuntimeLog.info(
            "Preview",
            "attempt success appID=\(appID) windowID=\(window.id) resolvedCG=\(capture.resolvedWindowID) titleBarStyle=\(capture.titleBarStyle?.rawValue ?? "nil")"
        )
        return (
            image: capture.image,
            titleBarStyle: titleBarStyleInferenceEnabled ? capture.titleBarStyle : nil
        )
    }

    func windowPreviewItems(visibleRange: Range<Int>? = nil) -> [WindowPreviewItem] {
        guard let session else { return [] }
        guard case .windowCycle(let appID) = session.mode else { return [] }
        guard let app = session.apps.first(where: { $0.id == appID }) else { return [] }

        let selectedIndex = session.selectedWindowIndexByAppID[appID] ?? 0
        let indexedWindows = indexedPreviewWindows(for: app, visibleRange: visibleRange)
        let eagerlyCapturedWindowIDs: Set<String>
        if visibleRange != nil {
            eagerlyCapturedWindowIDs = Set(indexedWindows.map { $0.window.id })
        } else {
            eagerlyCapturedWindowIDs = Set(
                eagerPreviewWindows(for: app, selectedIndex: selectedIndex).map(\.id)
            )
        }
        return indexedWindows.map { index, window in
            let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackTitle = overlayStyle == .windowOnly
                ? "Window \(index + 1)"
                : app.displayName
            let preview = eagerlyCapturedWindowIDs.contains(window.id)
                ? previewData(for: appID, window: window)
                : (image: nil, titleBarStyle: nil)
            return WindowPreviewItem(
                id: window.id,
                title: title.isEmpty ? fallbackTitle : title,
                image: preview.image,
                titleBarStyle: preview.titleBarStyle,
                isSelected: index == selectedIndex
            )
        }
    }

    private func indexedPreviewWindows(
        for app: AppSwitchCandidate,
        visibleRange: Range<Int>?
    ) -> [(index: Int, window: WindowCandidate)] {
        guard let visibleRange else {
            return app.windows.enumerated().map { (index: $0.offset, window: $0.element) }
        }
        let lowerBound = min(max(0, visibleRange.lowerBound), app.windows.count)
        let upperBound = min(max(lowerBound, visibleRange.upperBound), app.windows.count)
        guard lowerBound < upperBound else { return [] }
        return app.windows[lowerBound..<upperBound].enumerated().map {
            (index: lowerBound + $0.offset, window: $0.element)
        }
    }

    private func eagerPreviewWindows(
        for app: AppSwitchCandidate,
        selectedIndex: Int
    ) -> [WindowCandidate] {
        guard app.windows.count > Self.eagerWindowPreviewCaptureLimit else {
            return app.windows
        }

        let boundedSelectedIndex = min(max(0, selectedIndex), app.windows.count - 1)
        let lowerBound = max(0, boundedSelectedIndex - Self.eagerWindowPreviewCaptureRadius)
        let upperBound = min(
            app.windows.count - 1,
            boundedSelectedIndex + Self.eagerWindowPreviewCaptureRadius
        )
        return Array(app.windows[lowerBound...upperBound])
    }

    func windowPreviewSnapshotForTesting() -> [(
        id: String,
        title: String,
        hasImage: Bool,
        titleBarStyle: WindowTitleBarStyleGuess?,
        isSelected: Bool
    )] {
        windowPreviewItems().map {
            (
                id: $0.id,
                title: $0.title,
                hasImage: $0.image != nil,
                titleBarStyle: $0.titleBarStyle,
                isSelected: $0.isSelected
            )
        }
    }

    var selectedApp: AppSwitchCandidate? {
        session?.selectedApp
    }

    var canAutoEnterWindowLayer: Bool {
        guard let session else { return false }
        guard !searchViewState.isActive else { return false }
        if case .windowCycle = session.mode {
            return false
        }
        if autoEnterSuppressedAppID == session.selectedApp.id {
            return false
        }
        return session.selectedApp.windows.count >= 2
    }

    func icon(for app: AppSwitchCandidate) -> NSImage? {
        iconProvider.icon(for: app, context: runtimeContextsByID[app.id])
    }

    func searchAppItems() -> [SearchAppResultItem] {
        guard session != nil else { return [] }
        guard searchViewState.isActive, searchViewState.scope == .app else { return [] }

        let showsSelection = !searchViewState.isInputFocused
        return searchViewState.results.enumerated().compactMap { index, result in
            guard case .app(let appID) = result.kind else { return nil }
            guard let app = sessionAppsByID[appID] else { return nil }
            return SearchAppResultItem(
                id: result.id,
                app: app,
                isSelected: showsSelection && index == searchViewState.selectedResultIndex
            )
        }
    }

    func searchWindowItems() -> [SearchWindowResultItem] {
        guard session != nil else { return [] }
        guard searchViewState.isActive, searchViewState.scope == .window else { return [] }

        let showsSelection = !searchViewState.isInputFocused
        var iconByAppID: [String: NSImage] = [:]
        var missingIconAppIDs: Set<String> = []
        return searchViewState.results.enumerated().compactMap { index, result in
            guard case .window(let appID, _) = result.kind else { return nil }
            let app = sessionAppsByID[appID]
            let appName = app?.displayName ?? result.secondaryText ?? ""
            let resolvedIcon: NSImage?
            if let cached = iconByAppID[appID] {
                resolvedIcon = cached
            } else if missingIconAppIDs.contains(appID) {
                resolvedIcon = nil
            } else {
                let fetched = app.flatMap { icon(for: $0) }
                if let fetched {
                    iconByAppID[appID] = fetched
                } else {
                    missingIconAppIDs.insert(appID)
                }
                resolvedIcon = fetched
            }
            return SearchWindowResultItem(
                id: result.id,
                title: result.primaryText,
                appName: appName,
                icon: resolvedIcon,
                isSelected: showsSelection && index == searchViewState.selectedResultIndex
            )
        }
    }
}
