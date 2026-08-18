import AppKit
import Foundation

enum RuntimePermissionTarget: String, CaseIterable, Equatable {
    case accessibility
    case screenCapture
}

enum RuntimePermissionObservationMode: Equatable {
    case untilGranted(watchdogInterval: TimeInterval)
    case whileOwned

    var completesWhenGranted: Bool {
        switch self {
        case .untilGranted:
            return true
        case .whileOwned:
            return false
        }
    }

    var watchdogInterval: TimeInterval? {
        switch self {
        case let .untilGranted(watchdogInterval):
            return watchdogInterval
        case .whileOwned:
            return nil
        }
    }
}

struct RuntimePermissionObservationPolicy: Equatable {
    let fallbackReadbackInterval: TimeInterval
    let permissionRequestWatchdogInterval: TimeInterval

    static let standard = RuntimePermissionObservationPolicy(
        fallbackReadbackInterval: 0.5,
        permissionRequestWatchdogInterval: 20
    )

    init(
        fallbackReadbackInterval: TimeInterval,
        permissionRequestWatchdogInterval: TimeInterval
    ) {
        precondition(
            fallbackReadbackInterval > 0,
            "Permission fallback readback interval must be positive."
        )
        precondition(
            permissionRequestWatchdogInterval > 0,
            "Permission request watchdog interval must be positive."
        )
        self.fallbackReadbackInterval = fallbackReadbackInterval
        self.permissionRequestWatchdogInterval =
            permissionRequestWatchdogInterval
    }

    var permissionRequestMode: RuntimePermissionObservationMode {
        .untilGranted(
            watchdogInterval: permissionRequestWatchdogInterval
        )
    }

    var watchdogDescription: String {
        "\(Int(permissionRequestWatchdogInterval))s"
    }
}

struct RuntimePermissionObservationIdentity: Equatable {
    let bundleIdentifier: String
    let bundlePath: String

    static var current: RuntimePermissionObservationIdentity {
        RuntimePermissionObservationIdentity(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            bundlePath: Bundle.main.bundlePath
        )
    }
}

struct RuntimePermissionObservationEvidence: Equatable {
    enum Source: String, Equatable {
        case initialReadback
        case requestReadback
        case appActivation
        case fallbackReadback
        case watchdogReadback
    }

    let target: RuntimePermissionTarget
    let observationGeneration: UInt64
    let source: Source
    let readbackCount: Int
    let elapsedMs: Double
    let isGranted: Bool
}

struct RuntimePermissionObservationDiagnostic: Equatable {
    enum Action: String, Equatable {
        case watchdogExpired
    }

    let target: RuntimePermissionTarget
    let observationGeneration: UInt64
    let readbackCount: Int
    let elapsedMs: Double
    let finalPermissionGranted: Bool
    let finalEvidenceSource: RuntimePermissionObservationEvidence.Source
    let watchdogDescription: String
    let bundleIdentifier: String
    let bundlePath: String
    let action: Action

    var logMessage: String {
        [
            "permission observation",
            "target=\(target.rawValue)",
            "action=\(action.rawValue)",
            "generation=\(observationGeneration)",
            "readbacks=\(readbackCount)",
            "elapsedMs=\(String(format: "%.3f", elapsedMs))",
            "finalPermissionGranted=\(finalPermissionGranted)",
            "finalEvidence=\(finalEvidenceSource.rawValue)",
            "watchdog=\(watchdogDescription)",
            "bundle=\(bundleIdentifier)",
            "path=\(bundlePath)"
        ].joined(separator: " ")
    }
}

@MainActor
protocol RuntimePermissionObservationClockReading: AnyObject {
    var monotonicMilliseconds: Double { get }
}

@MainActor
final class SystemRuntimePermissionObservationClock:
    RuntimePermissionObservationClockReading
{
    var monotonicMilliseconds: Double {
        ProcessInfo.processInfo.systemUptime * 1_000
    }
}

protocol RuntimePermissionObservationCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol RuntimePermissionObservationScheduling: AnyObject {
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimePermissionObservationCancellable
}

private final class RuntimePermissionObservationScheduledToken:
    RuntimePermissionObservationCancellable
{
    private let task: Task<Void, Never>

    @MainActor
    init(
        interval: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        let nanoseconds = UInt64(
            (max(0, interval) * 1_000_000_000).rounded(.up)
        )
        task = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task.cancel()
    }

    deinit {
        task.cancel()
    }
}

@MainActor
final class RuntimePermissionObservationScheduler:
    RuntimePermissionObservationScheduling
{
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimePermissionObservationCancellable {
        RuntimePermissionObservationScheduledToken(
            interval: interval,
            action: action
        )
    }
}

@MainActor
protocol RuntimePermissionActivationObserving: AnyObject {
    func observeActivations(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimePermissionObservationCancellable
}

private final class RuntimePermissionActivationObservationToken:
    RuntimePermissionObservationCancellable
{
    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?

    init(
        notificationCenter: NotificationCenter,
        observer: NSObjectProtocol
    ) {
        self.notificationCenter = notificationCenter
        self.observer = observer
    }

    func cancel() {
        guard let observer else { return }
        notificationCenter.removeObserver(observer)
        self.observer = nil
    }

    deinit {
        cancel()
    }
}

@MainActor
final class RuntimePermissionActivationObserver:
    RuntimePermissionActivationObserving
{
    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func observeActivations(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimePermissionObservationCancellable {
        let observer = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                action()
            }
        }
        return RuntimePermissionActivationObservationToken(
            notificationCenter: notificationCenter,
            observer: observer
        )
    }
}
