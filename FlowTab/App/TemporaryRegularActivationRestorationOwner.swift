import AppKit
import Foundation

struct TemporaryRegularActivationRestorationPolicy: Equatable {
    let fallbackReadbackInterval: TimeInterval
    let watchdogInterval: TimeInterval

    static let standard = TemporaryRegularActivationRestorationPolicy(
        fallbackReadbackInterval: 0.02,
        watchdogInterval: 5
    )

    init(
        fallbackReadbackInterval: TimeInterval,
        watchdogInterval: TimeInterval
    ) {
        precondition(
            fallbackReadbackInterval > 0,
            "Activation restoration fallback interval must be positive."
        )
        precondition(
            watchdogInterval > 0,
            "Activation restoration watchdog interval must be positive."
        )
        self.fallbackReadbackInterval = fallbackReadbackInterval
        self.watchdogInterval = watchdogInterval
    }
}

enum TemporaryRegularActivationEvidenceSource: String, Equatable {
    case initialReadback
    case presentationReadback
    case applicationDidBecomeActive
    case applicationDidUnhide
    case windowDidBecomeKey
    case windowDidBecomeMain
    case windowDidDeminiaturize
    case windowDidMiniaturize
    case windowOcclusionChanged
    case windowWillClose
    case fallbackReadback
    case fallbackPresentationReadback
    case watchdogReadback
}

struct TemporaryRegularActivationEvidence: Equatable {
    let source: TemporaryRegularActivationEvidenceSource
    let elapsedMilliseconds: Double
    let applicationIsActive: Bool
    let windowIsVisible: Bool
    let windowIsMiniaturized: Bool
    let activationPolicy: NSApplication.ActivationPolicy

    var isStable: Bool {
        applicationIsActive && windowIsVisible
    }

    var logFields: String {
        [
            "lastEvidence=\(source.rawValue)",
            "elapsedMs=\(String(format: "%.3f", elapsedMilliseconds))",
            "appActive=\(applicationIsActive)",
            "windowVisible=\(windowIsVisible)",
            "windowMiniaturized=\(windowIsMiniaturized)",
            "activationPolicy=\(activationPolicy.rawValue)"
        ].joined(separator: " ")
    }
}

enum TemporaryRegularActivationRestorationOutcome: Equatable {
    case stable(TemporaryRegularActivationEvidence)
    case windowUnavailable(TemporaryRegularActivationEvidence)
    case watchdogExpired(TemporaryRegularActivationEvidence)
    case activationPolicyChanged(TemporaryRegularActivationEvidence)
}

protocol TemporaryRegularActivationCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol TemporaryRegularActivationScheduling: AnyObject {
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any TemporaryRegularActivationCancellable
}

private final class TemporaryRegularActivationScheduledToken:
    TemporaryRegularActivationCancellable
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
final class TemporaryRegularActivationScheduler:
    TemporaryRegularActivationScheduling
{
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any TemporaryRegularActivationCancellable {
        TemporaryRegularActivationScheduledToken(
            interval: interval,
            action: action
        )
    }
}

@MainActor
protocol TemporaryRegularActivationClockReading: AnyObject {
    var monotonicMilliseconds: Double { get }
}

@MainActor
final class SystemTemporaryRegularActivationClock:
    TemporaryRegularActivationClockReading
{
    var monotonicMilliseconds: Double {
        ProcessInfo.processInfo.systemUptime * 1_000
    }
}

@MainActor
protocol AppActivationEvidenceObserving: AnyObject {
    var flowTabIsActive: Bool { get }

    func observeFlowTabActivationEvidence(
        _ action: @escaping @MainActor @Sendable (
            TemporaryRegularActivationEvidenceSource
        ) -> Void
    ) -> any TemporaryRegularActivationCancellable
}

@MainActor
protocol AppWindowPresentationEvidenceObserving: AnyObject {
    func observeFlowTabWindowPresentationEvidence(
        _ action: @escaping @MainActor @Sendable (
            TemporaryRegularActivationEvidenceSource
        ) -> Void
    ) -> any TemporaryRegularActivationCancellable
}

private final class TemporaryRegularActivationNotificationToken:
    TemporaryRegularActivationCancellable
{
    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol]

    init(
        notificationCenter: NotificationCenter,
        observers: [NSObjectProtocol]
    ) {
        self.notificationCenter = notificationCenter
        self.observers = observers
    }

    func cancel() {
        let currentObservers = observers
        observers.removeAll()
        for observer in currentObservers {
            notificationCenter.removeObserver(observer)
        }
    }

    deinit {
        cancel()
    }
}

extension NSApplication: AppActivationEvidenceObserving {
    var flowTabIsActive: Bool {
        isActive
    }

