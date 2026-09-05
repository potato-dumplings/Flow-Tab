import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit

enum RuntimeWindowPreviewProvider {
    enum ScreenCaptureBridgeFailure: String, Equatable {
        case permissionDenied
        case timedOut
        case callbackReturnedAfterTimeout
        case returnedError
        case missingContent
    }

    enum CaptureFailureReason: String, Equatable {
        case permissionDenied
        case windowNotFound
        case screenCaptureUnavailable
        case transientSystemError
    }

    struct CaptureRequest {
        let preferredWindowID: CGWindowID?
        let ownerPID: pid_t
        let preferredTitle: String?
        let inferTitleBarStyle: Bool
    }

    struct CaptureResult {
        let image: NSImage
        let resolvedWindowID: CGWindowID
        let titleBarStyle: WindowTitleBarStyleGuess?
    }

    struct CaptureOutcome {
        let result: CaptureResult?
        let failureReason: CaptureFailureReason?

        static func success(_ result: CaptureResult) -> CaptureOutcome {
            CaptureOutcome(result: result, failureReason: nil)
        }

        static func failure(_ reason: CaptureFailureReason) -> CaptureOutcome {
            CaptureOutcome(result: nil, failureReason: reason)
        }
    }

    struct CaptureConcurrencyPolicy: Equatable {
        let maxConcurrentCaptures: Int

        static let `default` = CaptureConcurrencyPolicy(maxConcurrentCaptures: 4)
    }

    struct LiveCGWindowEntry {
        let id: CGWindowID
        let title: String?
    }

    struct LiveWindowCandidateForTesting {
        let id: CGWindowID
        let title: String?
    }

    struct PreparedCapture {
        let request: CaptureRequest
        let candidateIDs: [CGWindowID]
    }

    struct ShareableWindowLookup {
        let windowsByID: [CGWindowID: SCWindow]
        let failureReason: CaptureFailureReason?
    }

    final class ScreenCaptureBridgeState<Value> {
        private let lock = NSLock()
        private var didTimeOut = false
        private var completion: (value: Value?, error: Error?)?

        func complete(value: Value?, error: Error?) -> ScreenCaptureBridgeFailure? {
            lock.lock()
            defer { lock.unlock() }

            if didTimeOut {
                return .callbackReturnedAfterTimeout
            }
            completion = (value, error)
            return nil
        }

        func markTimedOutIfUncompleted() -> Bool {
            lock.lock()
            defer { lock.unlock() }

            if completion != nil {
                return false
            }
            didTimeOut = true
            return true
        }

        func completed() -> (value: Value?, error: Error?) {
            lock.lock()
            defer { lock.unlock() }

            return completion ?? (nil, nil)
        }
    }

    enum CancellableWaitResult: Equatable {
        case completed
        case timedOut
        case cancelled
    }

    static var hasLoggedScreenCapturePermissionWarning = false
    static let cancellationPollingInterval: TimeInterval = 0.025
    static func captureWindowPreview(
        preferredWindowID: CGWindowID?,
        ownerPID: pid_t,
        preferredTitle: String?,
        inferTitleBarStyle: Bool
    ) -> (image: NSImage, resolvedWindowID: CGWindowID, titleBarStyle: WindowTitleBarStyleGuess?)? {
        let request = CaptureRequest(
            preferredWindowID: preferredWindowID,
            ownerPID: ownerPID,
            preferredTitle: preferredTitle,
            inferTitleBarStyle: inferTitleBarStyle
        )
        guard let result = captureWindowPreviews([request]).first ?? nil else {
            return nil
        }
        return (
            image: result.image,
            resolvedWindowID: result.resolvedWindowID,
            titleBarStyle: result.titleBarStyle
        )
    }

    static func captureWindowPreviews(
        _ requests: [CaptureRequest],
        captureSemaphore: DispatchSemaphore? = nil,
        concurrencyPolicy: CaptureConcurrencyPolicy = .default
    ) -> [CaptureResult?] {
        captureWindowPreviewOutcomes(
            requests,
            captureSemaphore: captureSemaphore,
            concurrencyPolicy: concurrencyPolicy
        ).map(\.result)
    }

