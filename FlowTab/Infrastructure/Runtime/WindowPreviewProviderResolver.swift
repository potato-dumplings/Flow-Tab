import AppKit
import ApplicationServices
import Foundation

enum PreviewSource: Equatable {
    case special(appID: String)
    case genericScreenshot
}

enum WindowPreviewFailureReason: String, Equatable {
    case permissionDenied
    case windowNotFound
    case screenCaptureUnavailable
    case transientSystemError
    case specialProviderUnavailable
}

struct WindowPreviewRequest {
    let appID: String
    let bundleIdentifier: String?
    let ownerPID: pid_t
    let windowID: String
    let preferredCGWindowID: CGWindowID?
    let preferredTitle: String?
    let windowFrame: CGRect?
    let inferTitleBarStyle: Bool
    let activationHandleID: String?

    var genericCaptureRequest: RuntimeWindowPreviewProvider.CaptureRequest {
        RuntimeWindowPreviewProvider.CaptureRequest(
            preferredWindowID: preferredCGWindowID,
            ownerPID: ownerPID,
            preferredTitle: preferredTitle,
            inferTitleBarStyle: inferTitleBarStyle
        )
    }
}

struct WindowPreviewResult {
    let image: NSImage?
    let resolvedWindowID: CGWindowID?
    let titleBarStyle: WindowTitleBarStyleGuess?
    let source: PreviewSource?
    let failureReason: WindowPreviewFailureReason?

    static func success(
        image: NSImage,
        resolvedWindowID: CGWindowID?,
        titleBarStyle: WindowTitleBarStyleGuess?,
        source: PreviewSource
    ) -> WindowPreviewResult {
        WindowPreviewResult(
            image: image,
            resolvedWindowID: resolvedWindowID,
            titleBarStyle: titleBarStyle,
            source: source,
            failureReason: nil
        )
    }

    static func failure(_ reason: WindowPreviewFailureReason) -> WindowPreviewResult {
        WindowPreviewResult(
            image: nil,
            resolvedWindowID: nil,
            titleBarStyle: nil,
            source: nil,
            failureReason: reason
        )
    }
}

final class WindowPreviewCaptureCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

protocol SpecialWindowPreviewProviding {
    func supports(_ request: WindowPreviewRequest) -> Bool
    func previews(for requests: [WindowPreviewRequest]) async -> [WindowPreviewResult]
}

extension SpecialWindowPreviewProviding {
    func preview(for request: WindowPreviewRequest) async -> WindowPreviewResult {
        let results = await previews(for: [request])
        return results.first ?? .failure(.transientSystemError)
    }
}

protocol GenericWindowPreviewProviding {
    func previews(
        for requests: [WindowPreviewRequest],
        captureSemaphore: DispatchSemaphore?,
        cancellation: WindowPreviewCaptureCancellation
    ) async -> [WindowPreviewResult]
}

struct GenericWindowScreenshotPreviewProvider: GenericWindowPreviewProviding {
    func previews(
        for requests: [WindowPreviewRequest],
        captureSemaphore: DispatchSemaphore?,
        cancellation: WindowPreviewCaptureCancellation
    ) async -> [WindowPreviewResult] {
        RuntimeWindowPreviewProvider
            .captureWindowPreviewOutcomes(
                requests.map(\.genericCaptureRequest),
                captureSemaphore: captureSemaphore,
                cancellation: cancellation
            )
            .map(Self.windowPreviewResult)
    }

    private static func windowPreviewResult(
        from outcome: RuntimeWindowPreviewProvider.CaptureOutcome
    ) -> WindowPreviewResult {
        guard let result = outcome.result else {
            return .failure(windowPreviewFailureReason(from: outcome.failureReason))
        }
        return .success(
            image: result.image,
            resolvedWindowID: result.resolvedWindowID,
            titleBarStyle: result.titleBarStyle,
            source: .genericScreenshot
        )
    }

    private static func windowPreviewFailureReason(
        from reason: RuntimeWindowPreviewProvider.CaptureFailureReason?
    ) -> WindowPreviewFailureReason {
        switch reason {
        case .permissionDenied:
            return .permissionDenied
        case .windowNotFound:
            return .windowNotFound
        case .screenCaptureUnavailable:
            return .screenCaptureUnavailable
        case .transientSystemError, nil:
            return .transientSystemError
        }
    }
}

struct WindowPreviewProviderResolver {
    let specialProviders: [any SpecialWindowPreviewProviding]
    let genericProvider: any GenericWindowPreviewProviding

    static var `default`: WindowPreviewProviderResolver {
        WindowPreviewProviderResolver(
            specialProviders: [TerminalWindowPreviewProvider()],
            genericProvider: GenericWindowScreenshotPreviewProvider()
        )
    }

    func previewOutcomes(
        for requests: [WindowPreviewRequest],
        captureSemaphore: DispatchSemaphore?,
        cancellation: WindowPreviewCaptureCancellation =
            WindowPreviewCaptureCancellation()
    ) async -> [WindowPreviewResult] {
        guard !requests.isEmpty else { return [] }

        var results = Array(
            repeating: WindowPreviewResult.failure(.transientSystemError),
            count: requests.count
        )
        guard !cancellation.isCancelled else { return results }
        var handledIndexes = Set<Int>()

        for provider in specialProviders {
            guard !cancellation.isCancelled else { return results }
            var providerRequests: [(index: Int, request: WindowPreviewRequest)] = []
            for (index, request) in requests.enumerated() {
                guard !handledIndexes.contains(index), provider.supports(request) else {
                    continue
                }
                providerRequests.append((index: index, request: request))
            }
            guard !providerRequests.isEmpty else { continue }
            providerRequests.forEach { handledIndexes.insert($0.index) }

            let providerResults = await provider.previews(
                for: providerRequests.map(\.request)
            )
            guard !cancellation.isCancelled else { return results }

            for (offset, providerResult) in providerResults.enumerated() {
                guard providerRequests.indices.contains(offset) else { continue }
                results[providerRequests[offset].index] = providerResult
            }
        }
        guard !cancellation.isCancelled else { return results }

        var genericRequests: [(index: Int, request: WindowPreviewRequest)] = []
        for (index, request) in requests.enumerated() where !handledIndexes.contains(index) {
            genericRequests.append((index: index, request: request))
        }
        if !genericRequests.isEmpty {
            let genericResults = await genericProvider.previews(
                for: genericRequests.map(\.request),
                captureSemaphore: captureSemaphore,
                cancellation: cancellation
            )
            guard !cancellation.isCancelled else { return results }
            for (offset, genericResult) in genericResults.enumerated() {
                guard genericRequests.indices.contains(offset) else { continue }
                results[genericRequests[offset].index] = genericResult
            }
        }

        return results
    }
}