    func observeFlowTabActivationEvidence(
        _ action: @escaping @MainActor @Sendable (
            TemporaryRegularActivationEvidenceSource
        ) -> Void
    ) -> any TemporaryRegularActivationCancellable {
        let notificationCenter = NotificationCenter.default
        let sources: [
            (Notification.Name, TemporaryRegularActivationEvidenceSource)
        ] = [
            (
                NSApplication.didBecomeActiveNotification,
                .applicationDidBecomeActive
            ),
            (NSApplication.didUnhideNotification, .applicationDidUnhide)
        ]
        let observers = sources.map { name, source in
            notificationCenter.addObserver(
                forName: name,
                object: self,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    action(source)
                }
            }
        }
        return TemporaryRegularActivationNotificationToken(
            notificationCenter: notificationCenter,
            observers: observers
        )
    }
}

extension NSWindow: AppWindowPresentationEvidenceObserving {
    func observeFlowTabWindowPresentationEvidence(
        _ action: @escaping @MainActor @Sendable (
            TemporaryRegularActivationEvidenceSource
        ) -> Void
    ) -> any TemporaryRegularActivationCancellable {
        let notificationCenter = NotificationCenter.default
        let sources: [
            (Notification.Name, TemporaryRegularActivationEvidenceSource)
        ] = [
            (NSWindow.didBecomeKeyNotification, .windowDidBecomeKey),
            (NSWindow.didBecomeMainNotification, .windowDidBecomeMain),
            (
                NSWindow.didDeminiaturizeNotification,
                .windowDidDeminiaturize
            ),
            (NSWindow.didMiniaturizeNotification, .windowDidMiniaturize),
            (
                NSWindow.didChangeOcclusionStateNotification,
                .windowOcclusionChanged
            ),
            (NSWindow.willCloseNotification, .windowWillClose)
        ]
        let observers = sources.map { name, source in
            notificationCenter.addObserver(
                forName: name,
                object: self,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    action(source)
                }
            }
        }
        return TemporaryRegularActivationNotificationToken(
            notificationCenter: notificationCenter,
            observers: observers
        )
    }
}

@MainActor
final class TemporaryRegularActivationRestorationOwner {
    let generation: UInt64

    private let application: any AppWindowOpeningApplication
    private let window: any AppWindowOpeningWindow
    private let activationPolicyApplication: any AppActivationPolicyApplying
    private let scheduler: any TemporaryRegularActivationScheduling
    private let clock: any TemporaryRegularActivationClockReading
    private let policy: TemporaryRegularActivationRestorationPolicy

    private var observationTokens: [
        any TemporaryRegularActivationCancellable
    ] = []
    private var fallbackToken:
        (any TemporaryRegularActivationCancellable)?
    private var watchdogToken:
        (any TemporaryRegularActivationCancellable)?
    private var observationGeneration: UInt64 = 0
    private var startedAtMilliseconds: Double = 0
    private var hasObservedVisibleWindow = false
    private var presentationRequest: (@MainActor () -> Void)?
    private var outcomeHandler:
        (@MainActor (TemporaryRegularActivationRestorationOutcome) -> Void)?

    private(set) var lastEvidence: TemporaryRegularActivationEvidence?
    private(set) var isObserving = false

    init(
        generation: UInt64,
        application: any AppWindowOpeningApplication,
        window: any AppWindowOpeningWindow,
        activationPolicyApplication: any AppActivationPolicyApplying,
        scheduler: (any TemporaryRegularActivationScheduling)? = nil,
        clock: (any TemporaryRegularActivationClockReading)? = nil,
        policy: TemporaryRegularActivationRestorationPolicy = .standard
    ) {
        self.generation = generation
        self.application = application
        self.window = window
        self.activationPolicyApplication = activationPolicyApplication
        self.scheduler =
            scheduler ?? TemporaryRegularActivationScheduler()
        self.clock =
            clock ?? SystemTemporaryRegularActivationClock()
        self.policy = policy
    }

    func start(
        requestPresentation: @escaping @MainActor () -> Void,
        onOutcome: @escaping @MainActor (
            TemporaryRegularActivationRestorationOutcome
        ) -> Void
    ) {
        cancel()
        observationGeneration &+= 1
        let currentGeneration = observationGeneration
        startedAtMilliseconds = clock.monotonicMilliseconds
        hasObservedVisibleWindow = false
        presentationRequest = requestPresentation
        outcomeHandler = onOutcome
        isObserving = true

        installEvidenceObservers(generation: currentGeneration)
        if evaluate(.initialReadback, generation: currentGeneration) {
            return
        }

        requestPresentation()
        guard isCurrent(currentGeneration) else { return }
        if evaluate(.presentationReadback, generation: currentGeneration) {
            return
        }

        scheduleWatchdog(generation: currentGeneration)
        scheduleFallbackReadback(generation: currentGeneration)
    }

