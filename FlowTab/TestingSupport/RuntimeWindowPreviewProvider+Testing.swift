#if FLOWTAB_TESTING
import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit

extension RuntimeWindowPreviewProvider {
    private static var imagesForTesting: any RuntimePreviewImageProcessing {
        guard let collector = RuntimeWindowPreviewCaptureDiagnosticContext.current else {
            return RuntimePreviewImageProcessor()
        }
        return ControlTabPressurePreviewImages(base: RuntimePreviewImageProcessor(), collector: collector)
    }
    static func guessTitleBarStyleForTesting(from image: CGImage) -> WindowTitleBarStyleGuess? {
        RuntimePreviewImageProcessor.estimateTitleBarStyle(from: image)
    }

    static func candidateWindowIDsForTesting(
        preferredWindowID: CGWindowID?,
        ownerPID: pid_t,
        preferredTitle: String?
    ) -> [CGWindowID] {
        candidateWindowIDs(
            preferredWindowID: preferredWindowID,
            ownerPID: ownerPID,
            preferredTitle: preferredTitle
        )
    }

    static func candidateWindowIDsForTesting(
        preferredWindowID: CGWindowID?,
        preferredTitle: String?,
        liveWindows: [LiveWindowCandidateForTesting]
    ) -> [CGWindowID] {
        candidateWindowIDs(
            preferredWindowID: preferredWindowID,
            preferredTitle: preferredTitle,
            liveWindows: liveWindows.map { LiveCGWindowEntry(id: $0.id, title: $0.title) }
        )
    }

    static func scaledPreviewSizeForTesting(
        sourceWidth: CGFloat,
        sourceHeight: CGFloat
    ) -> (width: Int, height: Int) {
        RuntimePreviewImageProcessor.scaledPreviewSize(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
    }

    static func scaledPreviewImageIfNeededForTesting(_ image: CGImage) -> CGImage? {
        imagesForTesting.scale(image)
    }

    static func preferredCaptureSourceSizeForTesting(
        contentRect: CGRect?,
        pointPixelScale: CGFloat?,
        fallbackFrame: CGRect
    ) -> CGSize {
        RuntimeWindowImageCapturer.preferredCaptureSourceSize(
            contentRect: contentRect,
            pointPixelScale: pointPixelScale,
            fallbackFrame: fallbackFrame
        )
    }

    static func trimmedTransparentPaddingIfNeededForTesting(_ image: CGImage) -> CGImage {
        imagesForTesting.trim(image)
    }

    static func shareableContentOnScreenOnlyForTesting(
        preferredWindowID: CGWindowID?
    ) -> Bool {
        shareableContentOnScreenOnly(preferredWindowID: preferredWindowID)
    }

    static func shareableContentOnScreenOnlyForTesting(
        preferredWindowIDs: [CGWindowID?]
    ) -> Bool {
        shareableContentOnScreenOnly(preferredWindowIDs: preferredWindowIDs)
    }

    static func captureConcurrencyPolicyForTesting() -> CaptureConcurrencyPolicy {
        .default
    }

    static func captureWorkerCountForTesting(
        requestCount: Int,
        concurrencyPolicy: CaptureConcurrencyPolicy = .default
    ) -> Int {
        captureWorkerCount(
            requestCount: requestCount,
            concurrencyPolicy: concurrencyPolicy
        )
    }

    static func screenCaptureBridgeLateCallbackFailureForTesting() -> ScreenCaptureBridgeFailure? {
        let state = ScreenCaptureBridgeState<Int>()
        _ = state.markTimedOutIfUncompleted()
        return state.complete(value: 1, error: nil)
    }

    static func screenCaptureBridgeUsesCompletedValueBeforeTimeoutMarkForTesting() -> Bool {
        let state = ScreenCaptureBridgeState<Int>()
        _ = state.complete(value: 42, error: nil)
        let didMarkTimedOut = state.markTimedOutIfUncompleted()
        return !didMarkTimedOut && state.completed().value == 42
    }
}
#endif
