import Foundation
import XCTest

enum FlowTabUITestWindowSearchQueryProjectionPolicy {
    static let multiAppResultPublicationWatchdog: TimeInterval = 8
}

private final class FlowTabUITestWindowSearchQueryProjectionState {
    let expectation:
        FlowTabUITestSwitcherSearchResultExpectation

    private(set) var triggerDidComplete = false
    private(set) var baseline:
        FlowTabUITestSwitcherSearchResultSnapshot?
    private(set) var observedProjectionTransition = false

    init(
        expectation:
            FlowTabUITestSwitcherSearchResultExpectation
    ) {
        self.expectation = expectation
    }

    func reset() {
        triggerDidComplete = false
        baseline = nil
        observedProjectionTransition = false
    }

    func markTriggerCompleted() {
        triggerDidComplete = true
    }

    func observe(
        _ snapshot: FlowTabUITestSwitcherSearchResultSnapshot
    ) {
        guard triggerDidComplete else {
            baseline = snapshot
            return
        }
        guard let baseline else { return }
        if !Self.hasSameProjection(snapshot, as: baseline) {
            observedProjectionTransition = true
        }
    }

    var acceptsEvidence: Bool {
        guard triggerDidComplete, let baseline else {
            return false
        }
        return !expectation.isSatisfied(by: baseline)
            || observedProjectionTransition
    }

    var diagnosticSummary: String {
        "phase=\(triggerDidComplete ? "postTrigger" : "baseline") "
            + "triggerDidComplete=\(triggerDidComplete) "
            + "projectionTransitionObserved="
            + "\(observedProjectionTransition) "
            + "baseline={"
            + (baseline?.diagnosticSummary ?? "unobserved")
            + "}"
    }

    private static func hasSameProjection(
        _ lhs: FlowTabUITestSwitcherSearchResultSnapshot,
        as rhs: FlowTabUITestSwitcherSearchResultSnapshot
    ) -> Bool {
        lhs.resultsScope == rhs.resultsScope
            && lhs.resultsQuery == rhs.resultsQuery
            && lhs.results == rhs.results
            && lhs.committedResultIDs == rhs.committedResultIDs
    }
}

final class FlowTabUITestWindowSearchQueryProjectionObservationOwner {
    private let state:
        FlowTabUITestWindowSearchQueryProjectionState
    private let resultOwner:
        FlowTabUITestSwitcherSearchResultObservationOwner
    private let scheduledReadbacks:
        FlowTabUITestDeferredConditionReadbackRegistration

    init(
        scope: String,
        query: String,
        title: String,
        appName: String,
        scheduledReadbackRegistration:
            @escaping FlowTabUITestConditionObservationRegistration =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestSwitcherSearchResultSnapshot
    ) {
        let expectation =
            FlowTabUITestSwitcherSearchResultExpectation
                .committedMatchingWindow(
                    scope: scope,
                    query: query,
                    title: title,
                    appName: appName
                )
        let state =
            FlowTabUITestWindowSearchQueryProjectionState(
                expectation: expectation
            )
        let scheduledReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration:
                    scheduledReadbackRegistration
            )
        self.state = state
        self.scheduledReadbacks = scheduledReadbacks
        resultOwner =
            FlowTabUITestSwitcherSearchResultObservationOwner(
                expectation: expectation,
                acceptsEvidence: {
                    state.acceptsEvidence
                },
                observationRegistration: { callback in
                    scheduledReadbacks.register(callback)
                },
                readback: {
                    let snapshot = readback()
                    state.observe(snapshot)
                    return snapshot
                }
            )
    }

    func start() {
        state.reset()
        resultOwner.start()
    }

    var hasInitialBaseline: Bool {
        state.baseline != nil
    }

    func completeTriggerAndRequestReadback() {
        state.markTriggerCompleted()
        resultOwner.requestReadback(
            source: .triggerReadback
        )
        if resultOwner.resolvedEvidence == nil {
            scheduledReadbacks.activate()
        }
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> SwitcherSearchWindowResultObservation? {
        guard
            let evidence = resultOwner.waitForResolution(
                timeout: timeout
            )
        else {
            return nil
        }
        return state.expectation.matchingResult(
            in: evidence.value
        )
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSwitcherSearchResultSnapshot
    >? {
        resultOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        state.diagnosticSummary
            + " observation={"
            + resultOwner.diagnosticSummary
            + "}"
    }

    func cancel() {
        resultOwner.cancel()
        scheduledReadbacks.cancel()
    }
}

extension FlowTabUITests {
    func performAndWaitForCommittedSearchWindowResult(
        in app: XCUIApplication,
        scope: String,
        query: String,
        title: String,
        appName: String,
        timeout: TimeInterval,
        trigger: () throws -> Void
    ) rethrows -> SwitcherSearchWindowResultObservation? {
        let owner =
            FlowTabUITestWindowSearchQueryProjectionObservationOwner(
                scope: scope,
                query: query,
                title: title,
                appName: appName,
                readback: {
                    self.committedSwitcherSearchResultSnapshot(
                        in: app
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        guard owner.hasInitialBaseline else {
            XCTFail(
                "Committed Search window-result baseline was unavailable. "
                    + owner.diagnosticSummary
            )
            return nil
        }

        try trigger()
        owner.completeTriggerAndRequestReadback()

        guard
            let result = owner.waitForResolution(
                timeout: timeout
            )
        else {
            XCTFail(
                "Committed Search window-result projection "
                    + "watchdog expired. \(owner.diagnosticSummary)"
            )
            return nil
        }
        return result
    }
}
