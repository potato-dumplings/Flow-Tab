import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit

protocol RuntimeShareableWindowsProviding {
    func windows(onScreenOnly: Bool, cancellation: WindowPreviewCaptureCancellation?)
        -> RuntimeWindowPreviewProvider.ShareableWindowLookup
}

protocol RuntimeWindowImageCapturing {
    @available(macOS 14.0, *)
    func screenshot(of window: SCWindow, cancellation: WindowPreviewCaptureCancellation?) -> CGImage?
    func coreGraphicsImage(windowID: CGWindowID) -> CGImage?
}

struct RuntimeShareableWindowsProvider: RuntimeShareableWindowsProviding {
    func windows(onScreenOnly: Bool, cancellation: WindowPreviewCaptureCancellation?)
        -> RuntimeWindowPreviewProvider.ShareableWindowLookup {
        RuntimeWindowImageCapturer.fetchShareableWindowsByID(
            onScreenWindowsOnly: onScreenOnly, cancellation: cancellation
        )
    }
}

struct RuntimeWindowImageCapturer: RuntimeWindowImageCapturing {
    typealias ScreenCaptureBridgeFailure = RuntimeWindowPreviewProvider.ScreenCaptureBridgeFailure
    typealias ScreenCaptureBridgeState<Value> = RuntimeWindowPreviewProvider.ScreenCaptureBridgeState<Value>
    typealias ShareableWindowLookup = RuntimeWindowPreviewProvider.ShareableWindowLookup
    typealias CancellableWaitResult = RuntimeWindowPreviewProvider.CancellableWaitResult
    static let shareableContentLookupTimeout: TimeInterval = 1.0
    static let screenshotCaptureTimeout: TimeInterval = 1.0
    static let cancellationPollingInterval = RuntimeWindowPreviewProvider.cancellationPollingInterval
    let images: any RuntimePreviewImageProcessing

    @available(macOS 14.0, *)
    func screenshot(of window: SCWindow, cancellation: WindowPreviewCaptureCancellation?) -> CGImage? {
        Self.captureWindowUsingScreenshotManager(
            shareableWindow: window, cancellation: cancellation, images: images
        )
    }

