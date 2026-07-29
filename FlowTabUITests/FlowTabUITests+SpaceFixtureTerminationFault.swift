import Foundation
import XCTest

struct SpaceFixtureTerminationFaultUITestRoute {
    let notificationName: Notification.Name

    var fixtureLaunchArguments: [String] {
        [
            SpaceFixtureTerminationFaultEvidenceRoute
                .notificationArgument,
            notificationName.rawValue
        ]
    }
}

final class SpaceFixtureTerminationFaultObservationOwner {
    private let route:
        SpaceFixtureTerminationFaultUITestRoute
    private let center: DistributedNotificationCenter
    private let scheduledExpectation =
        XCTestExpectation(
            description:
                "fixture termination fault scheduled evidence"
        )
    private let appliedExpectation =
        XCTestExpectation(
            description:
                "fixture termination fault applied evidence"
        )
    private var observationToken: NSObjectProtocol?
    private var observedEvidence:
        [SpaceFixtureTerminationFaultEvidence] = []

    init(
        route: SpaceFixtureTerminationFaultUITestRoute,
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
            forName: route.notificationName,
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
    ) -> SpaceFixtureTerminationFaultEvidence? {
        wait(
            for: scheduledExpectation,
            phase: .scheduled,
            timeout: timeout
        )
    }

    func waitForApplied(
        requestGeneration: Int,
        timeout: TimeInterval
    ) -> SpaceFixtureTerminationFaultEvidence? {
        guard wait(
            for: appliedExpectation,
            phase: .applied,
            timeout: timeout
        )?.requestGeneration == requestGeneration
        else {
            return nil
        }
        return matchingEvidence(
            phase: .applied,
            requestGeneration: requestGeneration
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
                SpaceFixtureTerminationFaultEvidenceTransport
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
        phase: SpaceFixtureTerminationFaultEvidencePhase,
        timeout: TimeInterval
    ) -> SpaceFixtureTerminationFaultEvidence? {
        if let evidence = matchingEvidence(
            phase: phase,
            requestGeneration: nil
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
            requestGeneration: nil
        )
    }

    private func matchingEvidence(
        phase: SpaceFixtureTerminationFaultEvidencePhase,
        requestGeneration: Int?
    ) -> SpaceFixtureTerminationFaultEvidence? {
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
    func makeSpaceFixtureTerminationFaultRoute()
        -> SpaceFixtureTerminationFaultUITestRoute
    {
        SpaceFixtureTerminationFaultUITestRoute(
            notificationName: Notification.Name(
                "io.github.potato-dumplings.flowtab."
                    + "ui-test.fixture-termination."
                    + UUID().uuidString
            )
        )
    }
}
