import AppKit
import Foundation

enum ModifierReleaseObservationKind: Equatable, Sendable {
    case selectionConfirmation
    case replaySuppression
}

enum ModifierReleaseObservationSource: Equatable, Sendable {
    case initialReadback
    case inputTransition
    case fallbackSample(attempt: Int)
}

struct ModifierReleaseObservationSample: Equatable, Sendable {
    let generation: Int
    let source: ModifierReleaseObservationSource
    let inputPressed: Bool
    let releasedSamples: Int
}

@MainActor
protocol ModifierReleaseObservationCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol ModifierReleaseObservationScheduling: AnyObject {
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any ModifierReleaseObservationCancellable
}

@MainActor
private final class ModifierReleaseObservationScheduledToken:
    ModifierReleaseObservationCancellable
{
    private let task: Task<Void, Never>

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
final class ModifierReleaseObservationScheduler:
    ModifierReleaseObservationScheduling
{
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any ModifierReleaseObservationCancellable {
        ModifierReleaseObservationScheduledToken(
            interval: interval,
            action: action
        )
    }
}

@MainActor
protocol ModifierReleaseEventObserving: AnyObject {
    func start(
        relevantKeyCodes: Set<UInt16>,
        onInputTransition: @escaping @MainActor @Sendable () -> Void
    ) -> any ModifierReleaseObservationCancellable
}

@MainActor
private final class SystemModifierReleaseEventToken:
    ModifierReleaseObservationCancellable
{
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(
        relevantKeyCodes: Set<UInt16>,
        onInputTransition: @escaping @MainActor @Sendable () -> Void
    ) {
        let eventMask: NSEvent.EventTypeMask = [.flagsChanged, .keyUp]
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: eventMask
        ) { event in
            guard relevantKeyCodes.contains(event.keyCode) else { return event }
            onInputTransition()
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: eventMask
        ) { event in
            guard relevantKeyCodes.contains(event.keyCode) else { return }
            Task { @MainActor in
                onInputTransition()
            }
        }
    }

    func cancel() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
    }
}

@MainActor
final class SystemModifierReleaseEventSource: ModifierReleaseEventObserving {
    func start(
        relevantKeyCodes: Set<UInt16>,
        onInputTransition: @escaping @MainActor @Sendable () -> Void
    ) -> any ModifierReleaseObservationCancellable {
        SystemModifierReleaseEventToken(
            relevantKeyCodes: relevantKeyCodes,
            onInputTransition: onInputTransition
        )
    }
}

@MainActor
final class ModifierReleaseObservationOwner {
    typealias Readback = @MainActor (
        _ generation: Int,
        _ source: ModifierReleaseObservationSource
    ) -> Bool?
    typealias Started = @MainActor (_ generation: Int) -> Void
    typealias Sampled = @MainActor (
        _ sample: ModifierReleaseObservationSample
    ) -> Void
    typealias Completed = @MainActor (_ generation: Int) -> Void

    private struct ActiveObservation {
        let kind: ModifierReleaseObservationKind
        let generation: Int
        let sampleInterval: TimeInterval
        let requiredReleasedSampleCount: Int
        let readback: Readback
        let onSample: Sampled
        let onComplete: Completed
        var releasedSamples: Int
        var fallbackAttempt: Int
        var fallbackToken: (any ModifierReleaseObservationCancellable)?
        var eventToken: (any ModifierReleaseObservationCancellable)?
    }

    private let scheduler: any ModifierReleaseObservationScheduling
    private let eventSource: any ModifierReleaseEventObserving
    private var activeObservation: ActiveObservation?

    private(set) var generation = 0

    init(
        scheduler: (any ModifierReleaseObservationScheduling)? = nil,
        eventSource: (any ModifierReleaseEventObserving)? = nil
    ) {
        self.scheduler = scheduler ?? ModifierReleaseObservationScheduler()
        self.eventSource = eventSource ?? SystemModifierReleaseEventSource()
    }

    func isObserving(_ kind: ModifierReleaseObservationKind) -> Bool {
        activeObservation?.kind == kind
    }

    func isGenerationCurrent(_ candidate: Int) -> Bool {
        candidate == generation
    }

