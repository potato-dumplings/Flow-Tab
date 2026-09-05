import AppKit
import Combine
import FlowTabCore

extension SwitcherPreviewSession {
    func completeBatch(
        _ outcomes: [WindowPreviewResult],
        pendingCaptures: [PendingPreviewCapture],
        batchID: UUID,
        cancellation: WindowPreviewCaptureCancellation,
        generation: UInt64,
        startMs: Double,
        completeMs: Double
    ) -> PreviewBatchApplication {
        state.previewCaptureCancellationsByID[batchID] = nil
        guard !cancellation.isCancelled else { return .cancelled }
        for pendingCapture in pendingCaptures {
            guard case .inFlight(let stateGeneration) =
                    state.previewCaptureStatesByKey[
                        pendingCapture.initialCacheKey
                    ],
                  stateGeneration == generation
            else {
                continue
            }
            state.previewCaptureInFlightKeys.remove(
                pendingCapture.initialCacheKey
            )
        }
        guard generation == state.previewCaptureGeneration else {
            for pendingCapture in pendingCaptures
                where state.previewCaptureStatesByKey[
                    pendingCapture.initialCacheKey
                ] == .inFlight(generation: generation)
            {
                state.previewCaptureStatesByKey[pendingCapture.initialCacheKey] = .failed(
                    reason: .cancelledByNewerGeneration,
                    retryAfterGeneration: state.previewCaptureGeneration
                )
            }
            RuntimeLog.debug(.preview, "capture batch stale count=\(pendingCaptures.count)")
            return .stale
        }
        var completedCount = 0
        for (index, pendingCapture) in pendingCaptures.enumerated() {
            let outcome = outcomes.indices.contains(index)
                ? outcomes[index]
                : WindowPreviewResult.failure(.transientSystemError)
            completedCount += 1
            guard let image = outcome.image else {
                let failureReason = SwitcherPreviewSupport.previewFailureReason(from: outcome.failureReason)
                state.previewCaptureFailedKeys.insert(pendingCapture.initialCacheKey)
                state.previewCaptureStatesByKey[pendingCapture.initialCacheKey] = .failed(
                    reason: failureReason,
                    retryAfterGeneration: SwitcherPreviewSupport.previewRetryGeneration(
                        for: failureReason,
                        generation: generation
                    )
                )
                RuntimeLog.debug(
                    "Preview",
                    "capture failed appID=\(pendingCapture.appID) windowID=\(pendingCapture.windowID) reason=\(failureReason.rawValue) durationMs=\(SwitcherPreviewSupport.formatPreviewMilliseconds(completeMs - startMs))"
                )
                continue
            }
            applyPreviewCapture(
                (
                    image: image,
                    resolvedWindowID: outcome.resolvedWindowID,
                    titleBarStyle: outcome.titleBarStyle
                ),
                appID: pendingCapture.appID,
                windowID: pendingCapture.windowID,
                ownerPID: pendingCapture.ownerPID,
                initialCacheKey: pendingCapture.initialCacheKey
            )
            if RuntimeLog.isDebugEnabled(for: "Preview") {
                RuntimeLog.debug(
                    "Preview",
                    "image ready source=\(SwitcherPreviewSupport.previewSourceDescription(outcome.source)) appID=\(pendingCapture.appID) windowID=\(pendingCapture.windowID) resolvedCG=\(outcome.resolvedWindowID.map(String.init) ?? "nil") titleBarStyle=\(outcome.titleBarStyle?.rawValue ?? "nil") durationMs=\(SwitcherPreviewSupport.formatPreviewMilliseconds(completeMs - startMs))"
                )
                state.previewImageReadyLoggedKeys.insert(pendingCapture.initialCacheKey)
            }
        }
        publication.publish(completedCount: completedCount)
        return .applied(completedCount: completedCount)
    }
}
