#if FLOWTAB_TESTING
import AppKit
import ScreenCaptureKit

struct ControlTabPressurePreviewBatchFactory: WindowPreviewCaptureBatchCreating {
    var base: any WindowPreviewCaptureBatchCreating = RuntimeWindowPreviewCaptureBatchFactory()
    var collector: RuntimeWindowPreviewCaptureDiagnosticCollector?
    func makeBatch(
        requests: [RuntimeWindowPreviewProvider.CaptureRequest],
        captureSemaphore: DispatchSemaphore?,
        cancellation: WindowPreviewCaptureCancellation
    ) -> any WindowPreviewCaptureBatchRunning {
        let collector = collector ?? RuntimeWindowPreviewCaptureDiagnosticContext.current
            ?? RuntimeWindowPreviewCaptureDiagnosticCollector()
        let batch = base.makeBatch(requests: requests, captureSemaphore: captureSemaphore, cancellation: cancellation)
        guard let batch = batch as? RuntimeWindowPreviewCaptureBatch else {
            collector.recordUnexecutedPipeline(outcome: .notRequired, workUnits: requests.count)
            return batch
        }
        let images = ControlTabPressurePreviewImages(
            base: batch.operations.images, collector: collector
        )
        let capture: any RuntimeWindowImageCapturing
        if batch.operations.capture is RuntimeWindowImageCapturer {
            capture = RuntimeWindowImageCapturer(images: images)
        } else {
            capture = batch.operations.capture
        }
        return batch.using(
            operations: WindowPreviewCaptureOperations(
                windows: ControlTabPressureShareableWindows(
                    base: batch.operations.windows, collector: collector
                ),
                capture: ControlTabPressureWindowCapture(
                    base: capture, collector: collector
                ),
                images: images
            )
        )
    }
}

struct ControlTabPressurePreviewImages: RuntimePreviewImageProcessing {
    let base: any RuntimePreviewImageProcessing
    let collector: RuntimeWindowPreviewCaptureDiagnosticCollector

    func trim(_ image: CGImage) -> CGImage {
        let token = collector.begin(.transparentTrim, workUnits: 1)
        defer { collector.end(token) }
        return base.trim(image)
    }

    func scale(_ image: CGImage) -> CGImage? {
        let token = collector.begin(.imageScale, workUnits: 1)
        let result = base.scale(image)
        collector.end(token, outcome: result == nil ? .failed : .completed)
        return result
    }

    func materialize(_ image: CGImage) -> NSImage {
        let token = collector.begin(.imageMaterialization, workUnits: 1)
        defer { collector.end(token) }
        return base.materialize(image)
    }

    func titleBarStyle(from image: CGImage, requested: Bool) -> WindowTitleBarStyleGuess? {
        guard requested else {
            let result = base.titleBarStyle(from: image, requested: requested)
            collector.recordUnexecuted(.titleBarInference, outcome: .notRequested, workUnits: 1)
            return result
        }
        let token = collector.begin(.titleBarInference, workUnits: 1)
        defer { collector.end(token) }
        return base.titleBarStyle(from: image, requested: requested)
    }
}

struct ControlTabPressureShareableWindows: RuntimeShareableWindowsProviding {
    let base: any RuntimeShareableWindowsProviding
    let collector: RuntimeWindowPreviewCaptureDiagnosticCollector

    func windows(onScreenOnly: Bool, cancellation: WindowPreviewCaptureCancellation?)
        -> RuntimeWindowPreviewProvider.ShareableWindowLookup {
        let token = collector.begin(.shareableContentLookup, workUnits: 1)
        let result = base.windows(onScreenOnly: onScreenOnly, cancellation: cancellation)
        collector.end(token, outcome: cancellation?.isCancelled == true
            ? .cancelled : result.failureReason == nil ? .completed : .failed)
        return result
    }
}

struct ControlTabPressureWindowCapture: RuntimeWindowImageCapturing {
    let base: any RuntimeWindowImageCapturing
    let collector: RuntimeWindowPreviewCaptureDiagnosticCollector

    @available(macOS 14.0, *)
    func screenshot(of window: SCWindow, cancellation: WindowPreviewCaptureCancellation?) -> CGImage? {
        collector.recordUnexecuted(.coreGraphicsCapture, outcome: .notRequired, workUnits: 1)
        let token = collector.begin(.screenshotManagerCapture, workUnits: 1)
        let result = base.screenshot(of: window, cancellation: cancellation)
        collector.end(token, outcome: cancellation?.isCancelled == true
            ? .cancelled : result == nil ? .failed : .completed)
        return result
    }

    func coreGraphicsImage(windowID: CGWindowID) -> CGImage? {
        collector.recordUnexecuted(.screenshotManagerCapture, outcome: .notRequired, workUnits: 1)
        let token = collector.begin(.coreGraphicsCapture, workUnits: 1)
        let result = base.coreGraphicsImage(windowID: windowID)
        collector.end(token, outcome: result == nil ? .failed : .completed)
        return result
    }
}
#endif
