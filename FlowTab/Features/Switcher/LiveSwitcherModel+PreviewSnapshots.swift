import FlowTabCore

extension LiveSwitcherModel {
    @discardableResult
    func prewarmWindowOnlySessionPreviews() -> Int {
        guard overlayStyle == .windowOnly else { return 0 }
        guard let session, case .windowCycle = session.mode else { return 0 }
        return windowPreviewItems().count
    }

    var isWindowOnlyPreviewPreparationComplete: Bool {
        previewCaptureInFlightKeys.isEmpty
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

    func refreshFrozenPreviewOrderIfChanged(
        for appID: String,
        windows: [WindowCandidate]
    ) {
        guard let frozenWindows = previewWindowSnapshotsByAppID[appID] else { return }
        guard frozenWindows.map(\.id) != windows.map(\.id) else { return }
        previewWindowSnapshotsByAppID[appID] = windows
        previewDeferredCaptureScheduledAppIDs.remove(appID)
        lastWindowPreviewExposureLogSummary = nil
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
