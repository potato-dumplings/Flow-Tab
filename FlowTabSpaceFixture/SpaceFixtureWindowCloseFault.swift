import Foundation

struct SpaceFixtureWindowCloseFaultPolicy:
    Equatable
{
    static let defaultReadbackRetryIntervalMilliseconds =
        50
    static let defaultWatchdogMilliseconds = 10_000

    let targetWindowPlanIndex: Int
    let delayMilliseconds: Int
    let readbackRetryIntervalMilliseconds: Int
    let watchdogMilliseconds: Int

    init?(
        targetWindowPlanIndex: Int,
        delayMilliseconds: Int,
        readbackRetryIntervalMilliseconds: Int =
            Self
                .defaultReadbackRetryIntervalMilliseconds,
        watchdogMilliseconds: Int =
            Self.defaultWatchdogMilliseconds
    ) {
        guard targetWindowPlanIndex > 0,
              delayMilliseconds >= 0,
              readbackRetryIntervalMilliseconds > 0,
              watchdogMilliseconds > 0
        else {
            return nil
        }
        self.targetWindowPlanIndex =
            targetWindowPlanIndex
        self.delayMilliseconds = delayMilliseconds
        self.readbackRetryIntervalMilliseconds =
            readbackRetryIntervalMilliseconds
        self.watchdogMilliseconds = watchdogMilliseconds
    }
}

struct SpaceFixtureWindowCloseFaultWatchdogFailure:
    Equatable
{
    let targetWindowPlanIndex: Int
    let delayMilliseconds: Int
    let retryIntervalMilliseconds: Int
    let watchdogMilliseconds: Int
    let lastObservation:
        SpaceFixtureWindowCloseFaultObservation
    let finalObservation:
        SpaceFixtureWindowCloseFaultObservation

    var logFields: String {
        "condition=windowCloseTopology "
            + "delayMs=\(delayMilliseconds) "
            + "retryMs=\(retryIntervalMilliseconds) "
            + "watchdogMs=\(watchdogMilliseconds) "
            + "unmet=["
            + finalObservation.snapshot
                .unmetConditions(
                    expectedTargetWindowPlanIndex:
                        targetWindowPlanIndex
                )
                .joined(separator: ",")
            + "] last{\(lastObservation.logFields)} "
            + "final{\(finalObservation.logFields)}"
    }
}

@MainActor
final class SpaceFixtureWindowCloseFaultOwner {
    typealias SnapshotProvider =
        @MainActor ()
            -> SpaceFixtureWindowCloseTopologySnapshot
    typealias EvidencePublisher =
        @MainActor (
            SpaceFixtureWindowCloseFaultEvidence
        ) -> Void
    typealias WatchdogHandler =
        @MainActor (
            SpaceFixtureWindowCloseFaultWatchdogFailure
        ) -> Void
    typealias TriggerObserverFactory =
        @MainActor (
            SpaceFixtureWindowCloseFaultTriggerRoute,
            @escaping @MainActor (
                SpaceFixtureWindowCloseFaultTrigger
            ) -> Void
        ) -> any SpaceFixtureCancellable

    private enum Phase: Equatable {
        case awaitingExplicitTrigger
        case awaitingConfiguredDelay
        case applyingClose
        case awaitingReadback
    }

    private struct ActiveRequest {
        let generation: Int
        let policy: SpaceFixtureWindowCloseFaultPolicy
        let identity: SpaceFixtureWindowCloseFaultIdentity
        let triggerRoute:
            SpaceFixtureWindowCloseFaultTriggerRoute?
        let snapshotProvider: SnapshotProvider
        let applyClose: @MainActor () -> Void
        let onWatchdog: WatchdogHandler
        var phase: Phase
        var triggerToken:
            (any SpaceFixtureCancellable)?
        var scheduledToken:
            (any SpaceFixtureCancellable)?
        var retryToken:
            (any SpaceFixtureCancellable)?
        var watchdogToken:
            (any SpaceFixtureCancellable)?
    }

    private let scheduler: any SpaceFixtureScheduling
    private let evidencePublisher: EvidencePublisher
    private let triggerObserverFactory:
        TriggerObserverFactory
    private var activeRequest: ActiveRequest?

