import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

extension LiveSwitcherModel {
    private struct PendingPreviewCapture {
        let appID: String
        let windowID: String
        let ownerPID: pid_t
        let preferredWindowID: CGWindowID?
        let preferredTitle: String
        let inferTitleBarStyle: Bool
        let initialCacheKey: String

        var providerRequest: RuntimeWindowPreviewProvider.CaptureRequest {
            RuntimeWindowPreviewProvider.CaptureRequest(
                preferredWindowID: preferredWindowID,
                ownerPID: ownerPID,
                preferredTitle: preferredTitle,
                inferTitleBarStyle: inferTitleBarStyle
            )
        }
    }

    private struct ResolvedPreviewData {
        let preview: (image: NSImage?, titleBarStyle: WindowTitleBarStyleGuess?)
        let pendingCapture: PendingPreviewCapture?
        let isWaitingForCaptureCommit: Bool
    }

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
        let result = resolvePreviewData(
            for: appID,
            window: window,
            pinForSession: pinForSession
        )
        if let pendingCapture = result.pendingCapture {
            scheduleRuntimePreviewCaptures([pendingCapture], qos: captureQoS)
        }
        return result.preview
    }

    private func resolvePreviewData(
        for appID: String,
        window: WindowCandidate,
        pinForSession: Bool
    ) -> ResolvedPreviewData {
        guard var appContext = runtimeContextsByID[appID] else {
            return ResolvedPreviewData(
                preview: (image: nil, titleBarStyle: nil),
                pendingCapture: nil,
                isWaitingForCaptureCommit: false
            )
        }
        guard var windowContext = appContext.windowsByID[window.id] else {
            return ResolvedPreviewData(
                preview: (image: nil, titleBarStyle: nil),
                pendingCapture: nil,
                isWaitingForCaptureCommit: false
            )
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
            return ResolvedPreviewData(
                preview: (
                    image: pinned,
                    titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
                ),
                pendingCapture: nil,
                isWaitingForCaptureCommit: false
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
            return ResolvedPreviewData(
                preview: (
                    image: cached,
                    titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
                ),
                pendingCapture: nil,
                isWaitingForCaptureCommit: false
            )
        }

        if previewCaptureAttemptedKeys.contains(previewCacheKey) {
            if pinForSession,
               !previewCaptureInFlightKeys.contains(previewCacheKey),
               !previewCaptureFailedKeys.contains(previewCacheKey) {
                previewCaptureAttemptedKeys.remove(previewCacheKey)
            } else {
                return ResolvedPreviewData(
                    preview: (
                        image: nil,
                        titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
                    ),
                    pendingCapture: nil,
                    isWaitingForCaptureCommit: previewCaptureInFlightKeys.contains(previewCacheKey)
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
                RuntimeLog.debug(.preview, "attempt failed appID=\(appID) windowID=\(window.id)")
                return ResolvedPreviewData(
                    preview: (
                        image: nil,
                        titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
                    ),
                    pendingCapture: nil,
                    isWaitingForCaptureCommit: false
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
            return ResolvedPreviewData(
                preview: (
                    image: capture.image,
                    titleBarStyle: titleBarStyleInferenceEnabled ? capture.titleBarStyle : nil
                ),
                pendingCapture: nil,
                isWaitingForCaptureCommit: false
            )
        }

        guard !previewCaptureInFlightKeys.contains(previewCacheKey) else {
            return ResolvedPreviewData(
                preview: (
                    image: nil,
                    titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
                ),
                pendingCapture: nil,
                isWaitingForCaptureCommit: true
            )
        }
        previewCaptureInFlightKeys.insert(previewCacheKey)
        let pendingCapture = PendingPreviewCapture(
            appID: appID,
            windowID: window.id,
            ownerPID: ownerPID,
            preferredWindowID: windowContext.cgWindowID,
            preferredTitle: windowContext.title,
            inferTitleBarStyle: titleBarStyleInferenceEnabled,
            initialCacheKey: previewCacheKey
        )
        return ResolvedPreviewData(
            preview: (
                image: nil,
                titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
            ),
            pendingCapture: pendingCapture,
            isWaitingForCaptureCommit: true
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
        var pendingCaptures: [PendingPreviewCapture] = []
        var items: [WindowPreviewItem] = []
        var isWaitingForVisiblePreviewCommit = false
        items.reserveCapacity(indexedWindows.count)
        pendingCaptures.reserveCapacity(previewCaptureWindowIDs.count)
        for (index, window) in indexedWindows {
            let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackTitle = overlayStyle == .windowOnly
                ? "Window \(index + 1)"
                : app.displayName
            let preview: (image: NSImage?, titleBarStyle: WindowTitleBarStyleGuess?)
            if previewCaptureWindowIDs.contains(window.id) {
                let previewResult = resolvePreviewData(
                    for: appID,
                    window: window,
                    pinForSession: true
                )
                preview = previewResult.preview
                if let pendingCapture = previewResult.pendingCapture {
                    pendingCaptures.append(pendingCapture)
                }
                isWaitingForVisiblePreviewCommit = isWaitingForVisiblePreviewCommit
                    || previewResult.isWaitingForCaptureCommit
            } else {
                preview = (image: nil, titleBarStyle: nil)
            }
            items.append(
                WindowPreviewItem(
                    id: window.id,
                    title: title.isEmpty ? fallbackTitle : title,
                    image: preview.image,
                    titleBarStyle: preview.titleBarStyle,
                    isSelected: index == selectedIndex
                )
            )
        }
        scheduleRuntimePreviewCaptures(pendingCaptures, qos: .userInitiated)
        if isWaitingForVisiblePreviewCommit {
            return []
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

    private func scheduleRuntimePreviewCaptures(
        _ pendingCaptures: [PendingPreviewCapture],
        qos: DispatchQoS.QoSClass
    ) {
        guard !pendingCaptures.isEmpty else { return }
        let generation = previewCaptureGeneration
        let semaphore = previewCaptureSemaphore
        let batchOverride = previewCaptureBatchOverride
        let requests = pendingCaptures.map(\.providerRequest)
        let startMs = Self.monotonicMilliseconds()
        for pendingCapture in pendingCaptures {
            RuntimeLog.debug(
                "Preview",
                "capture scheduled appID=\(pendingCapture.appID) pid=\(pendingCapture.ownerPID) windowID=\(pendingCapture.windowID) mappedCG=\(pendingCapture.preferredWindowID.map(String.init) ?? "nil")"
            )
        }
        DispatchQueue.global(qos: qos).async {
            let captures = batchOverride?(requests) ?? RuntimeWindowPreviewProvider.captureWindowPreviews(
                requests,
                captureSemaphore: semaphore
            )
            let completeMs = Self.monotonicMilliseconds()
            Task { @MainActor [weak self] in
                self?.completeRuntimePreviewCaptureBatch(
                    captures,
                    pendingCaptures: pendingCaptures,
                    generation: generation,
                    startMs: startMs,
                    completeMs: completeMs
                )
            }
        }
    }

    private func completeRuntimePreviewCaptureBatch(
        _ captures: [RuntimeWindowPreviewProvider.CaptureResult?],
        pendingCaptures: [PendingPreviewCapture],
        generation: UInt64,
        startMs: Double,
        completeMs: Double
    ) {
        for pendingCapture in pendingCaptures {
            previewCaptureInFlightKeys.remove(pendingCapture.initialCacheKey)
        }
        guard generation == previewCaptureGeneration else {
            RuntimeLog.debug(.preview, "capture batch stale count=\(pendingCaptures.count)")
            return
        }
        var completedCount = 0
        for (index, pendingCapture) in pendingCaptures.enumerated() {
            let capture = captures.indices.contains(index) ? captures[index] : nil
            completedCount += 1
            guard let capture else {
                previewCaptureFailedKeys.insert(pendingCapture.initialCacheKey)
                RuntimeLog.debug(
                    "Preview",
                    "capture failed appID=\(pendingCapture.appID) windowID=\(pendingCapture.windowID) durationMs=\(Self.formatPreviewMilliseconds(completeMs - startMs))"
                )
                continue
            }
            applyPreviewCapture(
                (
                    image: capture.image,
                    resolvedWindowID: capture.resolvedWindowID,
                    titleBarStyle: capture.titleBarStyle
                ),
                appID: pendingCapture.appID,
                windowID: pendingCapture.windowID,
                ownerPID: pendingCapture.ownerPID,
                initialCacheKey: pendingCapture.initialCacheKey
            )
            if RuntimeLog.isDebugEnabled(for: "Preview") {
                RuntimeLog.debug(
                    "Preview",
                    "image ready source=capture appID=\(pendingCapture.appID) windowID=\(pendingCapture.windowID) resolvedCG=\(capture.resolvedWindowID) titleBarStyle=\(capture.titleBarStyle?.rawValue ?? "nil") durationMs=\(Self.formatPreviewMilliseconds(completeMs - startMs))"
                )
                previewImageReadyLoggedKeys.insert(pendingCapture.initialCacheKey)
            }
        }
        if completedCount > 0 {
            objectWillChange.send()
        }
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
        RuntimeLog.debug(.preview, "display \(summary)")
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
        var pendingCaptures: [PendingPreviewCapture] = []
        for window in previewWindows where !visibleWindowIDs.contains(window.id) {
            let previewResult = resolvePreviewData(
                for: appID,
                window: window,
                pinForSession: false
            )
            if let pendingCapture = previewResult.pendingCapture {
                pendingCaptures.append(pendingCapture)
            }
        }
        scheduleRuntimePreviewCaptures(pendingCaptures, qos: .utility)
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