    static func captureWindowPreviewOutcomes(
        _ requests: [CaptureRequest],
        captureSemaphore: DispatchSemaphore? = nil,
        concurrencyPolicy: CaptureConcurrencyPolicy = .default,
        cancellation: WindowPreviewCaptureCancellation? = nil
    ) -> [CaptureOutcome] {
        RuntimeWindowPreviewCaptureBatch(
            requests: requests,
            captureSemaphore: captureSemaphore,
            concurrencyPolicy: concurrencyPolicy,
            cancellation: cancellation,
            operations: .system
        ).capture()
    }
    static func candidateWindowIDs(
        preferredWindowID: CGWindowID?,
        ownerPID: pid_t,
        preferredTitle: String?
    ) -> [CGWindowID] {
        let liveWindows = collectLiveCGWindows(ownerPID: ownerPID)
        return candidateWindowIDs(
            preferredWindowID: preferredWindowID,
            preferredTitle: preferredTitle,
            liveWindows: liveWindows
        )
    }

    static func candidateWindowIDs(
        preferredWindowID: CGWindowID?,
        preferredTitle: String?,
        liveWindows: [LiveCGWindowEntry]
    ) -> [CGWindowID] {
        if let preferredWindowID {
            return [preferredWindowID]
        }

        let trimmedTitle = preferredTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedTitle, !trimmedTitle.isEmpty {
            let exactMatches = liveWindows.compactMap { window -> CGWindowID? in
                guard let title = window.title else { return nil }
                return title == trimmedTitle ? window.id : nil
            }
            if exactMatches.count == 1 {
                return exactMatches
            }
            if !exactMatches.isEmpty {
                return []
            }

            let caseInsensitiveMatches = liveWindows.compactMap { window -> CGWindowID? in
                guard let title = window.title else { return nil }
                return title.caseInsensitiveCompare(trimmedTitle) == .orderedSame ? window.id : nil
            }
            if caseInsensitiveMatches.count == 1 {
                return caseInsensitiveMatches
            }
            if !caseInsensitiveMatches.isEmpty {
                return []
            }
        }

        // Showing no preview is safer than binding another window's image to this slot.
        if let onlyWindow = liveWindows.only {
            return [onlyWindow.id]
        }
        return []
    }

    static func collectLiveCGWindows(ownerPID: pid_t) -> [LiveCGWindowEntry] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard
            let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }

        var windows: [LiveCGWindowEntry] = []
        windows.reserveCapacity(rawList.count)
        for item in rawList {
            guard let pid = item[kCGWindowOwnerPID as String] as? pid_t, pid == ownerPID else { continue }
            guard let layer = item[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let windowNumber = item[kCGWindowNumber as String] as? NSNumber else { continue }
            let title = (item[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            windows.append(
                LiveCGWindowEntry(
                    id: CGWindowID(windowNumber.uint32Value),
                    title: title
                )
            )
        }
        return windows
    }

    static func shareableContentOnScreenOnly(preferredWindowID: CGWindowID?) -> Bool {
        preferredWindowID == nil
    }

    static func shareableContentOnScreenOnly(
        preferredWindowIDs: [CGWindowID?]
    ) -> Bool {
        preferredWindowIDs.allSatisfy {
            shareableContentOnScreenOnly(preferredWindowID: $0)
        }
    }

    static func captureWorkerCount(
        requestCount: Int,
        concurrencyPolicy: CaptureConcurrencyPolicy
    ) -> Int {
        min(requestCount, max(1, concurrencyPolicy.maxConcurrentCaptures))
    }
    static func acquireCapturePermit(
        _ semaphore: DispatchSemaphore?,
        cancellation: WindowPreviewCaptureCancellation?
    ) -> Bool {
        guard let semaphore else {
            return cancellation?.isCancelled != true
        }
        while cancellation?.isCancelled != true {
            if semaphore.wait(
                timeout: .now() + cancellationPollingInterval
            ) == .success {
                if cancellation?.isCancelled == true {
                    semaphore.signal()
                    return false
                }
                return true
            }
        }
        return false
    }
    static func cancelledOutcomes(count: Int) -> [CaptureOutcome] {
        Array(repeating: .failure(.transientSystemError), count: count)
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
