import Combine
import Foundation

@MainActor
final class RuntimePermissionObservationCoordinator: ObservableObject {
    private struct Observation {
        let generation: UInt64
        let mode: RuntimePermissionObservationMode
        let startedAtMs: Double
        let identity: RuntimePermissionObservationIdentity
        let readPermission: @MainActor () -> Bool
        let onEvidence:
            @MainActor (RuntimePermissionObservationEvidence) -> Void
        let onWatchdog:
            @MainActor (RuntimePermissionObservationDiagnostic) -> Void
        var readbackCount: Int
        var fallbackToken:
            (any RuntimePermissionObservationCancellable)?
        var watchdogToken:
            (any RuntimePermissionObservationCancellable)?
    }

    private let clock: any RuntimePermissionObservationClockReading
    private let scheduler: any RuntimePermissionObservationScheduling
    private let activationObserver:
        any RuntimePermissionActivationObserving
    private let policy: RuntimePermissionObservationPolicy
    private var nextGeneration: UInt64 = 1
    private var observations:
        [RuntimePermissionTarget: Observation] = [:]
    private var activationToken:
        (any RuntimePermissionObservationCancellable)?
    private var activationGeneration: UInt64 = 0

    init(
        clock: (any RuntimePermissionObservationClockReading)? = nil,
        scheduler:
            (any RuntimePermissionObservationScheduling)? = nil,
        activationObserver:
            (any RuntimePermissionActivationObserving)? = nil,
        policy: RuntimePermissionObservationPolicy = .standard
    ) {
        self.clock =
            clock ?? SystemRuntimePermissionObservationClock()
        self.scheduler =
            scheduler ?? RuntimePermissionObservationScheduler()
        self.activationObserver =
            activationObserver ?? RuntimePermissionActivationObserver()
        self.policy = policy
    }

    @discardableResult
    func start(
        target: RuntimePermissionTarget,
        mode: RuntimePermissionObservationMode,
        identity: RuntimePermissionObservationIdentity = .current,
        readPermission: @escaping @MainActor () -> Bool,
        onEvidence:
            @escaping @MainActor (RuntimePermissionObservationEvidence) -> Void,
        onWatchdog:
            @escaping @MainActor (RuntimePermissionObservationDiagnostic) -> Void
    ) -> RuntimePermissionObservationEvidence {
        if case let .untilGranted(watchdogInterval) = mode {
            precondition(
                watchdogInterval > 0,
                "Permission observation watchdog interval must be positive."
            )
        }

        cancel(target: target)
        let generation = nextGeneration
        nextGeneration &+= 1
        observations[target] = Observation(
            generation: generation,
            mode: mode,
            startedAtMs: clock.monotonicMilliseconds,
            identity: identity,
            readPermission: readPermission,
            onEvidence: onEvidence,
            onWatchdog: onWatchdog,
            readbackCount: 0,
            fallbackToken: nil,
            watchdogToken: nil
        )

        installActivationObserverIfNeeded()
        let evidence = readback(
            target: target,
            generation: generation,
            source: .initialReadback
        )
        precondition(
            evidence != nil,
            "A newly installed permission observation must produce an initial readback."
        )
        return evidence!
    }

    @discardableResult
    func readback(
        target: RuntimePermissionTarget,
        source: RuntimePermissionObservationEvidence.Source
    ) -> RuntimePermissionObservationEvidence? {
        guard let observation = observations[target] else { return nil }
        return readback(
            target: target,
            generation: observation.generation,
            source: source
        )
    }

    func cancel(target: RuntimePermissionTarget) {
        guard let observation = observations.removeValue(forKey: target) else {
            return
        }
        observation.fallbackToken?.cancel()
        observation.watchdogToken?.cancel()
        removeActivationObserverIfIdle()
    }

    func cancelAll() {
        let activeTargets = Array(observations.keys)
        for target in activeTargets {
            cancel(target: target)
        }
        activationToken?.cancel()
        activationToken = nil
    }

    func isObserving(_ target: RuntimePermissionTarget) -> Bool {
        observations[target] != nil
    }

    deinit {
        for observation in observations.values {
            observation.fallbackToken?.cancel()
            observation.watchdogToken?.cancel()
        }
        activationToken?.cancel()
    }

    private func installActivationObserverIfNeeded() {
        guard activationToken == nil else { return }
        activationGeneration &+= 1
        let generation = activationGeneration
        activationToken = activationObserver.observeActivations {
            [weak self] in
            self?.handleAppActivation(generation: generation)
        }
    }

    private func removeActivationObserverIfIdle() {
        guard observations.isEmpty else { return }
        activationGeneration &+= 1
        activationToken?.cancel()
        activationToken = nil
    }

    private func handleAppActivation(generation: UInt64) {
        guard generation == activationGeneration else { return }
        let bindings = observations.map {
            (target: $0.key, generation: $0.value.generation)
        }
        for binding in bindings {
            _ = readback(
                target: binding.target,
                generation: binding.generation,
                source: .appActivation
            )
        }
    }

