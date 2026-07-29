import Foundation

@MainActor
final class SpaceFixtureApplicationAXSuppressionOwner {
    nonisolated static let defaultWatchdogMilliseconds = 15_000
    nonisolated static let defaultReadbackRetryIntervalMilliseconds = 100
    typealias AcknowledgementObservationInstaller =
        @MainActor (
            _ notificationName: Notification.Name,
            _ handler: @escaping @MainActor (
                SpaceFixtureProjectionAcknowledgement
            ) -> Void
        ) -> any SpaceFixtureCancellable
    typealias ExposureProvider = @MainActor () ->
        SpaceFixtureApplicationAXExposure
    typealias CompletionPublisher =
        @MainActor (
            _ completion: SpaceFixtureApplicationAXSuppressionCompletion,
            _ notificationName: Notification.Name
        ) -> Void
    private struct ActiveSuppression {
        let observationGeneration: Int
        let route: SpaceFixtureApplicationAXSuppressionRoute?
        let identity: SpaceFixtureApplicationIdentity
        let expectedProjectionWindowCount: Int
        let expectedPublishedAXWindowCount: Int
        let suppress: @MainActor () -> Void
        var localTopologyStageReached = false
        var suppressionRequested = false
        var lastAcknowledgement: SpaceFixtureProjectionAcknowledgement?
        var matchingAcknowledgement: SpaceFixtureProjectionAcknowledgement?
        var observationToken: (any SpaceFixtureCancellable)?
        var retryToken: (any SpaceFixtureCancellable)?
        var watchdogToken: (any SpaceFixtureCancellable)?
    }
    private let scheduler: any SpaceFixtureScheduling
    private let watchdogMilliseconds: Int
    private let readbackRetryIntervalMilliseconds: Int
    private let acknowledgementObservationInstaller: AcknowledgementObservationInstaller
    private let exposureProvider: ExposureProvider
    private let completionPublisher: CompletionPublisher
    private var active: ActiveSuppression?
    private(set) var observationGeneration = 0
    private(set) var suppressionGeneration: UInt64 = 0
    private(set) var lastEvidence: SpaceFixtureApplicationAXSuppressionEvidence?
    private(set) var lastFailure: SpaceFixtureApplicationAXSuppressionWatchdogFailure?

