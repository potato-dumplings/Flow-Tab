import Foundation
import XCTest

private enum SpaceFixtureWindowCloseFaultAppliedObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let eventWatchdog: TimeInterval = 1
    static let queuePressureTurns = 100
    static let pressureIterations = 200
}

extension FlowTabUITests {
    func testSpaceFixtureWindowCloseFaultAppliedWatchdogPolicyCompatibility() {
        XCTAssertEqual(
            SpaceFixtureWindowCloseFaultObservationPolicy
                .appliedEvidenceWatchdog,
            15
        )
        XCTAssertTrue(
            SpaceFixtureWindowCloseFaultObservationPolicy
                .appliedEvidenceWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            SpaceFixtureWindowCloseFaultObservationPolicy
                .appliedEvidenceWatchdog,
            0
        )
    }

    func testSpaceFixtureWindowCloseFaultUsesMatchingAppliedEvidenceAlreadyObserved() {
        let source =
            ManualSpaceFixtureWindowCloseFaultEvidenceSource()
        let owner = makeWindowCloseFaultObservationOwner(
            source: source
        )
        owner.start()
        defer { owner.cancel() }
        let applied = windowCloseFaultEvidence(
            generation: 21,
            phase: .applied
        )

        source.send(applied)

        XCTAssertEqual(
            owner.waitForApplied(
                requestGeneration: 21,
                timeout:
                    SpaceFixtureWindowCloseFaultAppliedObservationTestPolicy
                        .eventWatchdog
            ),
            applied
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "waitResult=initialReadback"
            )
        )
    }

    func testSpaceFixtureWindowCloseFaultWaitsForMatchingAppliedGeneration() {
        let source =
            ManualSpaceFixtureWindowCloseFaultEvidenceSource()
        let owner = makeWindowCloseFaultObservationOwner(
            source: source
        )
        owner.start()
        defer { owner.cancel() }
        let expected = windowCloseFaultEvidence(
            generation: 23,
            phase: .applied
        )
        DispatchQueue.main.async {
            source.send(
                self.windowCloseFaultEvidence(
                    generation: 22,
                    phase: .applied
                )
            )
            source.send(expected)
            source.send(expected)
        }

        XCTAssertEqual(
            owner.waitForApplied(
                requestGeneration: 23,
                timeout:
                    SpaceFixtureWindowCloseFaultAppliedObservationTestPolicy
                        .eventWatchdog
            ),
            expected
        )
        XCTAssertEqual(owner.observedEvidenceCount, 2)
    }

    func testSpaceFixtureWindowCloseFaultQueuedAppliedDeliveryPreservesResult() {
        let source =
            ManualSpaceFixtureWindowCloseFaultEvidenceSource()
        let owner = makeWindowCloseFaultObservationOwner(
            source: source
        )
        owner.start()
        defer { owner.cancel() }
        let expected = windowCloseFaultEvidence(
            generation: 25,
            phase: .applied
        )
        for _ in
            0..<SpaceFixtureWindowCloseFaultAppliedObservationTestPolicy
                .queuePressureTurns
        {
            DispatchQueue.main.async {}
        }
        DispatchQueue.main.async {
            source.send(expected)
        }

        XCTAssertEqual(
            owner.waitForApplied(
                requestGeneration: 25,
                timeout:
                    SpaceFixtureWindowCloseFaultAppliedObservationTestPolicy
                        .eventWatchdog
            ),
            expected
        )
    }

    func testSpaceFixtureWindowCloseFaultAppliedWatchdogReportsStaleGeneration() {
        let source =
            ManualSpaceFixtureWindowCloseFaultEvidenceSource()
        let owner = makeWindowCloseFaultObservationOwner(
            source: source
        )
        owner.start()
        defer { owner.cancel() }
        source.send(
            windowCloseFaultEvidence(
                generation: 26,
                phase: .applied
            )
        )

        XCTAssertNil(
            owner.waitForApplied(
                requestGeneration: 27,
                timeout:
                    SpaceFixtureWindowCloseFaultAppliedObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "unmetCondition=phase=applied"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "requestGeneration=27"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "waitResult=timedOut"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "generation=26"
            )
        )
    }

    func testSpaceFixtureWindowCloseFaultAppliedWaitRejectsCancellation() {
        let source =
            ManualSpaceFixtureWindowCloseFaultEvidenceSource()
        let owner = makeWindowCloseFaultObservationOwner(
            source: source
        )
        owner.start()

        owner.cancel()
        source.send(
            windowCloseFaultEvidence(
                generation: 29,
                phase: .applied
            )
        )

        XCTAssertNil(
            owner.waitForApplied(
                requestGeneration: 29,
                timeout:
                    SpaceFixtureWindowCloseFaultAppliedObservationTestPolicy
                        .eventWatchdog
            )
        )
        XCTAssertFalse(owner.isObservationActive)
        XCTAssertEqual(owner.observedEvidenceCount, 0)
        XCTAssertEqual(source.cancellationCount, 1)
    }

    func testSpaceFixtureWindowCloseFaultFiltersAppliedGenerationsUnderPressure() {
        for iteration in
            0..<SpaceFixtureWindowCloseFaultAppliedObservationTestPolicy
                .pressureIterations
        {
            let source =
                ManualSpaceFixtureWindowCloseFaultEvidenceSource()
            let owner = makeWindowCloseFaultObservationOwner(
                source: source
            )
            let expectedGeneration = iteration * 2 + 2
            let expected = windowCloseFaultEvidence(
                generation: expectedGeneration,
                phase: .applied
            )
            owner.start()
            DispatchQueue.main.async {
                source.send(
                    self.windowCloseFaultEvidence(
                        generation:
                            expectedGeneration - 1,
                        phase: .applied
                    )
                )
                source.send(expected)
            }

            XCTAssertEqual(
                owner.waitForApplied(
                    requestGeneration:
                        expectedGeneration,
                    timeout:
                        SpaceFixtureWindowCloseFaultAppliedObservationTestPolicy
                            .eventWatchdog
                ),
                expected
            )
            owner.cancel()
            XCTAssertEqual(source.cancellationCount, 1)
        }
    }
}