    private(set) var requestGeneration = 0
    private(set) var lastObservation:
        SpaceFixtureWindowCloseFaultObservation?
    private(set) var lastEvidence:
        SpaceFixtureWindowCloseFaultEvidence?
    private(set) var lastFailure:
        SpaceFixtureWindowCloseFaultWatchdogFailure?

    init(
        scheduler: (any SpaceFixtureScheduling)? = nil,
        triggerObserverFactory:
            TriggerObserverFactory? = nil,
        evidencePublisher:
            @escaping EvidencePublisher
    ) {
        self.scheduler = scheduler ?? SpaceFixtureScheduler()
        self.triggerObserverFactory =
            triggerObserverFactory
            ?? { route, onTrigger in
                SpaceFixtureWindowCloseFaultTriggerObservation(
                    route: route,
                    onTrigger: onTrigger
                )
            }
        self.evidencePublisher = evidencePublisher
    }

    var isPending: Bool {
        activeRequest != nil
    }

    @discardableResult
    func start(
        policy: SpaceFixtureWindowCloseFaultPolicy,
        identity: SpaceFixtureWindowCloseFaultIdentity,
        triggerRoute:
            SpaceFixtureWindowCloseFaultTriggerRoute? = nil,
        snapshotProvider:
            @escaping SnapshotProvider,
        applyClose: @escaping @MainActor () -> Void,
        onWatchdog:
            @escaping WatchdogHandler
    ) -> Int {
        precondition(
            !identity.bundleIdentifier.isEmpty,
            "Fixture window-close identity requires a bundle ID."
        )
        precondition(
            identity.processIdentifier > 0,
            "Fixture window-close identity requires a positive PID."
        )
        cancel(invalidate: false)
        requestGeneration += 1
        let generation = requestGeneration
        lastObservation = nil
        lastEvidence = nil
        lastFailure = nil
        activeRequest = ActiveRequest(
            generation: generation,
            policy: policy,
            identity: identity,
            triggerRoute: triggerRoute,
            snapshotProvider: snapshotProvider,
            applyClose: applyClose,
            onWatchdog: onWatchdog,
            phase:
                triggerRoute == nil
                ? .awaitingConfiguredDelay
                : .awaitingExplicitTrigger,
            triggerToken: nil,
            scheduledToken: nil,
            retryToken: nil,
            watchdogToken: nil
        )

        installTriggerObservationIfNeeded(
            route: triggerRoute,
            generation: generation
        )
        guard activeRequest?.generation == generation else {
            return generation
        }
        let initialObservation = observe(
            source: .initialReadback,
            generation: generation
        )
        publish(
            phase: .scheduled,
            observation: initialObservation,
            generation: generation
        )
        guard activeRequest?.generation == generation else {
            return generation
        }
        if initialObservation.snapshot.isResolved(
            expectedTargetWindowPlanIndex:
                policy.targetWindowPlanIndex
        ) {
            finish(
                observation: initialObservation,
                generation: generation
            )
            return generation
        }

        guard triggerRoute == nil else {
            return generation
        }
        scheduleConfiguredDelay(generation: generation)
        return generation
    }

    private func installTriggerObservationIfNeeded(
        route: SpaceFixtureWindowCloseFaultTriggerRoute?,
        generation: Int
    ) {
        guard let route else { return }
        let token = triggerObserverFactory(route) {
            [weak self] trigger in
            self?.receive(
                trigger: trigger,
                generation: generation
            )
        }
        guard var current = activeRequest,
              current.generation == generation,
              current.phase == .awaitingExplicitTrigger,
              current.triggerToken == nil
        else {
            token.cancel()
            return
        }
        current.triggerToken = token
        activeRequest = current
    }

    private func receive(
        trigger: SpaceFixtureWindowCloseFaultTrigger,
        generation: Int
    ) {
        guard var current = activeRequest,
              current.generation == generation,
              current.phase == .awaitingExplicitTrigger,
              trigger.requestGeneration == generation,
              trigger.identity == current.identity,
              trigger.targetWindowPlanIndex
                == current.policy.targetWindowPlanIndex
        else {
            return
        }
        current.triggerToken?.cancel()
        current.triggerToken = nil
        current.phase = .awaitingConfiguredDelay
        activeRequest = current
        scheduleConfiguredDelay(generation: generation)
    }

