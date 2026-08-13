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

enum SpaceFixtureTerminationFaultObservationPolicy {
    static let scheduledEvidenceWatchdog: TimeInterval = 8
}

typealias SpaceFixtureTerminationFaultEvidenceRegistration =
    (
        @escaping (SpaceFixtureTerminationFaultEvidence) -> Void
    ) -> FlowTabUITestObservationCancellation?

final class SpaceFixtureTerminationFaultObservationOwner {
    private let evidenceRegistration:
        SpaceFixtureTerminationFaultEvidenceRegistration
    private var nextObservationGeneration: UInt64 = 1
    private var activeObservationGeneration: UInt64?
    private var observationCancellation:
        FlowTabUITestObservationCancellation?
    private var scheduledExpectation: XCTestExpectation?
    private var appliedExpectation: XCTestExpectation?
    private var didFulfillScheduledExpectation = false
    private var didFulfillAppliedExpectation = false
    private var observedEvidence:
        [SpaceFixtureTerminationFaultEvidence] = []
    private var requestedPhase:
        SpaceFixtureTerminationFaultEvidencePhase?
    private var lastWaitResultDescription = "notStarted"

    init(
        route: SpaceFixtureTerminationFaultUITestRoute,
        center: DistributedNotificationCenter = .default(),
        evidenceRegistration:
            SpaceFixtureTerminationFaultEvidenceRegistration? =
                nil
    ) {
        if let evidenceRegistration {
            self.evidenceRegistration = evidenceRegistration
        } else {
            self.evidenceRegistration = { callback in
                let token = center.addObserver(
                    forName: route.notificationName,
                    object: nil,
                    queue: .main
                ) { notification in
                    guard let evidence =
                            SpaceFixtureTerminationFaultEvidenceTransport
                                .evidence(from: notification)
                    else {
                        return
                    }
                    callback(evidence)
                }
                return FlowTabUITestObservationCancellation {
                    center.removeObserver(token)
                }
            }
        }
    }

    func start() {
        cancel()
        observedEvidence.removeAll()
        requestedPhase = nil
        lastWaitResultDescription = "notStarted"
        didFulfillScheduledExpectation = false
        didFulfillAppliedExpectation = false
        scheduledExpectation = makeExpectation(
            description:
                "fixture termination fault scheduled evidence"
        )
        appliedExpectation = makeExpectation(
            description:
                "fixture termination fault applied evidence"
        )

        let generation = nextObservationGeneration
        nextObservationGeneration &+= 1
        activeObservationGeneration = generation
        observationCancellation =
            evidenceRegistration { [weak self] evidence in
                self?.observe(
                    evidence,
                    generation: generation
                )
            }
    }

    func cancel() {
        activeObservationGeneration = nil
        observationCancellation?.cancel()
        observationCancellation = nil
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
        let phase = requestedPhase?.rawValue ?? "none"
        let records = observedEvidence.isEmpty
            ? "none"
            : observedEvidence
                .map(\.logFields)
                .joined(separator: " | ")
        return "observationActive=\(isObservationActive) "
            + "unmetCondition=phase=\(phase) "
            + "waitResult=\(lastWaitResultDescription) "
            + "observed=[\(records)]"
    }

    var isObservationActive: Bool {
        activeObservationGeneration != nil
    }

    var observedEvidenceCount: Int {
        observedEvidence.count
    }

    deinit {
        cancel()
    }

    private func observe(
        _ evidence: SpaceFixtureTerminationFaultEvidence,
        generation: UInt64
    ) {
        guard activeObservationGeneration == generation,
              !observedEvidence.contains(evidence)
        else {
            return
        }
        observedEvidence.append(evidence)
        switch evidence.phase {
        case .scheduled:
            guard !didFulfillScheduledExpectation else {
                return
            }
            didFulfillScheduledExpectation = true
            scheduledExpectation?.fulfill()
        case .applied:
            guard !didFulfillAppliedExpectation else {
                return
            }
            didFulfillAppliedExpectation = true
            appliedExpectation?.fulfill()
        }
    }

    private func wait(
        for expectation: XCTestExpectation?,
        phase: SpaceFixtureTerminationFaultEvidencePhase,
        timeout: TimeInterval
    ) -> SpaceFixtureTerminationFaultEvidence? {
        requestedPhase = phase
        guard activeObservationGeneration != nil,
              let expectation
        else {
            lastWaitResultDescription = "inactive"
            return nil
        }
        if let evidence = matchingEvidence(
            phase: phase,
            requestGeneration: nil
        ) {
            lastWaitResultDescription = "initialReadback"
            return evidence
        }
        let waitResult = XCTWaiter.wait(
            for: [expectation],
            timeout: timeout
        )
        lastWaitResultDescription =
            waitResultDescription(waitResult)
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

    private func makeExpectation(
        description: String
    ) -> XCTestExpectation {
        let expectation =
            XCTestExpectation(description: description)
        expectation.assertForOverFulfill = true
        return expectation
    }

    private func waitResultDescription(
        _ result: XCTWaiter.Result
    ) -> String {
        switch result {
        case .completed:
            return "completed"
        case .timedOut:
            return "timedOut"
        case .incorrectOrder:
            return "incorrectOrder"
        case .invertedFulfillment:
            return "invertedFulfillment"
        case .interrupted:
            return "interrupted"
        @unknown default:
            return "unknown"
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
