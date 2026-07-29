import Foundation
import XCTest

struct SpaceFixtureWindowCloseFaultUITestRoute {
    let evidenceNotificationName: Notification.Name
    let triggerNotificationName: Notification.Name

    var fixtureLaunchArguments: [String] {
        [
            SpaceFixtureWindowCloseFaultEvidenceRoute
                .notificationArgument,
            evidenceNotificationName.rawValue,
            SpaceFixtureWindowCloseFaultTriggerRoute
                .notificationArgument,
            triggerNotificationName.rawValue
        ]
    }
}

final class SpaceFixtureWindowCloseFaultObservationOwner {
    private let route:
        SpaceFixtureWindowCloseFaultUITestRoute
    private let center: DistributedNotificationCenter
    private let scheduledExpectation =
        XCTestExpectation(
            description:
                "fixture window-close fault scheduled evidence"
        )
    private let appliedExpectation =
        XCTestExpectation(
            description:
                "fixture window-close fault applied evidence"
        )
    private var observationToken: NSObjectProtocol?
    private var observedEvidence:
        [SpaceFixtureWindowCloseFaultEvidence] = []

    init(
        route: SpaceFixtureWindowCloseFaultUITestRoute,
        center: DistributedNotificationCenter = .default()
    ) {
        self.route = route
        self.center = center
        scheduledExpectation.assertForOverFulfill = true
        appliedExpectation.assertForOverFulfill = true
    }

    func start() {
        cancel()
        observedEvidence.removeAll()
        observationToken = center.addObserver(
            forName: route.evidenceNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.observe(notification)
        }
    }

    func cancel() {
        guard let observationToken else { return }
        center.removeObserver(observationToken)
        self.observationToken = nil
    }

    func waitForScheduled(
        timeout: TimeInterval
    ) -> SpaceFixtureWindowCloseFaultEvidence? {
        wait(
            for: scheduledExpectation,
            phase: .scheduled,
            requestGeneration: nil,
            timeout: timeout
        )
    }

    func waitForApplied(
        requestGeneration: Int,
        timeout: TimeInterval
    ) -> SpaceFixtureWindowCloseFaultEvidence? {
        wait(
            for: appliedExpectation,
            phase: .applied,
            requestGeneration: requestGeneration,
            timeout: timeout
        )
    }

    func requestClose(
        from evidence:
            SpaceFixtureWindowCloseFaultEvidence
    ) {
        SpaceFixtureWindowCloseFaultTriggerTransport
            .publish(
                SpaceFixtureWindowCloseFaultTrigger(
                    requestGeneration:
                        evidence.requestGeneration,
                    identity: evidence.identity,
                    targetWindowPlanIndex:
                        evidence.snapshot
                            .targetWindowPlanIndex
                ),
                route:
                    SpaceFixtureWindowCloseFaultTriggerRoute(
                        notificationName:
                            route.triggerNotificationName
                    )
            )
    }

    var diagnosticSummary: String {
        guard !observedEvidence.isEmpty else {
            return "unobserved"
        }
        return observedEvidence
            .map(\.logFields)
            .joined(separator: " | ")
    }

    deinit {
        if let observationToken {
            center.removeObserver(observationToken)
        }
    }

    private func observe(_ notification: Notification) {
        guard let evidence =
                SpaceFixtureWindowCloseFaultEvidenceTransport
                    .evidence(from: notification)
        else {
            return
        }
        observedEvidence.append(evidence)
        switch evidence.phase {
        case .scheduled:
            scheduledExpectation.fulfill()
        case .applied:
            appliedExpectation.fulfill()
        }
    }

    private func wait(
        for expectation: XCTestExpectation,
        phase: SpaceFixtureWindowCloseFaultEvidencePhase,
        requestGeneration: Int?,
        timeout: TimeInterval
    ) -> SpaceFixtureWindowCloseFaultEvidence? {
        if let evidence = matchingEvidence(
            phase: phase,
            requestGeneration: requestGeneration
        ) {
            return evidence
        }
        guard XCTWaiter.wait(
            for: [expectation],
            timeout: timeout
        ) == .completed
        else {
            return nil
        }
        return matchingEvidence(
            phase: phase,
            requestGeneration: requestGeneration
        )
    }

    private func matchingEvidence(
        phase: SpaceFixtureWindowCloseFaultEvidencePhase,
        requestGeneration: Int?
    ) -> SpaceFixtureWindowCloseFaultEvidence? {
        observedEvidence.last {
            $0.phase == phase
                && (
                    requestGeneration == nil
                        || $0.requestGeneration
                            == requestGeneration
                )
        }
    }
}

extension FlowTabUITests {
    func makeSpaceFixtureWindowCloseFaultRoute()
        -> SpaceFixtureWindowCloseFaultUITestRoute
    {
        let routeID = UUID().uuidString
        return SpaceFixtureWindowCloseFaultUITestRoute(
            evidenceNotificationName: Notification.Name(
                "io.github.potato-dumplings.flowtab."
                    + "ui-test.fixture-window-close.evidence."
                    + routeID
            ),
            triggerNotificationName: Notification.Name(
                "io.github.potato-dumplings.flowtab."
                    + "ui-test.fixture-window-close.trigger."
                    + routeID
            )
        )
    }
}
