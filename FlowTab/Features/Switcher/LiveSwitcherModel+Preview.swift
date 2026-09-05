import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

enum PreviewCaptureFailureReason: String, Equatable {
    case permissionDenied
    case windowNotFound
    case screenCaptureUnavailable
    case transientSystemError
    case specialProviderUnavailable
    case cancelledByNewerGeneration
    case bindingActionDisallowed
}

enum PreviewCaptureState: Equatable {
    case notRequested
    case queued(generation: UInt64)
    case inFlight(generation: UInt64)
    case succeeded(cacheKey: String, generation: UInt64)
    case failed(reason: PreviewCaptureFailureReason, retryAfterGeneration: UInt64?)
}

extension LiveSwitcherModel {

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
        let previewWindows = SwitcherPreviewSupport.frozenPreviewWindows(for: appID, fallbackApp: app, snapshots: previewWindowSnapshotsByAppID)
        let selectedIndex = SwitcherPreviewSupport.selectedPreviewWindowIndex(
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

    private var previewPlanningContext: SwitcherPreviewPlanningContext {
        SwitcherPreviewPlanningContext(session: session, overlayStyle: overlayStyle,
            titleBarStyleInferenceEnabled: titleBarStyleInferenceEnabled,
            previewCaptureOverride: previewCaptureOverride)
    }

    private func resolvePreviewData(for appID: String, window: WindowCandidate,
                                    pinForSession: Bool) -> ResolvedPreviewData {
        previewPlanner.resolve(context: previewPlanningContext, appID: appID,
            window: window, pinForSession: pinForSession)
    }

    @discardableResult
    func prewarmSelectedAppWindowPreviews(availableWidth: CGFloat) -> Int {
        guard let session, case .appCycle = session.mode else { return 0 }
        let app = session.selectedApp
        guard !app.windows.isEmpty, runtimeContextsByID[app.id] != nil else { return 0 }

        freezeWindowPreviewOrderIfNeeded(for: app.id, session: session)
        let previewWindows = SwitcherPreviewSupport.frozenPreviewWindows(for: app.id, fallbackApp: app, snapshots: previewWindowSnapshotsByAppID)
        let selectedIndex = session.selectedWindowIndexByAppID[app.id] ?? 0
        let page = SwitcherWindowPreviewPaging.page(
            itemCount: previewWindows.count,
            selectedIndex: selectedIndex,
            availableWidth: availableWidth
        )
        var pendingCaptures: [PendingPreviewCapture] = []
        pendingCaptures.reserveCapacity(page.visibleRange.count)
        for index in page.visibleRange {
            let previewResult = resolvePreviewData(
                for: app.id,
                window: previewWindows[index],
                pinForSession: true
            )
            if let pendingCapture = previewResult.pendingCapture {
                pendingCaptures.append(pendingCapture)
            }
        }
        scheduleRuntimePreviewCaptures(pendingCaptures, qos: .userInitiated)
        return page.visibleRange.count
    }

    func windowPreviewItems(visibleRange: Range<Int>? = nil) -> [WindowPreviewItem] {
        guard let plan = previewPlanner.plan(context: previewPlanningContext, visibleRange: visibleRange) else { return [] }
        scheduleRuntimePreviewCaptures(plan.pendingCaptures, qos: .userInitiated)
        scheduleDeferredPreviewCapturesIfNeeded(appID: plan.appID,
            visibleRange: visibleRange, visibleItems: plan.items)
        logWindowPreviewExposure(appID: plan.appID, selectedIndex: plan.selectedIndex,
            visibleRange: visibleRange, items: plan.items)
        return plan.items
    }

    private func scheduleRuntimePreviewCaptures(
        _ pendingCaptures: [PendingPreviewCapture],
        qos: DispatchQoS.QoSClass
    ) {
        guard !pendingCaptures.isEmpty else { return }
        let generation = previewCaptureGeneration
        let semaphore = previewCaptureSemaphore
        let resolver = previewProviderResolver
        let batchOverride = previewCaptureBatchOverride
        let batchOutcomeOverride = previewCaptureBatchOutcomeOverride
        let batchID = UUID()
        let cancellation = WindowPreviewCaptureCancellation()
        previewCaptureCancellationsByID[batchID] = cancellation
        let batch = previewBatchFactory.makeBatch(
            request: SwitcherPreviewBatchRequest(id: batchID, captures: pendingCaptures,
                generation: generation, cancellation: cancellation, captureSemaphore: semaphore),
            resolver: resolver, capture: batchOverride, captureOutcomes: batchOutcomeOverride
        )
        let startMs = Self.monotonicMilliseconds()
        for pendingCapture in pendingCaptures {
            RuntimeLog.debug(
                "Preview",
                "capture scheduled appID=\(pendingCapture.appID) pid=\(pendingCapture.ownerPID) windowID=\(pendingCapture.windowID) mappedCG=\(pendingCapture.preferredWindowID.map(String.init) ?? "nil")"
            )
        }
        Task.detached(priority: SwitcherPreviewSupport.previewTaskPriority(for: qos)) {
            let outcomes = await batch.capture()
            let completeMs = Self.monotonicMilliseconds()
            Task { @MainActor [weak self] in
                self?.completeRuntimePreviewCaptureBatch(
                    outcomes,
                    pendingCaptures: pendingCaptures,
                    batchID: batchID,
                    cancellation: cancellation,
                    generation: generation,
                    startMs: startMs,
                    completeMs: completeMs
                )
            }
        }
    }

    private func completeRuntimePreviewCaptureBatch(
        _ outcomes: [WindowPreviewResult], pendingCaptures: [PendingPreviewCapture],
        batchID: UUID, cancellation: WindowPreviewCaptureCancellation,
        generation: UInt64, startMs: Double, completeMs: Double
    ) {
        _ = previewSession.completeBatch(outcomes, pendingCaptures: pendingCaptures,
            batchID: batchID, cancellation: cancellation, generation: generation,
            startMs: startMs, completeMs: completeMs)
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

        let previewWindows = SwitcherPreviewSupport.frozenPreviewWindows(for: appID, fallbackApp: app, snapshots: previewWindowSnapshotsByAppID)
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

    var selectedApp: AppSwitchCandidate? {
        session?.selectedApp
    }

    var canAutoEnterWindowLayer: Bool {
        guard let session else { return false }
        guard !searchViewState.isActive, !pendingSearchActivationAfterFreshnessBarrier else { return false }
        if case .windowCycle = session.mode {
            return false
        }
        if autoEnterSuppressedAppID == session.selectedApp.id {
            return false
        }
        guard let readiness = sessionAppWindowReadiness,
              readiness.identity.appID == session.selectedApp.id
        else {
            return false
        }
        return (readiness.readyWindowCount ?? 0) >= 2
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
            guard let app = committedSearchAppsByID[appID] else {
                return nil
            }
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
            let app = committedSearchAppsByID[appID]
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