    private func scheduleConfiguredDelay(generation: Int) {
        guard var current = activeRequest,
              current.generation == generation,
              current.phase == .awaitingConfiguredDelay,
              current.scheduledToken == nil
        else {
            return
        }
        let token = scheduler.schedule(
            afterMilliseconds:
                current.policy.delayMilliseconds
        ) { [weak self] in
            self?.applyClose(generation: generation)
        }
        guard var current = activeRequest,
              current.generation == generation,
              current.phase == .awaitingConfiguredDelay,
              current.scheduledToken == nil
        else {
            token.cancel()
            return
        }
        current.scheduledToken = token
        activeRequest = current
    }

    func cancel(invalidate: Bool = true) {
        let hadActiveRequest = activeRequest != nil
        cancelTokens(in: activeRequest)
        activeRequest = nil
        if invalidate && hadActiveRequest {
            requestGeneration += 1
        }
    }

    private func applyClose(generation: Int) {
        guard var current = activeRequest,
              current.generation == generation,
              current.phase == .awaitingConfiguredDelay
        else {
            return
        }
        current.scheduledToken?.cancel()
        current.scheduledToken = nil
        current.phase = .applyingClose
        activeRequest = current
        current.applyClose()

        guard var awaitingReadback = activeRequest,
              awaitingReadback.generation == generation,
              awaitingReadback.phase == .applyingClose
        else {
            return
        }
        awaitingReadback.phase = .awaitingReadback
        activeRequest = awaitingReadback
        evaluate(
            source: .closeActionReadback,
            generation: generation
        )
    }

    private func evaluate(
        source: SpaceFixtureWindowCloseFaultEvidenceSource,
        generation: Int
    ) {
        guard let current = activeRequest,
              current.generation == generation,
              current.phase == .awaitingReadback
        else {
            return
        }
        let previousObservation = lastObservation
        let observation = observe(
            source: source,
            generation: generation
        )
        if observation.snapshot.isResolved(
            expectedTargetWindowPlanIndex:
                current.policy.targetWindowPlanIndex
        ) {
            finish(
                observation: observation,
                generation: generation
            )
            return
        }
        if source == .watchdogReadback {
            fail(
                previousObservation:
                    previousObservation,
                finalObservation: observation,
                request: current
            )
            return
        }
        scheduleReadbackWork(generation: generation)
    }

    private func scheduleReadbackWork(generation: Int) {
        scheduleRetryIfNeeded(generation: generation)
        scheduleWatchdogIfNeeded(generation: generation)
    }

    private func scheduleRetryIfNeeded(generation: Int) {
        guard let current = activeRequest,
              current.generation == generation,
              current.phase == .awaitingReadback,
              current.retryToken == nil
        else {
            return
        }
        let token = scheduler.schedule(
            afterMilliseconds:
                current.policy
                    .readbackRetryIntervalMilliseconds
        ) { [weak self] in
            self?.retryReadback(generation: generation)
        }
        guard var pending = activeRequest,
              pending.generation == generation,
              pending.phase == .awaitingReadback,
              pending.retryToken == nil
        else {
            token.cancel()
            return
        }
        pending.retryToken = token
        activeRequest = pending
    }

    private func scheduleWatchdogIfNeeded(generation: Int) {
        guard let current = activeRequest,
              current.generation == generation,
              current.phase == .awaitingReadback,
              current.watchdogToken == nil
        else {
            return
        }
        let token = scheduler.schedule(
            afterMilliseconds:
                current.policy.watchdogMilliseconds
        ) { [weak self] in
            self?.watchdogDidFire(generation: generation)
        }
        guard var pending = activeRequest,
              pending.generation == generation,
              pending.phase == .awaitingReadback,
              pending.watchdogToken == nil
        else {
            token.cancel()
            return
        }
        pending.watchdogToken = token
        activeRequest = pending
    }

    private func retryReadback(generation: Int) {
        guard var current = activeRequest,
              current.generation == generation,
              current.phase == .awaitingReadback
        else {
            return
        }
        current.retryToken?.cancel()
        current.retryToken = nil
        activeRequest = current
        evaluate(
            source: .retryReadback,
            generation: generation
        )
    }

