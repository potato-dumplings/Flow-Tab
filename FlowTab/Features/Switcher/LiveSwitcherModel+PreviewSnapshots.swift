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
}
