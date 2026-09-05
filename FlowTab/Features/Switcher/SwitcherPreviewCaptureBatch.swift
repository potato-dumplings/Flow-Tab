import AppKit

struct SwitcherPreviewBatchRequest {
    let id: UUID
    let captures: [PendingPreviewCapture]
    let generation: UInt64
    let cancellation: WindowPreviewCaptureCancellation
    let captureSemaphore: DispatchSemaphore
}

typealias SwitcherPreviewBatchCapture = ([RuntimeWindowPreviewProvider.CaptureRequest])
    -> [RuntimeWindowPreviewProvider.CaptureResult?]
typealias SwitcherPreviewBatchCaptureOutcomes = ([RuntimeWindowPreviewProvider.CaptureRequest])
    -> [RuntimeWindowPreviewProvider.CaptureOutcome]

protocol SwitcherPreviewBatchRunning {
    func capture() async -> [WindowPreviewResult]
}

@MainActor
protocol SwitcherPreviewBatchCreating {
    func makeBatch(request: SwitcherPreviewBatchRequest,
                   resolver: WindowPreviewProviderResolver,
                   capture: SwitcherPreviewBatchCapture?,
                   captureOutcomes: SwitcherPreviewBatchCaptureOutcomes?) -> any SwitcherPreviewBatchRunning
}

struct SwitcherPreviewBatchFactory: SwitcherPreviewBatchCreating {
    func makeBatch(request: SwitcherPreviewBatchRequest,
                   resolver: WindowPreviewProviderResolver,
                   capture: SwitcherPreviewBatchCapture?,
                   captureOutcomes: SwitcherPreviewBatchCaptureOutcomes?) -> any SwitcherPreviewBatchRunning {
        SwitcherPreviewCaptureBatch(request: request, resolver: resolver,
            batchCapture: capture, batchCaptureOutcomes: captureOutcomes)
    }
}

struct SwitcherPreviewCaptureBatch: SwitcherPreviewBatchRunning {
    let request: SwitcherPreviewBatchRequest
    let resolver: WindowPreviewProviderResolver
    let batchCapture: SwitcherPreviewBatchCapture?
    let batchCaptureOutcomes: SwitcherPreviewBatchCaptureOutcomes?

    func capture() async -> [WindowPreviewResult] {
        let requests = request.captures.map(\.providerRequest)
        if request.cancellation.isCancelled {
            return Array(repeating: .failure(.transientSystemError), count: requests.count)
        }
        if let batchCaptureOutcomes {
            return batchCaptureOutcomes(requests.map(\.genericCaptureRequest))
                .map(SwitcherPreviewSupport.windowPreviewResult)
        }
        if let batchCapture {
            return batchCapture(requests.map(\.genericCaptureRequest)).map { capture in
                capture.map(SwitcherPreviewSupport.windowPreviewResult) ?? .failure(.transientSystemError)
            }
        }
        return await resolver.previewOutcomes(for: requests,
            captureSemaphore: request.captureSemaphore, cancellation: request.cancellation)
    }
}
