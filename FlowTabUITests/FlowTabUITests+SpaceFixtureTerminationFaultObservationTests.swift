import Foundation
import XCTest

private enum SpaceFixtureTerminationFaultObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let eventWatchdog: TimeInterval = 1
    static let pressureIterations = 200
}

final class ManualSpaceFixtureTerminationFaultEvidenceSource {
    private(set) var registrations:
        [(SpaceFixtureTerminationFaultEvidence) -> Void] = []
    private var activeRegistrationIndices: Set<Int> = []
    private(set) var cancellationCount = 0

    func register(
        _ callback:
            @escaping (SpaceFixtureTerminationFaultEvidence) -> Void
    ) -> FlowTabUITestObservationCancellation? {
        let index = registrations.count
        registrations.append(callback)
        activeRegistrationIndices.insert(index)
        return FlowTabUITestObservationCancellation {
            [weak self] in
            guard let self,
                  activeRegistrationIndices.remove(index)
                    != nil
            else {
                return
            }
            cancellationCount += 1
        }
    }

    func send(
        _ evidence: SpaceFixtureTerminationFaultEvidence
    ) {
        for index in activeRegistrationIndices.sorted() {
            registrations[index](evidence)
        }
    }

    func send(
        _ evidence: SpaceFixtureTerminationFaultEvidence,
        registrationAt index: Int
    ) {
        registrations[index](evidence)
    }
}

extension FlowTabUITests {
    func testSpaceFixtureTerminationFaultScheduledWatchdogPolicyCompatibility() {
        let watchdog =
            SpaceFixtureTerminationFaultObservationPolicy
                .scheduledEvidenceWatchdog
        XCTAssertEqual(watchdog, 8)
        XCTAssertTrue(watchdog.isFinite && watchdog > 0)
    }

    func testSpaceFixtureTerminationFaultUsesScheduledEvidenceAlreadyObserved() {
        let source =
            ManualSpaceFixtureTerminationFaultEvidenceSource()
        let owner = makeTerminationFaultObservationOwner(
            source: source
        )
        owner.start()
        defer { owner.cancel() }
        let scheduled = terminationFaultEvidence(
            generation: 7,
            phase: .scheduled
        )

        source.send(scheduled)

        XCTAssertEqual(
            owner.waitForScheduled(
                timeout:
                    SpaceFixtureTerminationFaultObservationTestPolicy
                        .eventWatchdog
            ),
            scheduled
        )
        XCTAssertEqual(owner.observedEvidenceCount, 1)
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "waitResult=initialReadback"
            )
        )
    }

    func testSpaceFixtureTerminationFaultWaitsForScheduledAfterOutOfOrderEvidence() {
        let source =
            ManualSpaceFixtureTerminationFaultEvidenceSource()
        let owner = makeTerminationFaultObservationOwner(
            source: source
        )
        owner.start()
        defer { owner.cancel() }
        let scheduled = terminationFaultEvidence(
            generation: 9,
            phase: .scheduled
        )
        let applied = terminationFaultEvidence(
            generation: 9,
            phase: .applied
        )
        DispatchQueue.main.async {
            source.send(applied)
            source.send(scheduled)
            source.send(scheduled)
        }

        XCTAssertEqual(
            owner.waitForScheduled(
                timeout:
                    SpaceFixtureTerminationFaultObservationTestPolicy
                        .eventWatchdog
            ),
            scheduled
        )
        XCTAssertEqual(owner.observedEvidenceCount, 2)
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "waitResult=completed"
            )
        )
    }

    func testSpaceFixtureTerminationFaultCancellationRejectsLaterScheduledEvidence() {
        let source =
            ManualSpaceFixtureTerminationFaultEvidenceSource()
        let owner = makeTerminationFaultObservationOwner(
            source: source
        )
        owner.start()
        XCTAssertTrue(owner.isObservationActive)

        owner.cancel()
        source.send(
            terminationFaultEvidence(
                generation: 11,
                phase: .scheduled
            )
        )

        XCTAssertFalse(owner.isObservationActive)
        XCTAssertNil(
            owner.waitForScheduled(
                timeout:
                    SpaceFixtureTerminationFaultObservationTestPolicy
                        .eventWatchdog
            )
        )
        XCTAssertEqual(owner.observedEvidenceCount, 0)
        XCTAssertEqual(source.cancellationCount, 1)
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "waitResult=inactive"
            )
        )
    }

    func testSpaceFixtureTerminationFaultScheduledWatchdogReportsLastEvidence() {
        let source =
            ManualSpaceFixtureTerminationFaultEvidenceSource()
        let owner = makeTerminationFaultObservationOwner(
            source: source
        )
        owner.start()
        defer { owner.cancel() }
        source.send(
            terminationFaultEvidence(
                generation: 13,
                phase: .applied
            )
        )

        XCTAssertNil(
            owner.waitForScheduled(
                timeout:
                    SpaceFixtureTerminationFaultObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "unmetCondition=phase=scheduled"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "waitResult=timedOut"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "phase=applied"
            )
        )
    }

    func testSpaceFixtureTerminationFaultRejectsCancelledGenerationsUnderPressure() {
        for iteration in
            0..<SpaceFixtureTerminationFaultObservationTestPolicy
                .pressureIterations
        {
            let source =
                ManualSpaceFixtureTerminationFaultEvidenceSource()
            let owner = makeTerminationFaultObservationOwner(
                source: source
            )
            let scheduled = terminationFaultEvidence(
                generation: iteration + 1,
                phase: .scheduled
            )
            owner.start()
            owner.cancel()
            owner.start()

            source.send(scheduled, registrationAt: 0)
            XCTAssertEqual(
                owner.observedEvidenceCount,
                0,
                "iteration=\(iteration)"
            )
            source.send(scheduled, registrationAt: 1)
            XCTAssertEqual(
                owner.waitForScheduled(
                    timeout:
                        SpaceFixtureTerminationFaultObservationTestPolicy
                            .eventWatchdog
                ),
                scheduled,
                "iteration=\(iteration)"
            )
            XCTAssertEqual(
                owner.observedEvidenceCount,
                1,
                "iteration=\(iteration)"
            )
            owner.cancel()
            XCTAssertEqual(
                source.cancellationCount,
                2,
                "iteration=\(iteration)"
            )
        }
    }

    func makeTerminationFaultObservationOwner(
        source:
            ManualSpaceFixtureTerminationFaultEvidenceSource
    ) -> SpaceFixtureTerminationFaultObservationOwner {
        SpaceFixtureTerminationFaultObservationOwner(
            route:
                SpaceFixtureTerminationFaultUITestRoute(
                    notificationName:
                        Notification.Name(
                            "termination-fault-evidence"
                        )
                ),
            evidenceRegistration: source.register
        )
    }

    func terminationFaultEvidence(
        generation: Int,
        phase: SpaceFixtureTerminationFaultEvidencePhase
    ) -> SpaceFixtureTerminationFaultEvidence {
        SpaceFixtureTerminationFaultEvidence(
            requestGeneration: generation,
            phase: phase,
            source: .terminationSignal,
            delayMilliseconds: 2_400,
            identity:
                SpaceFixtureTerminationFaultIdentity(
                    bundleIdentifier:
                        "io.github.flowtab.fixture",
                    processIdentifier: 4_321
                )
        )
    }
}
