import AppKit
import FlowTabCore

extension SwitcherPreviewPlanner.Operation {
    func resolvePreviewData(
        for appID: String,
        window: WindowCandidate,
        pinForSession: Bool
    ) -> ResolvedPreviewData {
        guard var appContext = contexts.values[appID] else {
            return ResolvedPreviewData(
                preview: (image: nil, titleBarStyle: nil),
                pendingCapture: nil
            )
        }
        guard var windowContext = appContext.windowsByID[window.id] else {
            return ResolvedPreviewData(
                preview: (image: nil, titleBarStyle: nil),
                pendingCapture: nil
            )
        }
        let ownerPID = windowContext.ownerPID == 0
            ? appContext.runningApp.processIdentifier
            : windowContext.ownerPID
        let previewCacheKey = SwitcherPreviewSupport.previewCacheKey(
            appID: appID,
            ownerPID: ownerPID,
            windowContext: windowContext
        )
        guard windowContext.bindingAllowedActions.contains(.capturePreview) else {
            state.previewCaptureAttemptedKeys.insert(previewCacheKey)
            state.previewCaptureFailedKeys.insert(previewCacheKey)
            state.previewCaptureStatesByKey[previewCacheKey] = .failed(
                reason: .bindingActionDisallowed,
                retryAfterGeneration: nil
            )
            RuntimeLog.debug(
                .preview,
                "capture skipped appID=\(appID) windowID=\(window.id) reason=binding_action_disallowed confidence=\(windowContext.bindingConfidence.rawValue) allowedActions=\(SwitcherPreviewSupport.previewAllowedActionsDescription(windowContext.bindingAllowedActions))"
            )
            return ResolvedPreviewData(
                preview: (
                    image: nil,
                    titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
                ),
                pendingCapture: nil
            )
        }
        if pinForSession {
            state.previewSessionPinnedKeys.insert(previewCacheKey)
        }
        if let pinned = state.previewSessionPinnedImagesByKey[previewCacheKey] {
            state.previewCaptureStatesByKey[previewCacheKey] = .succeeded(
                cacheKey: previewCacheKey,
                generation: state.previewCaptureGeneration
            )
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
                pendingCapture: nil
            )
        }
        if let cached = state.previewImageCache.image(forKey: previewCacheKey) {
            state.previewCaptureStatesByKey[previewCacheKey] = .succeeded(
                cacheKey: previewCacheKey,
                generation: state.previewCaptureGeneration
            )
            if pinForSession {
                state.previewSessionPinnedImagesByKey[previewCacheKey] = cached
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
                pendingCapture: nil
            )
        }

        if state.previewCaptureAttemptedKeys.contains(previewCacheKey) {
            if shouldRetryPreviewCapture(previewCacheKey) {
                state.previewCaptureAttemptedKeys.remove(previewCacheKey)
                state.previewCaptureFailedKeys.remove(previewCacheKey)
            } else if pinForSession,
                      !state.previewCaptureInFlightKeys.contains(previewCacheKey),
                      !state.previewCaptureFailedKeys.contains(previewCacheKey) {
                state.previewCaptureAttemptedKeys.remove(previewCacheKey)
            } else {
                return ResolvedPreviewData(
                    preview: (
                        image: nil,
                        titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
                    ),
                    pendingCapture: nil
                )
            }
        }
        state.previewCaptureAttemptedKeys.insert(previewCacheKey)
        state.previewCaptureStatesByKey[previewCacheKey] = .queued(generation: state.previewCaptureGeneration)

        if let previewCaptureOverride {
            guard
                let capture = previewCaptureOverride(
                    windowContext.cgWindowID,
                    ownerPID,
                    windowContext.title,
                    titleBarStyleInferenceEnabled
                )
            else {
                state.previewCaptureFailedKeys.insert(previewCacheKey)
                state.previewCaptureStatesByKey[previewCacheKey] = .failed(
                    reason: .transientSystemError,
                    retryAfterGeneration: state.previewCaptureGeneration &+ 1
                )
                RuntimeLog.debug(.preview, "attempt failed appID=\(appID) windowID=\(window.id)")
                return ResolvedPreviewData(
                    preview: (
                        image: nil,
                        titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
                    ),
                    pendingCapture: nil
                )
            }
            previewSession.applyPreviewCapture(
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
                pendingCapture: nil
            )
        }

        guard !state.previewCaptureInFlightKeys.contains(previewCacheKey) else {
            return ResolvedPreviewData(
                preview: (
                    image: nil,
                    titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
                ),
                pendingCapture: nil
            )
        }
        state.previewCaptureInFlightKeys.insert(previewCacheKey)
        state.previewCaptureStatesByKey[previewCacheKey] = .inFlight(generation: state.previewCaptureGeneration)
        let pendingCapture = PendingPreviewCapture(
            appID: appID,
            bundleIdentifier: appContext.runningApp.bundleIdentifier,
            windowID: window.id,
            ownerPID: ownerPID,
            preferredWindowID: windowContext.cgWindowID,
            preferredTitle: windowContext.title,
            windowFrame: windowContext.frame,
            inferTitleBarStyle: titleBarStyleInferenceEnabled,
            activationHandleID: windowContext.activationHandleID,
            initialCacheKey: previewCacheKey
        )
        return ResolvedPreviewData(
            preview: (
                image: nil,
                titleBarStyle: titleBarStyleInferenceEnabled ? windowContext.inferredTitleBarStyle : nil
            ),
            pendingCapture: pendingCapture
        )
    }
    func shouldRetryPreviewCapture(_ cacheKey: String) -> Bool {
        guard case let .failed(_, retryAfterGeneration?) = state.previewCaptureStatesByKey[cacheKey] else {
            return false
        }
        return retryAfterGeneration <= state.previewCaptureGeneration
    }
    func logPreviewImageReadyOnce(
        source: String,
        appID: String,
        windowID: String,
        key: String,
        cgWindowID: CGWindowID?
    ) {
        guard RuntimeLog.isDebugEnabled(for: "Preview") else { return }
        guard !state.previewImageReadyLoggedKeys.contains(key) else { return }
        state.previewImageReadyLoggedKeys.insert(key)
        RuntimeLog.debug(
            "Preview",
            "image ready source=\(source) appID=\(appID) windowID=\(windowID) cg=\(cgWindowID.map(String.init) ?? "nil")"
        )
    }
}