    @discardableResult
    func start(
        kind: ModifierReleaseObservationKind,
        relevantKeyCodes: Set<UInt16>,
        sampleInterval: TimeInterval,
        requiredReleasedSampleCount: Int,
        readback: @escaping Readback,
        onStarted: @escaping Started,
        onSample: @escaping Sampled,
        onComplete: @escaping Completed
    ) -> Int {
        clearActiveObservation()
        generation &+= 1
        let observationGeneration = generation
        activeObservation = ActiveObservation(
            kind: kind,
            generation: observationGeneration,
            sampleInterval: max(0, sampleInterval),
            requiredReleasedSampleCount: max(1, requiredReleasedSampleCount),
            readback: readback,
            onSample: onSample,
            onComplete: onComplete,
            releasedSamples: 0,
            fallbackAttempt: 0,
            fallbackToken: nil,
            eventToken: nil
        )

        let eventToken = eventSource.start(
            relevantKeyCodes: relevantKeyCodes
        ) { [weak self] in
            self?.observeInputTransition(generation: observationGeneration)
        }
        guard var active = activeObservation,
              active.generation == observationGeneration
        else {
            eventToken.cancel()
            return observationGeneration
        }
        active.eventToken = eventToken
        activeObservation = active

        onStarted(observationGeneration)
        observe(
            generation: observationGeneration,
            source: .initialReadback
        )
        if activeObservation?.generation == observationGeneration {
            scheduleFallback(generation: observationGeneration)
        }
        return observationGeneration
    }

    func observeInputTransition() {
        guard let generation = activeObservation?.generation else { return }
        observeInputTransition(generation: generation)
    }

    @discardableResult
    func cancel(
        kind: ModifierReleaseObservationKind? = nil
    ) -> Int? {
        guard let active = activeObservation else { return nil }
        if let kind, active.kind != kind {
            return nil
        }
        let canceledGeneration = active.generation
        clearActiveObservation()
        generation &+= 1
        return canceledGeneration
    }

    private func observeInputTransition(generation: Int) {
        guard var active = activeObservation,
              active.generation == generation
        else {
            return
        }
        active.fallbackToken?.cancel()
        active.fallbackToken = nil
        activeObservation = active
        observe(generation: generation, source: .inputTransition)
        if activeObservation?.generation == generation {
            scheduleFallback(generation: generation)
        }
    }

    private func observe(
        generation: Int,
        source: ModifierReleaseObservationSource
    ) {
        guard var active = activeObservation,
              active.generation == generation
        else {
            return
        }
        guard let inputPressed = active.readback(generation, source) else {
            clearActiveObservation()
            return
        }

        if inputPressed {
            active.releasedSamples = 0
        } else if source != .inputTransition || active.releasedSamples == 0 {
            active.releasedSamples += 1
        }
        let sample = ModifierReleaseObservationSample(
            generation: generation,
            source: source,
            inputPressed: inputPressed,
            releasedSamples: active.releasedSamples
        )
        activeObservation = active
        active.onSample(sample)

        guard let current = activeObservation,
              current.generation == generation,
              current.releasedSamples >= current.requiredReleasedSampleCount
        else {
            return
        }
        let completion = current.onComplete
        clearActiveObservation()
        completion(generation)
    }

    private func scheduleFallback(generation: Int) {
        guard var active = activeObservation,
              active.generation == generation,
              active.fallbackToken == nil
        else {
            return
        }
        active.fallbackAttempt += 1
        let attempt = active.fallbackAttempt
        activeObservation = active
        let token = scheduler.schedule(after: active.sampleInterval) {
            [weak self] in
            self?.fireFallback(generation: generation, attempt: attempt)
        }
        guard var registered = activeObservation,
              registered.generation == generation,
              registered.fallbackAttempt == attempt,
              registered.fallbackToken == nil
        else {
            token.cancel()
            return
        }
        registered.fallbackToken = token
        activeObservation = registered
    }

    private func fireFallback(generation: Int, attempt: Int) {
        guard var active = activeObservation,
              active.generation == generation,
              active.fallbackAttempt == attempt
        else {
            return
        }
        active.fallbackToken = nil
        activeObservation = active
        observe(
            generation: generation,
            source: .fallbackSample(attempt: attempt)
        )
        if activeObservation?.generation == generation {
            scheduleFallback(generation: generation)
        }
    }

    private func clearActiveObservation() {
        let previous = activeObservation
        activeObservation = nil
        previous?.fallbackToken?.cancel()
        previous?.eventToken?.cancel()
    }
}
