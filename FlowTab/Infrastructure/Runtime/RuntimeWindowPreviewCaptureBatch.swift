import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit

struct WindowPreviewCaptureOperations {
    let windows: any RuntimeShareableWindowsProviding
    let capture: any RuntimeWindowImageCapturing
    let images: any RuntimePreviewImageProcessing

    static var system: Self {
        let images = RuntimePreviewImageProcessor()
        return Self(windows: RuntimeShareableWindowsProvider(),
                    capture: RuntimeWindowImageCapturer(images: images), images: images)
    }
}

protocol WindowPreviewCaptureBatchRunning {
    func capture() -> [RuntimeWindowPreviewProvider.CaptureOutcome]
}

protocol WindowPreviewCaptureBatchCreating {
    func makeBatch(requests: [RuntimeWindowPreviewProvider.CaptureRequest],
                   captureSemaphore: DispatchSemaphore?,
                   cancellation: WindowPreviewCaptureCancellation) -> any WindowPreviewCaptureBatchRunning
}

struct RuntimeWindowPreviewCaptureBatchFactory: WindowPreviewCaptureBatchCreating {
    func makeBatch(requests: [RuntimeWindowPreviewProvider.CaptureRequest],
                   captureSemaphore: DispatchSemaphore?,
                   cancellation: WindowPreviewCaptureCancellation) -> any WindowPreviewCaptureBatchRunning {
        RuntimeWindowPreviewCaptureBatch(requests: requests, captureSemaphore: captureSemaphore,
            cancellation: cancellation, operations: .system)
    }
}

final class RuntimeWindowPreviewCaptureBatch: WindowPreviewCaptureBatchRunning {
    typealias CaptureRequest = RuntimeWindowPreviewProvider.CaptureRequest
    typealias CaptureResult = RuntimeWindowPreviewProvider.CaptureResult
    typealias CaptureOutcome = RuntimeWindowPreviewProvider.CaptureOutcome
    typealias CaptureConcurrencyPolicy = RuntimeWindowPreviewProvider.CaptureConcurrencyPolicy
    typealias PreparedCapture = RuntimeWindowPreviewProvider.PreparedCapture
    typealias ShareableWindowLookup = RuntimeWindowPreviewProvider.ShareableWindowLookup
    private let requests: [CaptureRequest]
    private let captureSemaphore: DispatchSemaphore?
    private let concurrencyPolicy: CaptureConcurrencyPolicy
    private let cancellation: WindowPreviewCaptureCancellation?
    let operations: WindowPreviewCaptureOperations

    init(requests: [CaptureRequest], captureSemaphore: DispatchSemaphore? = nil,
         concurrencyPolicy: CaptureConcurrencyPolicy = .default,
         cancellation: WindowPreviewCaptureCancellation? = nil,
         operations: WindowPreviewCaptureOperations) {
        self.requests = requests
        self.captureSemaphore = captureSemaphore
        self.concurrencyPolicy = concurrencyPolicy
        self.cancellation = cancellation
        self.operations = operations
    }