    func coreGraphicsImage(windowID: CGWindowID) -> CGImage? {
        Self.captureWindowUsingCoreGraphics(windowID: windowID, images: images)
    }
    static func fetchShareableWindowsByID(
        onScreenWindowsOnly: Bool,
        cancellation: WindowPreviewCaptureCancellation?
    ) -> ShareableWindowLookup {
        let bridgeState = ScreenCaptureBridgeState<SCShareableContent>()
        let semaphore = DispatchSemaphore(value: 0)
        SCShareableContent.getExcludingDesktopWindows(
            true,
            onScreenWindowsOnly: onScreenWindowsOnly
        ) { content, error in
            if bridgeState.complete(value: content, error: error) == .callbackReturnedAfterTimeout {
                RuntimeLog.debug(
                    .preview,
                    "shareable-content callback returned after timeout reason=\(ScreenCaptureBridgeFailure.callbackReturnedAfterTimeout.rawValue)"
                )
            }
            semaphore.signal()
        }

        let waitResult = waitForCompletion(
            semaphore,
            timeout: shareableContentLookupTimeout,
            cancellation: cancellation
        )
        if waitResult == .cancelled {
            return ShareableWindowLookup(
                windowsByID: [:],
                failureReason: .transientSystemError
            )
        }
        if waitResult == .timedOut, bridgeState.markTimedOutIfUncompleted() {
            RuntimeLog.warning(
                .preview,
                "shareable-content lookup timed out reason=\(ScreenCaptureBridgeFailure.timedOut.rawValue)"
            )
            return ShareableWindowLookup(windowsByID: [:], failureReason: .screenCaptureUnavailable)
        }

        let completion = bridgeState.completed()
        if let capturedError = completion.error {
            RuntimeLog.error(
                .preview,
                "shareable-content lookup failed reason=\(ScreenCaptureBridgeFailure.returnedError.rawValue) error=\(capturedError.localizedDescription)"
            )
            return ShareableWindowLookup(windowsByID: [:], failureReason: .screenCaptureUnavailable)
        }
        guard let shareableContent = completion.value else {
            RuntimeLog.debug(
                .preview,
                "shareable-content lookup returned no content reason=\(ScreenCaptureBridgeFailure.missingContent.rawValue)"
            )
            return ShareableWindowLookup(windowsByID: [:], failureReason: .screenCaptureUnavailable)
        }

        var windowsByID: [CGWindowID: SCWindow] = [:]
        windowsByID.reserveCapacity(shareableContent.windows.count)
        for window in shareableContent.windows {
            windowsByID[window.windowID] = window
        }
        return ShareableWindowLookup(windowsByID: windowsByID, failureReason: nil)
    }
    @available(macOS 14.0, *)
    static func captureWindowUsingScreenshotManager(
        shareableWindow: SCWindow,
        cancellation: WindowPreviewCaptureCancellation?,
        images: any RuntimePreviewImageProcessing
    ) -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: shareableWindow)
        let configuration = SCStreamConfiguration()
        let sourceSize = preferredCaptureSourceSize(
            contentRect: filter.contentRect,
            pointPixelScale: CGFloat(filter.pointPixelScale),
            fallbackFrame: shareableWindow.frame
        )
        let sourceWidth = sourceSize.width
        let sourceHeight = sourceSize.height
        let scaledSize = RuntimePreviewImageProcessor.scaledPreviewSize(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
        let width = scaledSize.width
        let height = scaledSize.height
        configuration.width = width
        configuration.height = height
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        let bridgeState = ScreenCaptureBridgeState<CGImage>()
        let semaphore = DispatchSemaphore(value: 0)
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
            if bridgeState.complete(value: image, error: error) == .callbackReturnedAfterTimeout {
                RuntimeLog.debug(
                    .preview,
                    "screenshot capture callback returned after timeout windowID=\(shareableWindow.windowID) reason=\(ScreenCaptureBridgeFailure.callbackReturnedAfterTimeout.rawValue)"
                )
            }
            semaphore.signal()
        }

        let waitResult = waitForCompletion(
            semaphore,
            timeout: screenshotCaptureTimeout,
            cancellation: cancellation
        )
        if waitResult == .cancelled {
            return nil
        }
        if waitResult == .timedOut, bridgeState.markTimedOutIfUncompleted() {
            RuntimeLog.warning(
                .preview,
                "screenshot capture timed out windowID=\(shareableWindow.windowID) reason=\(ScreenCaptureBridgeFailure.timedOut.rawValue)"
            )
            return nil
        }

        let completion = bridgeState.completed()
        if let capturedError = completion.error {
            RuntimeLog.debug(
                .preview,
                "screenshot capture failed windowID=\(shareableWindow.windowID) reason=\(ScreenCaptureBridgeFailure.returnedError.rawValue) error=\(capturedError.localizedDescription)"
            )
        }
        guard let capturedImage = completion.value else {
            RuntimeLog.debug(
                .preview,
                "screenshot capture returned no image windowID=\(shareableWindow.windowID) reason=\(ScreenCaptureBridgeFailure.missingContent.rawValue)"
            )
            return nil
        }
        return images.scale(images.trim(capturedImage))
    }
    static func captureWindowUsingCoreGraphics(windowID: CGWindowID, images: any RuntimePreviewImageProcessing) -> CGImage? {
        guard
            let image = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.boundsIgnoreFraming, .bestResolution]
            )
        else {
            RuntimeLog.debug(.preview, "legacy capture failed windowID=\(windowID)")
            return nil
        }
        return images.scale(images.trim(image))
    }
    static func preferredCaptureSourceSize(
        contentRect: CGRect?,
        pointPixelScale: CGFloat?,
        fallbackFrame: CGRect
    ) -> CGSize {
        let normalizedFrame = fallbackFrame.standardized
        let resolvedScale = pointPixelScale.map { max(1, $0) } ?? 1

        if let contentRect {
            let normalizedContentRect = contentRect.standardized
            if normalizedContentRect.width > 0, normalizedContentRect.height > 0 {
                return CGSize(
                    width: normalizedContentRect.width * resolvedScale,
                    height: normalizedContentRect.height * resolvedScale
                )
            }
        }

        return CGSize(
            width: max(1, normalizedFrame.width),
            height: max(1, normalizedFrame.height)
        )
    }
    static func waitForCompletion(
        _ semaphore: DispatchSemaphore,
        timeout: TimeInterval,
        cancellation: WindowPreviewCaptureCancellation?
    ) -> CancellableWaitResult {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while cancellation?.isCancelled != true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return .timedOut }
            let interval = min(remaining, cancellationPollingInterval)
            if semaphore.wait(timeout: .now() + interval) == .success {
                return .completed
            }
        }
        return .cancelled
    }
}