    private func watchdogDidFire(generation: Int) {
        guard var current = activeRequest,
              current.generation == generation,
              current.phase == .awaitingReadback
        else {
            return
        }
        current.watchdogToken?.cancel()
        current.watchdogToken = nil
        activeRequest = current
        evaluate(
            source: .watchdogReadback,
            generation: generation
        )
    }

    private func observe(
        source: SpaceFixtureWindowCloseFaultEvidenceSource,
        generation: Int
    ) -> SpaceFixtureWindowCloseFaultObservation {
        guard let current = activeRequest,
              current.generation == generation
        else {
            preconditionFailure(
                "Window-close readback requires an active generation."
            )
        }
        let observation =
            SpaceFixtureWindowCloseFaultObservation(
                requestGeneration: generation,
                source: source,
                snapshot: current.snapshotProvider()
            )
        lastObservation = observation
        return observation
    }

    private func finish(
        observation: SpaceFixtureWindowCloseFaultObservation,
        generation: Int
    ) {
        guard let current = activeRequest,
              current.generation == generation
        else {
            return
        }
        cancelTokens(in: current)
        activeRequest = nil
        publish(
            phase: .applied,
            observation: observation,
            generation: generation,
            request: current
        )
    }

    private func fail(
        previousObservation:
            SpaceFixtureWindowCloseFaultObservation?,
        finalObservation:
            SpaceFixtureWindowCloseFaultObservation,
        request: ActiveRequest
    ) {
        guard activeRequest?.generation
            == request.generation
        else {
            return
        }
        let failure =
            SpaceFixtureWindowCloseFaultWatchdogFailure(
                targetWindowPlanIndex:
                    request.policy
                        .targetWindowPlanIndex,
                delayMilliseconds:
                    request.policy.delayMilliseconds,
                retryIntervalMilliseconds:
                    request.policy
                        .readbackRetryIntervalMilliseconds,
                watchdogMilliseconds:
                    request.policy.watchdogMilliseconds,
                lastObservation:
                    previousObservation
                    ?? finalObservation,
                finalObservation: finalObservation
            )
        cancelTokens(in: request)
        activeRequest = nil
        lastFailure = failure
        request.onWatchdog(failure)
    }

    private func publish(
        phase: SpaceFixtureWindowCloseFaultEvidencePhase,
        observation:
            SpaceFixtureWindowCloseFaultObservation,
        generation: Int,
        request: ActiveRequest? = nil
    ) {
        guard let resolvedRequest =
                request
                ?? activeRequest,
              resolvedRequest.generation == generation
        else {
            return
        }
        let evidence =
            SpaceFixtureWindowCloseFaultEvidence(
                requestGeneration: generation,
                phase: phase,
                source: observation.source,
                delayMilliseconds:
                    resolvedRequest.policy
                        .delayMilliseconds,
                awaitsExplicitTrigger:
                    resolvedRequest.triggerRoute != nil,
                identity: resolvedRequest.identity,
                snapshot: observation.snapshot
            )
        lastEvidence = evidence
        evidencePublisher(evidence)
    }

    private func cancelTokens(
        in request: ActiveRequest?
    ) {
        request?.triggerToken?.cancel()
        request?.scheduledToken?.cancel()
        request?.retryToken?.cancel()
        request?.watchdogToken?.cancel()
    }
}

@MainActor
private final class SpaceFixtureWindowCloseFaultTriggerObservation:
    SpaceFixtureCancellable
{
    private let center: DistributedNotificationCenter
    private var token: NSObjectProtocol?

    init(
        route: SpaceFixtureWindowCloseFaultTriggerRoute,
        center: DistributedNotificationCenter = .default(),
        onTrigger:
            @escaping @MainActor (
                SpaceFixtureWindowCloseFaultTrigger
            ) -> Void
    ) {
        self.center = center
        token = center.addObserver(
            forName: route.notificationName,
            object: nil,
            queue: .main
        ) { notification in
            guard let trigger =
                    SpaceFixtureWindowCloseFaultTriggerTransport
                        .trigger(from: notification)
            else {
                return
            }
            Task { @MainActor in
                onTrigger(trigger)
            }
        }
    }

    func cancel() {
        guard let token else { return }
        center.removeObserver(token)
        self.token = nil
    }

    deinit {
        if let token {
            center.removeObserver(token)
        }
    }
}
