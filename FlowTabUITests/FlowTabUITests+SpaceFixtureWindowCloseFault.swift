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

enum SpaceFixtureWindowCloseFaultObservationPolicy {
    static let scheduledEvidenceWatchdog: TimeInterval = 8
    static let appliedEvidenceWatchdog: TimeInterval = 15
}

typealias SpaceFixtureWindowCloseFaultEvidenceRegistration =
    (
        @escaping (SpaceFixtureWindowCloseFaultEvidence) -> Void
    ) -> FlowTabUITestObservationCancellation?

final class SpaceFixtureWindowCloseFaultObservationOwner {
    private let route:
        SpaceFixtureWindowCloseFaultUITestRoute
    private let evidenceRegistration:
        SpaceFixtureWindowCloseFaultEvidenceRegistration
    private var nextObservationGeneration: UInt64 = 1
    private var activeObservationGeneration: UInt64?
    private var observationCancellation:
        FlowTabUITestObservationCancellation?
    private var scheduledExpectation: XCTestExpectation?
    private var appliedExpectation: XCTestExpectation?
    private var didFulfillScheduledExpectation = false
    private var didFulfillAppliedExpectation = false
    private var observedEvidence:
        [SpaceFixtureWindowCloseFaultEvidence] = []
    private var requestedPhase:
        SpaceFixtureWindowCloseFaultEvidencePhase?
    private var requestedGeneration: Int?
    private var lastWaitResultDescription = "notStarted"

    init(
        route: SpaceFixtureWindowCloseFaultUITestRoute,
        center: DistributedNotificationCenter = .default(),
        evidenceRegistration:
            SpaceFixtureWindowCloseFaultEvidenceRegistration? =
                nil
    ) {
        self.route = route
        if let evidenceRegistration {
            self.evidenceRegistration =
                evidenceRegistration
        } else {
            self.evidenceRegistration = { callback in
                let token = center.addObserver(
                    forName:
                        route.evidenceNotificationName,
                    object: nil,
                    queue: .main
                ) { notification in
                    guard let evidence =
                            SpaceFixtureWindowCloseFaultEvidenceTransport
                                .evidence(
                                    from: notification
                                )
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
        requestedGeneration = nil
        lastWaitResultDescription = "notStarted"
        didFulfillScheduledExpectation = false
        didFulfillAppliedExpectation = false
        scheduledExpectation =
            makeExpectation(
                description:
                    "fixture window-close fault scheduled evidence"
            )
        appliedExpectation =
            makeExpectation(
                description:
                    "fixture window-close fault applied evidence"
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
        let phase =
            requestedPhase?.rawValue ?? "none"
        let generation =
            requestedGeneration.map(String.init)
                ?? "any"
        let records = observedEvidence.isEmpty
            ? "none"
            : observedEvidence
                .map(\.logFields)
                .joined(separator: " | ")
        return "observationActive=\(isObservationActive) "
            + "unmetCondition=phase=\(phase) "
            + "requestGeneration=\(generation) "
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
        _ evidence:
            SpaceFixtureWindowCloseFaultEvidence,
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
            guard !didFulfillScheduledExpectation
            else {
                return
            }
            didFulfillScheduledExpectation = true
            scheduledExpectation?.fulfill()
        case .applied:
            guard !didFulfillAppliedExpectation,
                  requestedPhase == .applied,
                  requestedGeneration
                    == evidence.requestGeneration
            else {
                return
            }
            didFulfillAppliedExpectation = true
            appliedExpectation?.fulfill()
        }
    }

    private func wait(
        for expectation: XCTestExpectation?,
        phase: SpaceFixtureWindowCloseFaultEvidencePhase,
        requestGeneration: Int?,
        timeout: TimeInterval
    ) -> SpaceFixtureWindowCloseFaultEvidence? {
        requestedPhase = phase
        requestedGeneration = requestGeneration
        guard activeObservationGeneration != nil,
              let expectation
        else {
            lastWaitResultDescription = "inactive"
            return nil
        }
        if let evidence = matchingEvidence(
            phase: phase,
            requestGeneration: requestGeneration
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
