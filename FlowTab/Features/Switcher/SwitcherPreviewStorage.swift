import AppKit
import Combine
import FlowTabCore

@MainActor
final class SwitcherRuntimeContextStore {
    var values: [String: RuntimeAppContext] = [:]
}

@MainActor
final class SwitcherPreviewStorage {
    let previewImageCache = BoundedImageCache(
        countLimit: 64,
        totalCostLimit: 160 * 1_024 * 1_024
    )
    var previewCaptureAttemptedKeys: Set<String> = []
    var previewCaptureFailedKeys: Set<String> = []
    var previewCaptureInFlightKeys: Set<String> = []
    var previewCaptureStatesByKey: [String: PreviewCaptureState] = [:]
    var previewImageReadyLoggedKeys: Set<String> = []
    var previewSessionPinnedKeys: Set<String> = []
    var previewSessionPinnedImagesByKey: [String: NSImage] = [:]
    var previewDeferredCaptureScheduledAppIDs: Set<String> = []
    var previewCaptureGeneration: UInt64 = 0
    var previewCaptureCancellationsByID:
        [UUID: WindowPreviewCaptureCancellation] = [:]
    let previewCaptureSemaphore = DispatchSemaphore(value: 4)
    var previewWindowSnapshotsByAppID: [String: [WindowCandidate]] = [:]
    var lastWindowPreviewExposureLogSummary: String?
}