    init(
        scheduler: (any SpaceFixtureScheduling)? = nil,
        watchdogMilliseconds: Int = defaultWatchdogMilliseconds,
        readbackRetryIntervalMilliseconds: Int = defaultReadbackRetryIntervalMilliseconds,
        acknowledgementObservationInstaller: AcknowledgementObservationInstaller? = nil,
        exposureProvider: @escaping ExposureProvider,
        completionPublisher: CompletionPublisher? = nil
    ) {
        precondition(watchdogMilliseconds > 0)
        precondition(readbackRetryIntervalMilliseconds > 0)
        self.scheduler = scheduler ?? SpaceFixtureScheduler()
        self.watchdogMilliseconds = watchdogMilliseconds
        self.readbackRetryIntervalMilliseconds =
            readbackRetryIntervalMilliseconds
        self.acknowledgementObservationInstaller =
            acknowledgementObservationInstaller
            ?? { notificationName, handler in
                SpaceFixtureProjectionAcknowledgementTransport
                    .observe(
                        notificationName: notificationName,
                        handler: handler
                    )
            }
        self.exposureProvider = exposureProvider
        self.completionPublisher = completionPublisher
            ?? { completion, notificationName in
                SpaceFixtureApplicationAXSuppressionTransport
                    .post(
                        completion,
                        notificationName: notificationName
                    )
            }
    }
    var isObserving: Bool {
        active != nil
    }
    @discardableResult
    func start(
        route: SpaceFixtureApplicationAXSuppressionRoute?,
        identity: SpaceFixtureApplicationIdentity,
        expectedProjectionWindowCount: Int,
        expectedPublishedAXWindowCount: Int,
        suppress: @escaping @MainActor () -> Void
    ) -> Int {
        precondition(!identity.bundleIdentifier.isEmpty)
        precondition(identity.processIdentifier > 0)
        precondition(expectedProjectionWindowCount > 0)
        precondition(expectedPublishedAXWindowCount >= 0)
        cancel(invalidate: false)
        observationGeneration += 1
        lastEvidence = nil
        lastFailure = nil
        let generation = observationGeneration
        active = ActiveSuppression(
            observationGeneration: generation,
            route: route,
            identity: identity,
            expectedProjectionWindowCount:
                expectedProjectionWindowCount,
            expectedPublishedAXWindowCount: expectedPublishedAXWindowCount,
            suppress: suppress
        )
        if let route {
            let token = acknowledgementObservationInstaller(
                route.projectionAcknowledgementNotificationName
            ) { [weak self] acknowledgement in
                self?.observe(
                    acknowledgement: acknowledgement,
                    observationGeneration: generation
                )
            }
            guard var observing = matchingActive(generation)
            else {
                token.cancel()
                return generation
            }
            observing.observationToken = token
            active = observing
        }
        let watchdogToken = scheduler.schedule(
            afterMilliseconds: watchdogMilliseconds
        ) { [weak self] in
            self?.expireWatchdog(
                observationGeneration: generation
            )
        }
        guard var armed = matchingActive(generation) else {
            watchdogToken.cancel()
            return generation
        }
        armed.watchdogToken = watchdogToken
        active = armed
        evaluate(
            source: .initialReadback,
            observationGeneration: generation
        )
        return generation
    }
    func localTopologyStageDidResolve() {
        guard var current = active else { return }
        current.localTopologyStageReached = true
        active = current
        evaluate(
            source: .localTopologyStage,
            observationGeneration: current.observationGeneration
        )
    }
    func cancel(invalidate: Bool = true) {
        cancelActive()
        if invalidate {
            observationGeneration += 1
        }
    }
    private func observe(
        acknowledgement: SpaceFixtureProjectionAcknowledgement,
        observationGeneration: Int
    ) {
        guard var current = matchingActive(
            observationGeneration
        ) else {
            return
        }
        current.lastAcknowledgement = acknowledgement
        if acknowledgement.bundleIdentifier
                == current.identity.bundleIdentifier,
           acknowledgement.processIdentifier
                == current.identity.processIdentifier,
           acknowledgement.windowCount
                == current.expectedProjectionWindowCount,
           acknowledgement.acknowledgementGeneration
                > (
                    current.matchingAcknowledgement?
                        .acknowledgementGeneration ?? 0
                )
        {
            current.matchingAcknowledgement =
                acknowledgement
        }
        active = current
        evaluate(
            source: .projectionAcknowledgement,
            observationGeneration: observationGeneration
        )
    }
    private func evaluate(
        source: SpaceFixtureApplicationAXSuppressionEvidenceSource,
        observationGeneration: Int,
        allowsRetry: Bool = true
    ) {
        guard var current = matchingActive(
            observationGeneration
        ) else {
            return
        }
        let exposure = exposureProvider()
        let evidence = makeEvidence(
            source: source,
            current: current,
            exposure: exposure
        )
        lastEvidence = evidence
        if !current.suppressionRequested,
           current.localTopologyStageReached,
           exposure.matchesPublishedWindowCount(
                current.expectedPublishedAXWindowCount
           ),
           current.route == nil
                || current.matchingAcknowledgement != nil
        {
            current.suppressionRequested = true
            current.retryToken?.cancel()
            current.retryToken = nil
            active = current
            current.suppress()
            evaluate(
                source: .suppressionActionReadback,
                observationGeneration: observationGeneration,
                allowsRetry: allowsRetry
            )
            return
        }
        if current.suppressionRequested {
            if exposure.isSuppressed {
                finish(
                    current: current,
                    exposure: exposure
                )
            } else if allowsRetry {
                scheduleRetry(
                    observationGeneration: observationGeneration
                )
            }
            return
        }
        if current.localTopologyStageReached,
           !exposure.matchesPublishedWindowCount(
                current.expectedPublishedAXWindowCount
           ),
           allowsRetry
        {
            scheduleRetry(
                observationGeneration: observationGeneration
            )
        } else {
            current.retryToken?.cancel()
            current.retryToken = nil
            active = current
        }
    }
    private func scheduleRetry(
        observationGeneration: Int
    ) {
        guard let current = matchingActive(
            observationGeneration
        ), current.retryToken == nil else {
            return
        }
        let token = scheduler.schedule(
            afterMilliseconds:
                readbackRetryIntervalMilliseconds
        ) { [weak self] in
            self?.retry(
                observationGeneration: observationGeneration
            )
        }
        guard var armed = matchingActive(
            observationGeneration
        ) else {
            token.cancel()
            return
        }
        armed.retryToken = token
        active = armed
    }
    private func retry(observationGeneration: Int) {
        guard var current = matchingActive(
            observationGeneration
        ) else {
            return
        }
        current.retryToken = nil
        active = current
        evaluate(
            source: .retryReadback,
            observationGeneration: observationGeneration
        )
    }
    private func expireWatchdog(
        observationGeneration: Int
    ) {
        guard matchingActive(observationGeneration) != nil
        else {
            return
        }
        let previousEvidence = lastEvidence
        evaluate(
            source: .watchdogReadback,
            observationGeneration: observationGeneration,
            allowsRetry: false
        )
        guard matchingActive(observationGeneration) != nil,
              let finalEvidence = lastEvidence
        else {
            return
        }
        cancelActive()
        let failure =
            SpaceFixtureApplicationAXSuppressionWatchdogFailure(
                watchdogMilliseconds: watchdogMilliseconds,
                lastEvidence: previousEvidence ?? finalEvidence,
                finalEvidence: finalEvidence
            )
        lastFailure = failure
        NSLog(
            "SpaceFixture AX suppression watchdog failed: %@",
            failure.logFields
        )
    }
    private func finish(
        current: ActiveSuppression,
        exposure: SpaceFixtureApplicationAXExposure
    ) {
        cancelActive()
        suppressionGeneration &+= 1
        guard let route = current.route,
              let acknowledgement =
                current.matchingAcknowledgement
        else {
            return
        }
        completionPublisher(
            SpaceFixtureApplicationAXSuppressionCompletion(
                observationGeneration:
                    current.observationGeneration,
                suppressionGeneration:
                    suppressionGeneration,
                identity: current.identity,
                expectedProjectionWindowCount:
                    current.expectedProjectionWindowCount,
                acknowledgement: acknowledgement,
                exposure: exposure
            ),
            route.suppressionCompletionNotificationName
        )
    }
    private func makeEvidence(
        source: SpaceFixtureApplicationAXSuppressionEvidenceSource,
        current: ActiveSuppression,
        exposure: SpaceFixtureApplicationAXExposure
    ) -> SpaceFixtureApplicationAXSuppressionEvidence {
        SpaceFixtureApplicationAXSuppressionEvidence(
            source: source,
            observationGeneration:
                current.observationGeneration,
            identity: current.identity,
            expectedProjectionWindowCount:
                current.expectedProjectionWindowCount,
            expectedPublishedAXWindowCount:
                current.expectedPublishedAXWindowCount,
            routeIsConfigured: current.route != nil,
            localTopologyStageReached:
                current.localTopologyStageReached,
            suppressionRequested:
                current.suppressionRequested,
            exposure: exposure,
            lastAcknowledgement:
                current.lastAcknowledgement,
            matchingAcknowledgement:
                current.matchingAcknowledgement
        )
    }
    private func matchingActive(
        _ observationGeneration: Int
    ) -> ActiveSuppression? {
        guard let active,
              active.observationGeneration
                == observationGeneration
        else {
            return nil
        }
        return active
    }
    private func cancelActive() {
        active?.observationToken?.cancel()
        active?.retryToken?.cancel()
        active?.watchdogToken?.cancel()
        active = nil
    }
}
