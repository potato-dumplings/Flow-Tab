import Foundation
import XCTest

enum SpaceFixtureWindowCloseFaultObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let eventWatchdog: TimeInterval = 1
    static let pressureIterations = 200
}

final class ManualSpaceFixtureWindowCloseFaultEvidenceSource {
    private(set) var registrations:
        [(SpaceFixtureWindowCloseFaultEvidence) -> Void] = []
    private var activeRegistrationIndices: Set<Int> = []
    private(set) var cancellationCount = 0

    func register(
        _ callback:
            @escaping (SpaceFixtureWindowCloseFaultEvidence) -> Void
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
        _ evidence: SpaceFixtureWindowCloseFaultEvidence
    ) {
        for index in activeRegistrationIndices.sorted() {
            registrations[index](evidence)
        }
    }

    func send(
        _ evidence: SpaceFixtureWindowCloseFaultEvidence,
        registrationAt index: Int
    ) {
        registrations[index](evidence)
    }
}

extension FlowTabUITests {
    func testSpaceFixtureWindowCloseFaultScheduledWatchdogPolicyCompatibility() {
        XCTAssertEqual(
            SpaceFixtureWindowCloseFaultObservationPolicy
                .scheduledEvidenceWatchdog,
            8
        )
        XCTAssertTrue(
            SpaceFixtureWindowCloseFaultObservationPolicy
                .scheduledEvidenceWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            SpaceFixtureWindowCloseFaultObservationPolicy
                .scheduledEvidenceWatchdog,
            0
        )
    }

    func testSpaceFixtureWindowCloseFaultUsesScheduledEvidenceAlreadyObserved() {
        let source =
            ManualSpaceFixtureWindowCloseFaultEvidenceSource()
        let owner =
            makeWindowCloseFaultObservationOwner(
                source: source
            )
        owner.start()
        defer { owner.cancel() }
        let scheduled = windowCloseFaultEvidence(
            generation: 7,
            phase: .scheduled
        )

        source.send(scheduled)

        XCTAssertEqual(
            owner.waitForScheduled(
                timeout:
                    SpaceFixtureWindowCloseFaultObservationTestPolicy
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

    func testSpaceFixtureWindowCloseFaultWaitsForScheduledAfterOutOfOrderEvidence() {
        let source =
            ManualSpaceFixtureWindowCloseFaultEvidenceSource()
        let owner =
            makeWindowCloseFaultObservationOwner(
                source: source
            )
        owner.start()
        defer { owner.cancel() }
        let scheduled = windowCloseFaultEvidence(
            generation: 9,
            phase: .scheduled
        )
        let applied = windowCloseFaultEvidence(
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
                    SpaceFixtureWindowCloseFaultObservationTestPolicy
                        .eventWatchdog
            ),
            scheduled
        )
        XCTAssertEqual(owner.observedEvidenceCount, 2)
    }

    func testSpaceFixtureWindowCloseFaultCancellationRejectsLaterScheduledEvidence() {
        let source =
            ManualSpaceFixtureWindowCloseFaultEvidenceSource()
        let owner =
            makeWindowCloseFaultObservationOwner(
                source: source
            )
        owner.start()
        XCTAssertTrue(owner.isObservationActive)

        owner.cancel()
        source.send(
            windowCloseFaultEvidence(
                generation: 11,
                phase: .scheduled
            )
        )

        XCTAssertFalse(owner.isObservationActive)
        XCTAssertNil(
            owner.waitForScheduled(
                timeout:
                    SpaceFixtureWindowCloseFaultObservationTestPolicy
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

    func testSpaceFixtureWindowCloseFaultScheduledWatchdogReportsLastEvidence() {
        let source =
            ManualSpaceFixtureWindowCloseFaultEvidenceSource()
        let owner =
            makeWindowCloseFaultObservationOwner(
                source: source
            )
        owner.start()
        defer { owner.cancel() }
        source.send(
            windowCloseFaultEvidence(
                generation: 13,
                phase: .applied
            )
        )

        XCTAssertNil(
            owner.waitForScheduled(
                timeout:
                    SpaceFixtureWindowCloseFaultObservationTestPolicy
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

    func testSpaceFixtureWindowCloseFaultRejectsCancelledGenerationsUnderPressure() {
        for iteration in
            0..<SpaceFixtureWindowCloseFaultObservationTestPolicy
                .pressureIterations
        {
            let source =
                ManualSpaceFixtureWindowCloseFaultEvidenceSource()
            let owner =
                makeWindowCloseFaultObservationOwner(
                    source: source
                )
            let scheduled = windowCloseFaultEvidence(
                generation: iteration + 1,
                phase: .scheduled
            )
            owner.start()
            owner.cancel()
            owner.start()

            source.send(
                scheduled,
                registrationAt: 0
            )
            XCTAssertEqual(owner.observedEvidenceCount, 0)
            source.send(
                scheduled,
                registrationAt: 1
            )
            XCTAssertEqual(
                owner.waitForScheduled(
                    timeout:
                        SpaceFixtureWindowCloseFaultObservationTestPolicy
                            .eventWatchdog
                ),
                scheduled
            )
            XCTAssertEqual(owner.observedEvidenceCount, 1)
            owner.cancel()
            XCTAssertEqual(source.cancellationCount, 2)
        }
    }

    func makeWindowCloseFaultObservationOwner(
        source:
            ManualSpaceFixtureWindowCloseFaultEvidenceSource
    ) -> SpaceFixtureWindowCloseFaultObservationOwner {
        SpaceFixtureWindowCloseFaultObservationOwner(
            route:
                SpaceFixtureWindowCloseFaultUITestRoute(
                    evidenceNotificationName:
                        Notification.Name(
                            "window-close-evidence"
                        ),
                    triggerNotificationName:
                        Notification.Name(
                            "window-close-trigger"
                        )
                ),
            evidenceRegistration: source.register
        )
    }

    func windowCloseFaultEvidence(
        generation: Int,
        phase: SpaceFixtureWindowCloseFaultEvidencePhase
    ) -> SpaceFixtureWindowCloseFaultEvidence {
        let isApplied = phase == .applied
        return SpaceFixtureWindowCloseFaultEvidence(
            requestGeneration: generation,
            phase: phase,
            source:
                isApplied
                    ? .closeActionReadback
                    : .initialReadback,
            delayMilliseconds: 250,
            awaitsExplicitTrigger: true,
            identity:
                SpaceFixtureWindowCloseFaultIdentity(
                    bundleIdentifier:
                        "io.github.flowtab.fixture",
                    processIdentifier: 4_321
                ),
            snapshot:
                SpaceFixtureWindowCloseTopologySnapshot(
                    targetWindowPlanIndex: 2,
                    targetWindowNumber: 902,
                    targetWindowIsVisible: !isApplied,
                    targetCGWindowIsOnScreen: !isApplied,
                    remainingWindowPlanIndices:
                        isApplied ? [1] : [1, 2]
                )
        )
    }
}
