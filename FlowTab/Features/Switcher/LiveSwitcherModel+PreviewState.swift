import AppKit
import FlowTabCore

extension LiveSwitcherModel {
    var previewCaptureAttemptedKeys: Set<String> {
        get { previewStorage.previewCaptureAttemptedKeys }
        set { previewStorage.previewCaptureAttemptedKeys = newValue }
        _modify { yield &previewStorage.previewCaptureAttemptedKeys }
    }
    var previewCaptureFailedKeys: Set<String> {
        get { previewStorage.previewCaptureFailedKeys }
        set { previewStorage.previewCaptureFailedKeys = newValue }
        _modify { yield &previewStorage.previewCaptureFailedKeys }
    }
    var previewCaptureInFlightKeys: Set<String> {
        get { previewStorage.previewCaptureInFlightKeys }
        set { previewStorage.previewCaptureInFlightKeys = newValue }
        _modify { yield &previewStorage.previewCaptureInFlightKeys }
    }
    var previewCaptureStatesByKey: [String: PreviewCaptureState] {
        get { previewStorage.previewCaptureStatesByKey }
        set { previewStorage.previewCaptureStatesByKey = newValue }
        _modify { yield &previewStorage.previewCaptureStatesByKey }
    }
    var previewImageReadyLoggedKeys: Set<String> {
        get { previewStorage.previewImageReadyLoggedKeys }
        set { previewStorage.previewImageReadyLoggedKeys = newValue }
        _modify { yield &previewStorage.previewImageReadyLoggedKeys }
    }
    var previewSessionPinnedKeys: Set<String> {
        get { previewStorage.previewSessionPinnedKeys }
        set { previewStorage.previewSessionPinnedKeys = newValue }
        _modify { yield &previewStorage.previewSessionPinnedKeys }
    }
    var previewSessionPinnedImagesByKey: [String: NSImage] {
        get { previewStorage.previewSessionPinnedImagesByKey }
        set { previewStorage.previewSessionPinnedImagesByKey = newValue }
        _modify { yield &previewStorage.previewSessionPinnedImagesByKey }
    }
    var previewDeferredCaptureScheduledAppIDs: Set<String> {
        get { previewStorage.previewDeferredCaptureScheduledAppIDs }
        set { previewStorage.previewDeferredCaptureScheduledAppIDs = newValue }
        _modify { yield &previewStorage.previewDeferredCaptureScheduledAppIDs }
    }
    var previewCaptureGeneration: UInt64 {
        get { previewStorage.previewCaptureGeneration }
        set { previewStorage.previewCaptureGeneration = newValue }
        _modify { yield &previewStorage.previewCaptureGeneration }
    }
    var previewCaptureCancellationsByID: [UUID: WindowPreviewCaptureCancellation] {
        get { previewStorage.previewCaptureCancellationsByID }
        set { previewStorage.previewCaptureCancellationsByID = newValue }
        _modify { yield &previewStorage.previewCaptureCancellationsByID }
    }
    var previewCaptureSemaphore: DispatchSemaphore {
        get { previewStorage.previewCaptureSemaphore }
    }
    var previewWindowSnapshotsByAppID: [String: [WindowCandidate]] {
        get { previewStorage.previewWindowSnapshotsByAppID }
        set { previewStorage.previewWindowSnapshotsByAppID = newValue }
        _modify { yield &previewStorage.previewWindowSnapshotsByAppID }
    }
    var lastWindowPreviewExposureLogSummary: String? {
        get { previewStorage.lastWindowPreviewExposureLogSummary }
        set { previewStorage.lastWindowPreviewExposureLogSummary = newValue }
        _modify { yield &previewStorage.lastWindowPreviewExposureLogSummary }
    }
}
