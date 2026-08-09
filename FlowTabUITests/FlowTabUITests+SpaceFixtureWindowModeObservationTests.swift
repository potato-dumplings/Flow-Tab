import Foundation
import XCTest

private enum SpaceFixtureWindowModeObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testWindowModeObservationPolicyPreservesFiveSecondCompatibilityBound() {
        XCTAssertEqual(
            SpaceFixtureWindowModeUITestPolicy
                .publicationWatchdog,
            5
        )
    }

    func testWindowModeObservationAcceptsInitialExactEvidence() {
        let owner = SpaceFixtureWindowModeObservationOwner(
            expectedIdentifier:
                "flowtab.spacefixture.window.mode.1",
            expectedLabel: "Standard Window",
            observationRegistration: nil,
            readback: {
                self.windowModeSnapshot(
                    index: 1,
                    label: "Standard Window"
                )
            }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
    }

    func testWindowModeObservationRequiresExactPostBaselineEvidence() {
        var snapshot = SpaceFixtureWindowModeSnapshot(
            identifier: nil,
            exists: false,
            label: nil
        )
        var readback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner = SpaceFixtureWindowModeObservationOwner(
            expectedIdentifier:
                "flowtab.spacefixture.window.mode.2",
            expectedLabel: "Fullscreen Target",
            observationRegistration: { callback in
                readback = callback
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: { snapshot }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.latestEvidence?.source,
            .initialReadback
        )
        XCTAssertEqual(owner.latestEvidence?.value.exists, false)
        XCTAssertNil(owner.resolvedEvidence)

        for _ in 0..<20 {
            snapshot = self.windowModeSnapshot(
                index: 1,
                label: "Fullscreen Target"
            )
            readback?(.scheduledReadback)
            snapshot = self.windowModeSnapshot(
                index: 2,
                label: "Standard Window"
            )
            readback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = windowModeSnapshot(
            index: 2,
            label: "Fullscreen Target"
        )
        readback?(.triggerReadback)
        readback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testWindowModeObservationRejectsStaleCallbacksUnderPressure() {
        for _ in
            0..<SpaceFixtureWindowModeObservationTestPolicy
                .pressureIterations
        {
            var snapshot = SpaceFixtureWindowModeSnapshot(
                identifier: nil,
                exists: false,
                label: nil
            )
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner = SpaceFixtureWindowModeObservationOwner(
                expectedIdentifier:
                    "flowtab.spacefixture.window.mode.2",
                expectedLabel: "Fullscreen Target",
                observationRegistration: { callback in
                    callbacks.append(callback)
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
            owner.start()
            let staleReadback = callbacks[0]
            owner.cancel()
            owner.start()

            snapshot = windowModeSnapshot(
                index: 2,
                label: "Fullscreen Target"
            )
            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            callbacks[1](.scheduledReadback)
            callbacks[1](.triggerReadback)
            XCTAssertEqual(owner.resolvedEvidence?.generation, 2)
            owner.cancel()
        }
    }

    func testWindowModeObservationWatchdogReportsFinalReadback() {
        let owner = SpaceFixtureWindowModeObservationOwner(
            expectedIdentifier:
                "flowtab.spacefixture.window.mode.2",
            expectedLabel: "Fullscreen Target",
            observationRegistration: nil,
            readback: {
                self.windowModeSnapshot(
                    index: 2,
                    label: "Standard Window"
                )
            }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    SpaceFixtureWindowModeObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "expectedIdentifier=flowtab.spacefixture.window.mode.2"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "expectedLabel=Fullscreen Target"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "exists=true label=Standard Window"
            )
        )
    }

    private func windowModeSnapshot(
        index: Int,
        label: String
    ) -> SpaceFixtureWindowModeSnapshot {
        SpaceFixtureWindowModeSnapshot(
            identifier:
                "flowtab.spacefixture.window.mode.\(index)",
            exists: true,
            label: label
        )
    }
}
