import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

extension LiveSwitcherModel {
    func handleSessionPreviewSnapshotLifecycle(_ session: SwitcherSession) {
        guard case .windowCycle(let appID) = session.mode else { return }
        freezeWindowPreviewOrderIfNeeded(for: appID, session: session)
    }

    func clearPreviewSnapshotState() {
        previewImageCache.removeAll()
        previewCaptureAttemptedKeys = []
        previewCaptureFailedKeys = []
        previewCaptureInFlightKeys = []
        previewImageReadyLoggedKeys = []
        previewSessionPinnedKeys = []
        previewSessionPinnedImagesByKey = [:]
        previewDeferredCaptureScheduledAppIDs = []
        previewCaptureGeneration &+= 1
        previewWindowSnapshotsByAppID = [:]
        lastWindowPreviewExposureLogSummary = nil
    }

    func freezeWindowPreviewOrderIfNeeded(
        for appID: String,
        session: SwitcherSession? = nil
    ) {
        guard previewWindowSnapshotsByAppID[appID] == nil else { return }
        let resolvedSession = session ?? self.session
        guard let app = resolvedSession?.apps.first(where: { $0.id == appID }) else { return }
        previewWindowSnapshotsByAppID[appID] = app.windows
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
        let previewWindows = frozenPreviewWindows(for: appID, fallbackApp: app)
        let selectedIndex = selectedPreviewWindowIndex(
            appID: appID,
            session: session,
            previewWindows: previewWindows
        )
        return WindowPreviewPageSummary(
            itemCount: previewWindows.count,
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
        window: WindowCandidate,
        pinForSession: Bool = false,
        captureQoS: DispatchQoS.QoSClass = .userInitiated
    ) -> (image: NSImage?, titleBarStyle: WindowTitleBarStyleGuess?) {
        guard var appContext = runtimeContextsByID[appID] else {
            return (image: nil, titleBarStyle: nil)
        }
        guard var windowContext = appContext.windowsByID[window.id] else {
            return (image: nil, titleBarStyle: nil)
        }
        let ownerPID = windowContext.ownerPID == 0
            ? appContext.runningApp.processIdentifier
            : windowContext.ownerPID
        let previewCacheKey = Self.previewCacheKey(
            appID: appID,
            ownerPID: ownerPID,
            windowContext: windowContext
        )
        if pinForSession {
            previewSessionPinnedKeys.insert(previewCacheKey)
        }
        if let pinned = previewSessionPinnedImagesByKey[previewCacheKey] {
            logPreviewImageReadyOnce(
                source: "pinned",
                appID: appID,
                windowID: window.id,
                key: previewCacheKey,
                cgWindowID: windowContext.cgWindowID
            )
            return (
                image: pinned,
                titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
            )
        }
        if let cached = previewImageCache.image(forKey: previewCacheKey) {
            if pinForSession {
                previewSessionPinnedImagesByKey[previewCacheKey] = cached
            }
            logPreviewImageReadyOnce(
                source: "cache",
                appID: appID,
                windowID: window.id,
                key: previewCacheKey,
                cgWindowID: windowContext.cgWindowID
            )
            return (
                image: cached,
                titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
            )
        }

        if previewCaptureAttemptedKeys.contains(previewCacheKey) {
            if pinForSession,
               !previewCaptureInFlightKeys.contains(previewCacheKey),
               !previewCaptureFailedKeys.contains(previewCacheKey) {
                previewCaptureAttemptedKeys.remove(previewCacheKey)
            } else {
                return (
                    image: nil,
                    titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
                )
            }
        }
        previewCaptureAttemptedKeys.insert(previewCacheKey)

        if let previewCaptureOverride {
            guard
                let capture = previewCaptureOverride(
                    windowContext.cgWindowID,
                    ownerPID,
                    windowContext.title,
                    titleBarStyleInferenceEnabled
                )
            else {
                previewCaptureFailedKeys.insert(previewCacheKey)
                RuntimeLog.debug("Preview", "attempt failed appID=\(appID) windowID=\(window.id)")
                return (
                    image: nil,
                    titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
                )
            }
            applyPreviewCapture(
                capture,
                appID: appID,
                windowID: window.id,
                ownerPID: ownerPID,
                initialCacheKey: previewCacheKey
            )
            logPreviewImageReadyOnce(
                source: "override",
                appID: appID,
                windowID: window.id,
                key: previewCacheKey,
                cgWindowID: capture.resolvedWindowID
            )
            return (
                image: capture.image,
                titleBarStyle: titleBarStyleInferenceEnabled ? capture.titleBarStyle : nil
            )
        }

        scheduleRuntimePreviewCapture(
            appID: appID,
            windowID: window.id,
            ownerPID: ownerPID,
            preferredWindowID: windowContext.cgWindowID,
            preferredTitle: windowContext.title,
            inferTitleBarStyle: titleBarStyleInferenceEnabled,
            initialCacheKey: previewCacheKey,
            qos: captureQoS
        )
        return (
            image: nil,
            titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
        )
    }

    func windowPreviewItems(visibleRange: Range<Int>? = nil) -> [WindowPreviewItem] {
        guard let session else { return [] }
        guard case .windowCycle(let appID) = session.mode else { return [] }
        guard let app = session.apps.first(where: { $0.id == appID }) else { return [] }

        let previewWindows = frozenPreviewWindows(for: appID, fallbackApp: app)
        let selectedIndex = selectedPreviewWindowIndex(
            appID: appID,
            session: session,
            previewWindows: previewWindows
        ) ?? 0
        let indexedWindows = indexedPreviewWindows(in: previewWindows, visibleRange: visibleRange)
        let shouldRequestPreviews = visibleRange != nil || overlayStyle == .windowOnly
        let previewCaptureWindowIDs = shouldRequestPreviews
            ? Set(indexedWindows.map { $0.window.id })
            : []
        let items = indexedWindows.map { index, window in
            let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackTitle = overlayStyle == .windowOnly
                ? "Window \(index + 1)"
                : app.displayName
            let preview = previewCaptureWindowIDs.contains(window.id)
                ? previewData(
                    for: appID,
                    window: window,
                    pinForSession: true,
                    captureQoS: .userInitiated
                )
                : (image: nil, titleBarStyle: nil)
            return WindowPreviewItem(
                id: window.id,
                title: title.isEmpty ? fallbackTitle : title,
                image: preview.image,
                titleBarStyle: preview.titleBarStyle,
                isSelected: index == selectedIndex
            )
        }
        scheduleDeferredPreviewCapturesIfNeeded(
            appID: appID,
            visibleRange: visibleRange,
            visibleItems: items
        )
        logWindowPreviewExposure(
            appID: appID,
            selectedIndex: selectedIndex,
            visibleRange: visibleRange,
            items: items
        )
        return items
    }

    private static func previewCacheKey(
        appID: String,
        ownerPID: pid_t,
        windowContext: RuntimeWindowContext
    ) -> String {
        [
            appID,
            "pid:\(ownerPID)",
            "cg:\(windowContext.cgWindowID.map(String.init) ?? "nil")",
            "window:\(windowContext.id)",
            "title:\(windowContext.title)"
        ].joined(separator: "#")
    }

    private func scheduleRuntimePreviewCapture(
        appID: String,
        windowID: String,
        ownerPID: pid_t,
        preferredWindowID: CGWindowID?,
        preferredTitle: String,
        inferTitleBarStyle: Bool,
        initialCacheKey: String,
        qos: DispatchQoS.QoSClass
    ) {
        guard !previewCaptureInFlightKeys.contains(initialCacheKey) else { return }
        previewCaptureInFlightKeys.insert(initialCacheKey)
        let generation = previewCaptureGeneration
        let semaphore = previewCaptureSemaphore
        let startMs = Self.monotonicMilliseconds()
        RuntimeLog.debug(
            "Preview",
            "capture scheduled appID=\(appID) pid=\(ownerPID) windowID=\(windowID) mappedCG=\(preferredWindowID.map(String.init) ?? "nil")"
        )
        DispatchQueue.global(qos: qos).async {
            semaphore.wait()
            let capture = RuntimeWindowPreviewProvider.captureWindowPreview(
                preferredWindowID: preferredWindowID,
                ownerPID: ownerPID,
                preferredTitle: preferredTitle,
                inferTitleBarStyle: inferTitleBarStyle
            )
            semaphore.signal()
            let completeMs = Self.monotonicMilliseconds()
            Task { @MainActor [weak self] in
                self?.completeRuntimePreviewCapture(
                    capture,
                    appID: appID,
                    windowID: windowID,
                    ownerPID: ownerPID,
                    initialCacheKey: initialCacheKey,
                    generation: generation,
                    startMs: startMs,
                    completeMs: completeMs
                )
            }
        }
    }

    private func completeRuntimePreviewCapture(
        _ capture: (image: NSImage, resolvedWindowID: CGWindowID, titleBarStyle: WindowTitleBarStyleGuess?)?,
        appID: String,
        windowID: String,
        ownerPID: pid_t,
        initialCacheKey: String,
        generation: UInt64,
        startMs: Double,
        completeMs: Double
    ) {
        previewCaptureInFlightKeys.remove(initialCacheKey)
        guard generation == previewCaptureGeneration else {
            RuntimeLog.debug("Preview", "capture stale appID=\(appID) windowID=\(windowID)")
            return
        }
        guard let capture else {
            previewCaptureFailedKeys.insert(initialCacheKey)
            RuntimeLog.debug(
                "Preview",
                "capture failed appID=\(appID) windowID=\(windowID) durationMs=\(Self.formatPreviewMilliseconds(completeMs - startMs))"
            )
            return
        }
        applyPreviewCapture(
            capture,
            appID: appID,
            windowID: windowID,
            ownerPID: ownerPID,
            initialCacheKey: initialCacheKey
        )
        if RuntimeLog.isDebugEnabled(for: "Preview") {
            RuntimeLog.debug(
                "Preview",
                "image ready source=capture appID=\(appID) windowID=\(windowID) resolvedCG=\(capture.resolvedWindowID) titleBarStyle=\(capture.titleBarStyle?.rawValue ?? "nil") durationMs=\(Self.formatPreviewMilliseconds(completeMs - startMs))"
            )
            previewImageReadyLoggedKeys.insert(initialCacheKey)
        }
        objectWillChange.send()
    }

    private func applyPreviewCapture(
        _ capture: (image: NSImage, resolvedWindowID: CGWindowID, titleBarStyle: WindowTitleBarStyleGuess?),
        appID: String,
        windowID: String,
        ownerPID: pid_t,
        initialCacheKey: String
    ) {
        guard var appContext = runtimeContextsByID[appID] else { return }
        guard var windowContext = appContext.windowsByID[windowID] else { return }
        windowContext.cgWindowID = capture.resolvedWindowID
        windowContext.inferredTitleBarStyle = capture.titleBarStyle
        var windowsByID = appContext.windowsByID
        windowsByID[windowID] = windowContext
        appContext = RuntimeAppContext(
            appID: appContext.appID,
            runningApp: appContext.runningApp,
            windowsByID: windowsByID
        )
        runtimeContextsByID[appID] = appContext
        let resolvedCacheKey = Self.previewCacheKey(
            appID: appID,
            ownerPID: ownerPID,
            windowContext: windowContext
        )
        previewImageCache.insert(capture.image, forKey: initialCacheKey)
        previewImageCache.insert(capture.image, forKey: resolvedCacheKey)
        previewCaptureFailedKeys.remove(initialCacheKey)
        previewCaptureFailedKeys.remove(resolvedCacheKey)
        pinPreviewImageIfNeeded(
            capture.image,
            initialCacheKey: initialCacheKey,
            resolvedCacheKey: resolvedCacheKey
        )
        previewCaptureAttemptedKeys.insert(resolvedCacheKey)
    }

    private func pinPreviewImageIfNeeded(
        _ image: NSImage,
        initialCacheKey: String,
        resolvedCacheKey: String
    ) {
        guard
            previewSessionPinnedKeys.contains(initialCacheKey)
                || previewSessionPinnedKeys.contains(resolvedCacheKey)
        else {
            return
        }
        previewSessionPinnedKeys.insert(initialCacheKey)
        previewSessionPinnedKeys.insert(resolvedCacheKey)
        previewSessionPinnedImagesByKey[initialCacheKey] = image
        previewSessionPinnedImagesByKey[resolvedCacheKey] = image
    }

    private static func formatPreviewMilliseconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func logPreviewImageReadyOnce(
        source: String,
        appID: String,
        windowID: String,
        key: String,
        cgWindowID: CGWindowID?
    ) {
        guard RuntimeLog.isDebugEnabled(for: "Preview") else { return }
        guard !previewImageReadyLoggedKeys.contains(key) else { return }
        previewImageReadyLoggedKeys.insert(key)
        RuntimeLog.debug(
            "Preview",
            "image ready source=\(source) appID=\(appID) windowID=\(windowID) cg=\(cgWindowID.map(String.init) ?? "nil")"
        )
    }

    private func logWindowPreviewExposure(
        appID: String,
        selectedIndex: Int,
        visibleRange: Range<Int>?,
        items: [WindowPreviewItem]
    ) {
        guard RuntimeLog.isDebugEnabled(for: "Preview") else { return }
        let imageCount = items.reduce(0) { count, item in
            count + (item.image == nil ? 0 : 1)
        }
        let rangeSummary = visibleRange.map { "\($0.lowerBound)..<\($0.upperBound)" } ?? "all"
        let itemSummary = items.map { item in
            let imageState = item.image == nil ? "fallback" : "image"
            let selectedState = item.isSelected ? ":selected" : ""
            return "\(item.id)=\(imageState)\(selectedState)"
        }.joined(separator: "|")
        let summary = [
            "appID=\(appID)",
            "range=\(rangeSummary)",
            "selectedIndex=\(selectedIndex)",
            "itemCount=\(items.count)",
            "imageCount=\(imageCount)",
            "items=\(itemSummary)"
        ].joined(separator: " ")
        guard lastWindowPreviewExposureLogSummary != summary else { return }
        lastWindowPreviewExposureLogSummary = summary
        RuntimeLog.debug("Preview", "display \(summary)")
    }

    private func frozenPreviewWindows(
        for appID: String,
        fallbackApp app: AppSwitchCandidate
    ) -> [WindowCandidate] {
        previewWindowSnapshotsByAppID[appID] ?? app.windows
    }

    private func selectedPreviewWindowIndex(
        appID: String,
        session: SwitcherSession,
        previewWindows: [WindowCandidate]
    ) -> Int? {
        guard !previewWindows.isEmpty else { return nil }
        if let selectedWindowID = session.selectedWindow?.id,
           let index = previewWindows.firstIndex(where: { $0.id == selectedWindowID }) {
            return index
        }
        return session.selectedWindowIndexByAppID[appID]
            .map { min(max(0, $0), max(previewWindows.count - 1, 0)) }
    }

    private func indexedPreviewWindows(
        in windows: [WindowCandidate],
        visibleRange: Range<Int>?
    ) -> [(index: Int, window: WindowCandidate)] {
        guard let visibleRange else {
            return windows.enumerated().map { (index: $0.offset, window: $0.element) }
        }
        let lowerBound = min(max(0, visibleRange.lowerBound), windows.count)
        let upperBound = min(max(lowerBound, visibleRange.upperBound), windows.count)
        guard lowerBound < upperBound else { return [] }
        return windows[lowerBound..<upperBound].enumerated().map {
            (index: lowerBound + $0.offset, window: $0.element)
        }
    }

    private func scheduleDeferredPreviewCapturesIfNeeded(
        appID: String,
        visibleRange: Range<Int>?,
        visibleItems: [WindowPreviewItem]
    ) {
        guard visibleRange != nil else { return }
        guard !visibleItems.isEmpty, visibleItems.allSatisfy({ $0.image != nil }) else { return }
        guard !previewDeferredCaptureScheduledAppIDs.contains(appID) else { return }
        previewDeferredCaptureScheduledAppIDs.insert(appID)
        let generation = previewCaptureGeneration
        let visibleWindowIDs = Set(visibleItems.map(\.id))

        DispatchQueue.main.async { [weak self] in
            Task { @MainActor [weak self] in
                self?.startDeferredPreviewCaptures(
                    appID: appID,
                    excludingWindowIDs: visibleWindowIDs,
                    generation: generation
                )
            }
        }
    }

    private func startDeferredPreviewCaptures(
        appID: String,
        excludingWindowIDs visibleWindowIDs: Set<String>,
        generation: UInt64
    ) {
        guard generation == previewCaptureGeneration else { return }
        guard let session else { return }
        guard case .windowCycle(let windowLayerAppID) = session.mode, windowLayerAppID == appID else {
            return
        }
        guard let app = session.apps.first(where: { $0.id == appID }) else { return }

        let previewWindows = frozenPreviewWindows(for: appID, fallbackApp: app)
        for window in previewWindows where !visibleWindowIDs.contains(window.id) {
            _ = previewData(
                for: appID,
                window: window,
                pinForSession: false,
                captureQoS: .utility
            )
        }
    }

    func windowPreviewSnapshotForTesting(visibleRange: Range<Int>? = nil) -> [(
        id: String,
        title: String,
        hasImage: Bool,
        titleBarStyle: WindowTitleBarStyleGuess?,
        isSelected: Bool
    )] {
        windowPreviewItems(visibleRange: visibleRange).map {
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
