import AppKit
import Combine
import FlowTabCore

enum PreviewBatchApplication: Equatable {
    case cancelled
    case stale
    case applied(completedCount: Int)
}

@MainActor
protocol SwitcherPreviewSessionOperating: AnyObject {
    func clear()
    func applyPreviewCapture(
        _ capture: (image: NSImage, resolvedWindowID: CGWindowID?, titleBarStyle: WindowTitleBarStyleGuess?),
        appID: String, windowID: String, ownerPID: pid_t, initialCacheKey: String
    )
    func completeBatch(_ outcomes: [WindowPreviewResult], pendingCaptures: [PendingPreviewCapture],
                       batchID: UUID, cancellation: WindowPreviewCaptureCancellation,
                       generation: UInt64, startMs: Double, completeMs: Double) -> PreviewBatchApplication
}

@MainActor
final class SwitcherPreviewSession: SwitcherPreviewSessionOperating {
    let state: SwitcherPreviewStorage
    let contexts: SwitcherRuntimeContextStore
    var publication: any SwitcherPreviewPublishing

    init(state: SwitcherPreviewStorage, contexts: SwitcherRuntimeContextStore,
         publication: any SwitcherPreviewPublishing) {
        self.state = state
        self.contexts = contexts
        self.publication = publication
    }

    func applyPreviewCapture(
        _ capture: (image: NSImage, resolvedWindowID: CGWindowID?, titleBarStyle: WindowTitleBarStyleGuess?),
        appID: String,
        windowID: String,
        ownerPID: pid_t,
        initialCacheKey: String
    ) {
        guard var appContext = contexts.values[appID] else { return }
        guard var windowContext = appContext.windowsByID[windowID] else { return }
        if let resolvedWindowID = capture.resolvedWindowID {
            windowContext.cgWindowID = resolvedWindowID
        }
        windowContext.inferredTitleBarStyle = capture.titleBarStyle
        var windowsByID = appContext.windowsByID
        windowsByID[windowID] = windowContext
        appContext = RuntimeAppContext(
            appID: appContext.appID,
            runningApp: appContext.runningApp,
            ownerPID: appContext.ownerPID,
            windowsByID: windowsByID
        )
        contexts.values[appID] = appContext
        let resolvedCacheKey = SwitcherPreviewSupport.previewCacheKey(
            appID: appID,
            ownerPID: ownerPID,
            windowContext: windowContext
        )
        state.previewImageCache.insert(capture.image, forKey: initialCacheKey)
        state.previewImageCache.insert(capture.image, forKey: resolvedCacheKey)
        state.previewCaptureFailedKeys.remove(initialCacheKey)
        state.previewCaptureFailedKeys.remove(resolvedCacheKey)
        state.previewCaptureStatesByKey[initialCacheKey] = .succeeded(
            cacheKey: resolvedCacheKey,
            generation: state.previewCaptureGeneration
        )
        state.previewCaptureStatesByKey[resolvedCacheKey] = .succeeded(
            cacheKey: resolvedCacheKey,
            generation: state.previewCaptureGeneration
        )
        pinPreviewImageIfNeeded(
            capture.image,
            initialCacheKey: initialCacheKey,
            resolvedCacheKey: resolvedCacheKey
        )
        state.previewCaptureAttemptedKeys.insert(resolvedCacheKey)
    }
    func pinPreviewImageIfNeeded(
        _ image: NSImage,
        initialCacheKey: String,
        resolvedCacheKey: String
    ) {
        guard
            state.previewSessionPinnedKeys.contains(initialCacheKey)
                || state.previewSessionPinnedKeys.contains(resolvedCacheKey)
        else {
            return
        }
        state.previewSessionPinnedKeys.insert(initialCacheKey)
        state.previewSessionPinnedKeys.insert(resolvedCacheKey)
        state.previewSessionPinnedImagesByKey[initialCacheKey] = image
        state.previewSessionPinnedImagesByKey[resolvedCacheKey] = image
    }
    func clear() {
        state.previewCaptureCancellationsByID.values.forEach { $0.cancel() }
        state.previewCaptureCancellationsByID.removeAll()
        state.previewImageCache.removeAll()
        state.previewCaptureAttemptedKeys = []
        state.previewCaptureFailedKeys = []
        state.previewCaptureInFlightKeys = []
        state.previewCaptureStatesByKey = [:]
        state.previewImageReadyLoggedKeys = []
        state.previewSessionPinnedKeys = []
        state.previewSessionPinnedImagesByKey = [:]
        state.previewDeferredCaptureScheduledAppIDs = []
        state.previewCaptureGeneration &+= 1
        state.previewWindowSnapshotsByAppID = [:]
        state.lastWindowPreviewExposureLogSummary = nil
    }
}