    func using(operations: WindowPreviewCaptureOperations) -> RuntimeWindowPreviewCaptureBatch {
        RuntimeWindowPreviewCaptureBatch(requests: requests, captureSemaphore: captureSemaphore,
            concurrencyPolicy: concurrencyPolicy, cancellation: cancellation, operations: operations)
    }
    func capture() -> [CaptureOutcome] {
        guard !requests.isEmpty else { return [] }
        guard cancellation?.isCancelled != true else {
            return RuntimeWindowPreviewProvider.cancelledOutcomes(count: requests.count)
        }
        guard ScreenCapturePermissionChecker.hasScreenCapturePermission else {
            if !RuntimeWindowPreviewProvider.hasLoggedScreenCapturePermissionWarning {
                RuntimeLog.warning(
                    .permission,
                    "screen recording permission missing; window preview unavailable reason=\(RuntimeWindowPreviewProvider.ScreenCaptureBridgeFailure.permissionDenied.rawValue)"
                )
                RuntimeWindowPreviewProvider.hasLoggedScreenCapturePermissionWarning = true
            }
            return Array(repeating: .failure(.permissionDenied), count: requests.count)
        }

        let liveWindowsByPID = Dictionary(
            uniqueKeysWithValues: Set(requests.map(\.ownerPID)).map {
                ($0, RuntimeWindowPreviewProvider.collectLiveCGWindows(ownerPID: $0))
            }
        )
        guard cancellation?.isCancelled != true else {
            return RuntimeWindowPreviewProvider.cancelledOutcomes(count: requests.count)
        }
        let preparedCaptures = requests.map { request in
            let candidateIDs = RuntimeWindowPreviewProvider.candidateWindowIDs(
                preferredWindowID: request.preferredWindowID,
                preferredTitle: request.preferredTitle,
                liveWindows: liveWindowsByPID[request.ownerPID] ?? []
            )
            if candidateIDs.isEmpty {
                RuntimeLog.debug(
                    .preview,
                    "no candidate windows pid=\(request.ownerPID) preferredID=\(request.preferredWindowID.map(String.init) ?? "nil") title=\(request.preferredTitle ?? "<empty>")"
                )
            }
            return PreparedCapture(request: request, candidateIDs: candidateIDs)
        }

        guard preparedCaptures.contains(where: { !$0.candidateIDs.isEmpty }) else {
            return Array(repeating: .failure(.windowNotFound), count: preparedCaptures.count)
        }

        let onScreenWindowsOnly = RuntimeWindowPreviewProvider.shareableContentOnScreenOnly(
            preferredWindowIDs: requests.map(\.preferredWindowID)
        )
        let shareableWindowLookup = operations.windows.windows(
            onScreenOnly: onScreenWindowsOnly,
            cancellation: cancellation
        )
        guard cancellation?.isCancelled != true else {
            return RuntimeWindowPreviewProvider.cancelledOutcomes(count: requests.count)
        }

        var outcomes = Array<CaptureOutcome>(
            repeating: .failure(.transientSystemError),
            count: preparedCaptures.count
        )
        let resultsLock = NSLock()
        let indexLock = NSLock()
        var nextIndex = 0
        let workerCount = RuntimeWindowPreviewProvider.captureWorkerCount(
            requestCount: preparedCaptures.count,
            concurrencyPolicy: concurrencyPolicy
        )
        let group = DispatchGroup()

        for _ in 0..<workerCount {
            group.enter()
            Self.previewCaptureWorkerQueue.async { [self] in
                defer { group.leave() }
                while true {
                    guard cancellation?.isCancelled != true else { return }
                    indexLock.lock()
                    let index = nextIndex
                    nextIndex += 1
                    indexLock.unlock()

                    guard index < preparedCaptures.count else { return }
                    let preparedCapture = preparedCaptures[index]
                    let outcome: CaptureOutcome
                    if preparedCapture.candidateIDs.isEmpty {
                        outcome = .failure(.windowNotFound)
                    } else {
                        guard RuntimeWindowPreviewProvider.acquireCapturePermit(
                            captureSemaphore,
                            cancellation: cancellation
                        ) else {
                            return
                        }
                        defer { captureSemaphore?.signal() }
                        outcome = captureWindowPreviewOutcome(
                            preparedCapture,
                            shareableWindowLookup: shareableWindowLookup,
                            cancellation: cancellation
                        )
                    }

                    resultsLock.lock()
                    outcomes[index] = outcome
                    resultsLock.unlock()
                }
            }
        }
        group.wait()
        return outcomes
    }
    private func captureWindowPreviewOutcome(
        _ preparedCapture: PreparedCapture,
        shareableWindowLookup: ShareableWindowLookup,
        cancellation: WindowPreviewCaptureCancellation?
    ) -> CaptureOutcome {
        var sawShareableCandidate = false
        for candidateID in preparedCapture.candidateIDs {
            guard cancellation?.isCancelled != true else {
                return .failure(.transientSystemError)
            }
            guard let shareableWindow = shareableWindowLookup.windowsByID[candidateID] else { continue }
            sawShareableCandidate = true
            guard let cgImage = captureWindow(
                shareableWindow: shareableWindow,
                cancellation: cancellation
            ) else { continue }
            let titleBarStyle = operations.images.titleBarStyle(
                from: cgImage, requested: preparedCapture.request.inferTitleBarStyle
            )
            let image = operations.images.materialize(cgImage)
            RuntimeLog.debug(
                .preview,
                "capture success pid=\(preparedCapture.request.ownerPID) windowID=\(candidateID) candidates=\(preparedCapture.candidateIDs.count) titleBarStyle=\(titleBarStyle?.rawValue ?? "nil")"
            )
            return .success(
                CaptureResult(
                    image: image,
                    resolvedWindowID: candidateID,
                    titleBarStyle: titleBarStyle
                )
            )
        }
        let failureReason = shareableWindowLookup.failureReason
            ?? (sawShareableCandidate ? .transientSystemError : .windowNotFound)
        RuntimeLog.error(
            .preview,
            "capture failed pid=\(preparedCapture.request.ownerPID) preferredID=\(preparedCapture.request.preferredWindowID.map(String.init) ?? "nil") title=\(preparedCapture.request.preferredTitle ?? "<empty>") candidates=\(preparedCapture.candidateIDs.map(String.init).joined(separator: ",")) reason=\(failureReason.rawValue)"
        )
        return .failure(failureReason)
    }
    private func captureWindow(
        shareableWindow: SCWindow,
        cancellation: WindowPreviewCaptureCancellation?
    ) -> CGImage? {
        guard cancellation?.isCancelled != true else { return nil }
        if #available(macOS 14.0, *) {
            return operations.capture.screenshot(
                of: shareableWindow,
                cancellation: cancellation
            )
        }
        return operations.capture.coreGraphicsImage(windowID: shareableWindow.windowID)
    }
    private static let previewCaptureWorkerQueue = DispatchQueue(
        label: "FlowTab.preview.capture.worker", qos: .userInitiated, attributes: .concurrent
    )
}