    func cancel() {
        observationGeneration &+= 1
        stopCurrentObservation()
        presentationRequest = nil
        outcomeHandler = nil
    }

    deinit {
        for token in observationTokens {
            token.cancel()
        }
        fallbackToken?.cancel()
        watchdogToken?.cancel()
    }

    private func installEvidenceObservers(generation: UInt64) {
        if let application =
            application as? any AppActivationEvidenceObserving
        {
            observationTokens.append(
                application.observeFlowTabActivationEvidence {
                    [weak self] source in
                    self?.handleEvidenceChange(
                        source,
                        generation: generation
                    )
                }
            )
        }
        if let window =
            window as? any AppWindowPresentationEvidenceObserving
        {
            observationTokens.append(
                window.observeFlowTabWindowPresentationEvidence {
                    [weak self] source in
                    self?.handleEvidenceChange(
                        source,
                        generation: generation
                    )
                }
            )
        }
    }

    private func handleEvidenceChange(
        _ source: TemporaryRegularActivationEvidenceSource,
        generation: UInt64
    ) {
        guard isCurrent(generation) else { return }
        _ = evaluate(source, generation: generation)
    }

    private func evaluate(
        _ source: TemporaryRegularActivationEvidenceSource,
        generation: UInt64
    ) -> Bool {
        guard isCurrent(generation) else { return true }
        let evidence = captureEvidence(source: source)

        if evidence.activationPolicy != .regular {
            finish(
                .activationPolicyChanged(evidence),
                generation: generation
            )
            return true
        }
        if evidence.isStable {
            finish(.stable(evidence), generation: generation)
            return true
        }
        if
            hasObservedVisibleWindow,
            !evidence.windowIsVisible,
            !evidence.windowIsMiniaturized
        {
            finish(
                .windowUnavailable(evidence),
                generation: generation
            )
            return true
        }
        return false
    }

    private func captureEvidence(
        source: TemporaryRegularActivationEvidenceSource
    ) -> TemporaryRegularActivationEvidence {
        let applicationIsActive =
            (application as? any AppActivationEvidenceObserving)?
                .flowTabIsActive ?? true
        let evidence = TemporaryRegularActivationEvidence(
            source: source,
            elapsedMilliseconds: max(
                0,
                clock.monotonicMilliseconds - startedAtMilliseconds
            ),
            applicationIsActive: applicationIsActive,
            windowIsVisible: window.isVisible,
            windowIsMiniaturized: window.isMiniaturized,
            activationPolicy:
                activationPolicyApplication.flowTabActivationPolicy
        )
        lastEvidence = evidence
        if evidence.windowIsVisible {
            hasObservedVisibleWindow = true
        }
        return evidence
    }

    private func scheduleFallbackReadback(generation: UInt64) {
        fallbackToken?.cancel()
        fallbackToken = scheduler.schedule(
            after: policy.fallbackReadbackInterval
        ) { [weak self] in
            self?.runFallbackReadback(generation: generation)
        }
    }

    private func runFallbackReadback(generation: UInt64) {
        guard isCurrent(generation) else { return }
        fallbackToken = nil
        if evaluate(.fallbackReadback, generation: generation) {
            return
        }

        presentationRequest?()
        guard isCurrent(generation) else { return }
        if evaluate(
            .fallbackPresentationReadback,
            generation: generation
        ) {
            return
        }
        scheduleFallbackReadback(generation: generation)
    }

    private func scheduleWatchdog(generation: UInt64) {
        watchdogToken?.cancel()
        watchdogToken = scheduler.schedule(
            after: policy.watchdogInterval
        ) { [weak self] in
            self?.runWatchdog(generation: generation)
        }
    }

    private func runWatchdog(generation: UInt64) {
        guard isCurrent(generation) else { return }
        watchdogToken = nil
        if evaluate(.watchdogReadback, generation: generation) {
            return
        }
        guard let evidence = lastEvidence else { return }
        finish(.watchdogExpired(evidence), generation: generation)
    }

    private func finish(
        _ outcome: TemporaryRegularActivationRestorationOutcome,
        generation: UInt64
    ) {
        guard isCurrent(generation) else { return }
        let handler = outcomeHandler
        stopCurrentObservation()
        presentationRequest = nil
        outcomeHandler = nil
        handler?(outcome)
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        isObserving && observationGeneration == generation
    }

    private func stopCurrentObservation() {
        isObserving = false
        for token in observationTokens {
            token.cancel()
        }
        observationTokens.removeAll()
        fallbackToken?.cancel()
        fallbackToken = nil
        watchdogToken?.cancel()
        watchdogToken = nil
    }
}
