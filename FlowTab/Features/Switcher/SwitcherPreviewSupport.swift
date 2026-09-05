import AppKit
import Combine
import FlowTabCore

enum SwitcherPreviewSupport {
    static func previewCacheKey(
        appID: String,
        ownerPID: pid_t,
        windowContext: RuntimeWindowContext
    ) -> String {
        [
            appID,
            "pid:\(ownerPID)",
            "cg:\(windowContext.cgWindowID.map(String.init) ?? "nil")",
            "window:\(windowContext.id)"
        ].joined(separator: "#")
    }
    static func previewFailureReason(
        from providerReason: WindowPreviewFailureReason?
    ) -> PreviewCaptureFailureReason {
        switch providerReason {
        case .permissionDenied:
            return .permissionDenied
        case .windowNotFound:
            return .windowNotFound
        case .screenCaptureUnavailable:
            return .screenCaptureUnavailable
        case .specialProviderUnavailable:
            return .specialProviderUnavailable
        case .transientSystemError, nil:
            return .transientSystemError
        }
    }
    static func windowPreviewResult(
        from capture: RuntimeWindowPreviewProvider.CaptureResult
    ) -> WindowPreviewResult {
        .success(
            image: capture.image,
            resolvedWindowID: capture.resolvedWindowID,
            titleBarStyle: capture.titleBarStyle,
            source: .genericScreenshot
        )
    }
    static func windowPreviewResult(
        from outcome: RuntimeWindowPreviewProvider.CaptureOutcome
    ) -> WindowPreviewResult {
        guard let result = outcome.result else {
            return .failure(windowPreviewFailureReason(from: outcome.failureReason))
        }
        return windowPreviewResult(from: result)
    }
    static func windowPreviewFailureReason(
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
    static func previewTaskPriority(for qos: DispatchQoS.QoSClass) -> TaskPriority {
        switch qos {
        case .background:
            return .background
        case .utility:
            return .utility
        case .userInteractive:
            return .high
        default:
            return .userInitiated
        }
    }
    static func previewSourceDescription(_ source: PreviewSource?) -> String {
        switch source {
        case nil:
            return "unknown"
        case .genericScreenshot:
            return "capture"
        case .special(let appID):
            return "special:\(appID)"
        }
    }
    static func previewRetryGeneration(
        for reason: PreviewCaptureFailureReason,
        generation: UInt64
    ) -> UInt64? {
        switch reason {
        case .permissionDenied, .bindingActionDisallowed:
            return nil
        case .windowNotFound, .screenCaptureUnavailable, .transientSystemError, .specialProviderUnavailable:
            return generation &+ 1
        case .cancelledByNewerGeneration:
            return generation
        }
    }
    static func previewAllowedActionsDescription(
        _ allowedActions: Set<WindowBindingAction>
    ) -> String {
        allowedActions
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
    }
    static func formatPreviewMilliseconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
    static func frozenPreviewWindows(
        for appID: String,
        fallbackApp app: AppSwitchCandidate,
        snapshots: [String: [WindowCandidate]]
    ) -> [WindowCandidate] {
        snapshots[appID] ?? app.windows
    }
    static func selectedPreviewWindowIndex(
        appID: String,
        session: SwitcherSession,
        previewWindows: [WindowCandidate]
    ) -> Int? {
        guard !previewWindows.isEmpty else { return nil }
        if let selectedWindowID = session.selectedWindow?.id,
           let index = previewWindows.firstIndex(where: { $0.id == selectedWindowID }) {
            return index
        }
        return session.selectedWindowIndexByAppID[appID]
            .map { min(max(0, $0), max(previewWindows.count - 1, 0)) }
    }
    static func indexedPreviewWindows(
        in windows: [WindowCandidate],
        visibleRange: Range<Int>?
    ) -> [(index: Int, window: WindowCandidate)] {
        guard let visibleRange else {
            return windows.enumerated().map { (index: $0.offset, window: $0.element) }
        }
        let lowerBound = min(max(0, visibleRange.lowerBound), windows.count)
        let upperBound = min(max(lowerBound, visibleRange.upperBound), windows.count)
        guard lowerBound < upperBound else { return [] }
        return windows[lowerBound..<upperBound].enumerated().map {
            (index: lowerBound + $0.offset, window: $0.element)
        }
    }
}
