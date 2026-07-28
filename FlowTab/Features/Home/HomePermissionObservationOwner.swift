import Combine
import Foundation

@MainActor
final class HomePermissionObservationOwner: ObservableObject {
    static let fallbackReadbackInterval: TimeInterval = 1

    @Published private(set) var accessibilityTrusted: Bool
    @Published private(set) var screenCaptureTrusted: Bool

    private static let observationPolicy = RuntimePermissionObservationPolicy(
        fallbackReadbackInterval: fallbackReadbackInterval,
        permissionRequestWatchdogInterval:
            RuntimePermissionObservationPolicy.standard
                .permissionRequestWatchdogInterval
    )

    private let coordinator: RuntimePermissionObservationCoordinator
    private let readAccessibilityPermission: @MainActor () -> Bool
    private let readScreenCapturePermission: @MainActor () -> Bool
    private var onPermissionChanged:
        (@MainActor (RuntimePermissionObservationEvidence) -> Void)?

    init(
        accessibilityTrusted: Bool,
        screenCaptureTrusted: Bool,
        coordinator: RuntimePermissionObservationCoordinator? = nil,
        readAccessibilityPermission:
            @escaping @MainActor () -> Bool = {
                AccessibilityPermissionChecker.isTrusted()
            },
        readScreenCapturePermission:
            @escaping @MainActor () -> Bool = {
                ScreenCapturePermissionChecker.hasScreenCapturePermission
            }
    ) {
        self.accessibilityTrusted = accessibilityTrusted
        self.screenCaptureTrusted = screenCaptureTrusted
        self.coordinator = coordinator
            ?? RuntimePermissionObservationCoordinator(
                policy: Self.observationPolicy
            )
        self.readAccessibilityPermission = readAccessibilityPermission
        self.readScreenCapturePermission = readScreenCapturePermission
    }

    func start(
        onPermissionChanged:
            @escaping @MainActor (RuntimePermissionObservationEvidence) -> Void
    ) {
        self.onPermissionChanged = onPermissionChanged
        startIfNeeded(
            target: .accessibility,
            readPermission: readAccessibilityPermission
        )
        startIfNeeded(
            target: .screenCapture,
            readPermission: readScreenCapturePermission
        )
    }

    func stop() {
        onPermissionChanged = nil
        coordinator.cancelAll()
    }

    func isObserving(_ target: RuntimePermissionTarget) -> Bool {
        coordinator.isObserving(target)
    }

    private func startIfNeeded(
        target: RuntimePermissionTarget,
        readPermission: @escaping @MainActor () -> Bool
    ) {
        guard !coordinator.isObserving(target) else { return }
        coordinator.start(
            target: target,
            mode: .whileOwned,
            readPermission: readPermission,
            onEvidence: { [weak self] evidence in
                self?.apply(evidence)
            },
            onWatchdog: { diagnostic in
                RuntimeLog.warning(.permission, diagnostic.logMessage)
            }
        )
    }

    private func apply(
        _ evidence: RuntimePermissionObservationEvidence
    ) {
        let previousValue: Bool
        switch evidence.target {
        case .accessibility:
            previousValue = accessibilityTrusted
            guard previousValue != evidence.isGranted else { return }
            accessibilityTrusted = evidence.isGranted
        case .screenCapture:
            previousValue = screenCaptureTrusted
            guard previousValue != evidence.isGranted else { return }
            screenCaptureTrusted = evidence.isGranted
        }

        RuntimeLog.info(
            .permission,
            [
                "home permission observed",
                "target=\(evidence.target.rawValue)",
                "source=\(evidence.source.rawValue)",
                "granted=\(evidence.isGranted)",
                "generation=\(evidence.observationGeneration)",
                "readbacks=\(evidence.readbackCount)",
                "elapsedMs=\(String(format: "%.3f", evidence.elapsedMs))"
            ].joined(separator: " ")
        )
        onPermissionChanged?(evidence)
    }
}
