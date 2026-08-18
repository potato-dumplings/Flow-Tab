import Foundation

final class SpaceFixtureWorkflowDesktopAnchorOwner {
    typealias ResolvedHandler = (
        SpaceFixtureWorkflowDesktopAnchorEvidence
    ) -> Void
    typealias WatchdogHandler = (
        SpaceFixtureWorkflowDesktopAnchorWatchdogFailure
    ) -> Void

    private struct ActiveObservation {
        let generation: Int
        let expectation:
            SpaceFixtureWorkflowDesktopAnchorExpectation
        let watchdogSeconds: TimeInterval
        let onResolved: ResolvedHandler
        let onWatchdog: WatchdogHandler
        var lastEvidence:
            SpaceFixtureWorkflowDesktopAnchorEvidence?
    }

    private var active: ActiveObservation?

    private(set) var observationGeneration = 0
    private(set) var lastEvidence:
        SpaceFixtureWorkflowDesktopAnchorEvidence?
    private(set) var lastFailure:
        SpaceFixtureWorkflowDesktopAnchorWatchdogFailure?

    var isObserving: Bool {
        active != nil
    }

    @discardableResult
    func start(
        expectation:
            SpaceFixtureWorkflowDesktopAnchorExpectation,
        watchdogSeconds: TimeInterval,
        onResolved: @escaping ResolvedHandler,
        onWatchdog: @escaping WatchdogHandler
    ) -> Int {
        precondition(watchdogSeconds > 0)
        cancel(invalidate: false)
        observationGeneration += 1
        let generation = observationGeneration
        lastEvidence = nil
        lastFailure = nil
        active = ActiveObservation(
            generation: generation,
            expectation: expectation,
            watchdogSeconds: watchdogSeconds,
            onResolved: onResolved,
            onWatchdog: onWatchdog,
            lastEvidence: nil
        )
        return generation
    }

    @discardableResult
    func observe(
        snapshot:
            SpaceFixtureWorkflowDesktopAnchorSnapshot,
        source:
            SpaceFixtureWorkflowDesktopAnchorEvidenceSource,
        observationGeneration: Int
    ) -> Bool {
        guard var current = matchingActive(
            observationGeneration
        ) else {
            return false
        }
        let evidence =
            SpaceFixtureWorkflowDesktopAnchorEvidence(
                observationGeneration:
                    observationGeneration,
                source: source,
                snapshot: snapshot
            )
        current.lastEvidence = evidence
        lastEvidence = evidence
        active = current
        guard snapshot.isResolved(
            expectation: current.expectation
        ) else {
            return false
        }
        finishResolved(evidence)
        return true
    }

    @discardableResult
    func expireWatchdog(
        finalSnapshot:
            SpaceFixtureWorkflowDesktopAnchorSnapshot,
        observationGeneration: Int
    ) -> Bool {
        guard let current = matchingActive(
            observationGeneration
        ) else {
            return false
        }
        if observe(
            snapshot: finalSnapshot,
            source: .watchdogReadback,
            observationGeneration: observationGeneration
        ) {
            return true
        }
        guard let completed = takeActive() else {
            return false
        }
        let finalEvidence =
            SpaceFixtureWorkflowDesktopAnchorEvidence(
                observationGeneration:
                    observationGeneration,
                source: .watchdogReadback,
                snapshot: finalSnapshot
            )
        let failure =
            SpaceFixtureWorkflowDesktopAnchorWatchdogFailure(
                observationGeneration:
                    observationGeneration,
                watchdogSeconds:
                    current.watchdogSeconds,
                expectation: current.expectation,
                lastEvidence:
                    current.lastEvidence
                    ?? finalEvidence,
                finalEvidence: finalEvidence
            )
        lastEvidence = finalEvidence
        lastFailure = failure
        completed.onWatchdog(failure)
        return false
    }

    func cancel(invalidate: Bool = true) {
        let hadActiveObservation = active != nil
        active = nil
        if invalidate && hadActiveObservation {
            observationGeneration += 1
        }
    }

    private func finishResolved(
        _ evidence:
            SpaceFixtureWorkflowDesktopAnchorEvidence
    ) {
        guard let completed = takeActive() else {
            return
        }
        completed.onResolved(evidence)
    }

    private func takeActive() -> ActiveObservation? {
        guard let active else { return nil }
        self.active = nil
        return active
    }

    private func matchingActive(
        _ observationGeneration: Int
    ) -> ActiveObservation? {
        guard let active,
              active.generation
                == observationGeneration
        else {
            return nil
        }
        return active
    }
}
