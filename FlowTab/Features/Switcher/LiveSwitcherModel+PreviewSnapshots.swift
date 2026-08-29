import FlowTabCore

extension LiveSwitcherModel {
    @discardableResult
    func prewarmWindowOnlySessionPreviews() -> Int {
        guard overlayStyle == .windowOnly else { return 0 }
        guard let session, case .windowCycle = session.mode else { return 0 }
        return windowPreviewItems().count
    }

    var windowOnlyPreviewCaptureInFlightCount: Int {
        previewCaptureInFlightKeys.count
    }

    func handleSessionPreviewSnapshotLifecycle(_ session: SwitcherSession) {
        guard case .windowCycle(let appID) = session.mode else { return }
        freezeWindowPreviewOrderIfNeeded(for: appID, session: session)
    }

    func clearPreviewSnapshotState() {
        previewCaptureCancellationsByID.values.forEach { $0.cancel() }
        previewCaptureCancellationsByID.removeAll()
        previewImageCache.removeAll()
        previewCaptureAttemptedKeys = []
        previewCaptureFailedKeys = []
        previewCaptureInFlightKeys = []
        previewCaptureStatesByKey = [:]
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

    func previewCaptureStatesForTesting() -> [String: PreviewCaptureState] {
        previewCaptureStatesByKey
    }
}