    @discardableResult
    private func readback(
        target: RuntimePermissionTarget,
        generation: UInt64,
        source: RuntimePermissionObservationEvidence.Source
    ) -> RuntimePermissionObservationEvidence? {
        guard var observation = observations[target],
              observation.generation == generation
        else {
            return nil
        }

        observation.readbackCount += 1
        let evidence = RuntimePermissionObservationEvidence(
            target: target,
            observationGeneration: generation,
            source: source,
            readbackCount: observation.readbackCount,
            elapsedMs: elapsedMilliseconds(since: observation.startedAtMs),
            isGranted: observation.readPermission()
        )
        observations[target] = observation
        observation.onEvidence(evidence)

        guard let current = observations[target],
              current.generation == generation
        else {
            return evidence
        }

        if current.mode.completesWhenGranted && evidence.isGranted {
            finish(target: target, generation: generation)
            return evidence
        }

        if source == .watchdogReadback {
            expireWatchdog(
                target: target,
                generation: generation,
                finalEvidence: evidence
            )
            return evidence
        }

        scheduleFallbackIfNeeded(
            target: target,
            generation: generation
        )
        scheduleWatchdogIfNeeded(
            target: target,
            generation: generation
        )
        return evidence
    }

    private func scheduleFallbackIfNeeded(
        target: RuntimePermissionTarget,
        generation: UInt64
    ) {
        // TCC exposes no unified permission-transition notification. App
        // activation covers the common System Settings return path; this
        // cancellable readback covers transitions without that lifecycle event.
        guard var observation = observations[target],
              observation.generation == generation,
              observation.fallbackToken == nil
        else {
            return
        }
        observation.fallbackToken = scheduler.schedule(
            after: policy.fallbackReadbackInterval
        ) { [weak self] in
            self?.handleFallbackReadback(
                target: target,
                generation: generation
            )
        }
        observations[target] = observation
    }

    private func scheduleWatchdogIfNeeded(
        target: RuntimePermissionTarget,
        generation: UInt64
    ) {
        guard var observation = observations[target],
              observation.generation == generation,
              observation.watchdogToken == nil,
              let watchdogInterval = observation.mode.watchdogInterval
        else {
            return
        }
        let elapsedSeconds =
            elapsedMilliseconds(since: observation.startedAtMs) / 1_000
        observation.watchdogToken = scheduler.schedule(
            after: max(0, watchdogInterval - elapsedSeconds)
        ) { [weak self] in
            self?.handleWatchdogWake(
                target: target,
                generation: generation
            )
        }
        observations[target] = observation
    }

    private func handleFallbackReadback(
        target: RuntimePermissionTarget,
        generation: UInt64
    ) {
        guard var observation = observations[target],
              observation.generation == generation
        else {
            return
        }
        observation.fallbackToken = nil
        observations[target] = observation
        _ = readback(
            target: target,
            generation: generation,
            source: .fallbackReadback
        )
    }

    private func handleWatchdogWake(
        target: RuntimePermissionTarget,
        generation: UInt64
    ) {
        guard var observation = observations[target],
              observation.generation == generation,
              let watchdogInterval = observation.mode.watchdogInterval
        else {
            return
        }
        observation.watchdogToken = nil
        observations[target] = observation

        let elapsedSeconds =
            elapsedMilliseconds(since: observation.startedAtMs) / 1_000
        guard elapsedSeconds >= watchdogInterval else {
            scheduleWatchdogIfNeeded(
                target: target,
                generation: generation
            )
            return
        }
        _ = readback(
            target: target,
            generation: generation,
            source: .watchdogReadback
        )
    }

    private func expireWatchdog(
        target: RuntimePermissionTarget,
        generation: UInt64,
        finalEvidence: RuntimePermissionObservationEvidence
    ) {
        guard let observation = observations[target],
              observation.generation == generation
        else {
            return
        }
        let watchdogDescription = observation.mode.watchdogInterval
            .map { "\(Int($0))s" }
            ?? policy.watchdogDescription
        let diagnostic = RuntimePermissionObservationDiagnostic(
            target: target,
            observationGeneration: generation,
            readbackCount: finalEvidence.readbackCount,
            elapsedMs: finalEvidence.elapsedMs,
            finalPermissionGranted: finalEvidence.isGranted,
            finalEvidenceSource: finalEvidence.source,
            watchdogDescription: watchdogDescription,
            bundleIdentifier: observation.identity.bundleIdentifier,
            bundlePath: observation.identity.bundlePath,
            action: .watchdogExpired
        )
        let completion = observation.onWatchdog
        finish(target: target, generation: generation)
        completion(diagnostic)
    }

    private func finish(
        target: RuntimePermissionTarget,
        generation: UInt64
    ) {
        guard let observation = observations[target],
              observation.generation == generation
        else {
            return
        }
        observations[target] = nil
        observation.fallbackToken?.cancel()
        observation.watchdogToken?.cancel()
        removeActivationObserverIfIdle()
    }

    private func elapsedMilliseconds(since startedAtMs: Double) -> Double {
        max(0, clock.monotonicMilliseconds - startedAtMs)
    }
}
