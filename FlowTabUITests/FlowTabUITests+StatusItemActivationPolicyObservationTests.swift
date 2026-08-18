import Foundation
import XCTest

private enum StatusItemActivationPolicyObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let delayedReadbacks = 20
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testStatusItemActivationPolicyRuleRequiresExactOrderedMarkers() {
        XCTAssertEqual(
            StatusItemActivationPolicyUITestPolicy.transitionWatchdog,
            8
        )
        let regular =
            StatusItemActivationPolicyUITestPolicy
                .temporaryRegularMarker
        let accessory =
            StatusItemActivationPolicyUITestPolicy
                .stableAccessoryMarker

        XCTAssertTrue(
            StatusItemActivationPolicyObservationRule.isSatisfied(
                by: statusItemActivationPolicySnapshot(
                    contents: "\(regular)\n\(accessory)"
                )
            )
        )
        XCTAssertFalse(
            StatusItemActivationPolicyObservationRule.isSatisfied(
                by: statusItemActivationPolicySnapshot(
                    contents: "\(accessory)\n\(regular)"
                )
            )
        )
        XCTAssertFalse(
            StatusItemActivationPolicyObservationRule.isSatisfied(
                by: statusItemActivationPolicySnapshot(
                    contents: regular
                )
            )
        )
    }

    func testStatusItemActivationPolicyObserverAcceptsInitialEvidence() {
        let owner = StatusItemActivationPolicyObservationOwner(
            observationRegistration: nil,
            readback: {
                self.statusItemActivationPolicyCompleteSnapshot()
            }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
    }

    func testStatusItemActivationPolicyObserverUsesOrderedEventAndCancels() {
        let regular =
            StatusItemActivationPolicyUITestPolicy
                .temporaryRegularMarker
        let accessory =
            StatusItemActivationPolicyUITestPolicy
                .stableAccessoryMarker
        var snapshot = statusItemActivationPolicySnapshot(
            contents: ""
        )
        var readback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner = StatusItemActivationPolicyObservationOwner(
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

        for index in
            0..<StatusItemActivationPolicyObservationTestPolicy
                .delayedReadbacks
        {
            let partialContents = index.isMultiple(of: 2)
                ? regular
                : "\(accessory)\n\(regular)"
            snapshot = statusItemActivationPolicySnapshot(
                fileEventGeneration: UInt64(index + 2),
                contents: partialContents
            )
            readback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = statusItemActivationPolicyCompleteSnapshot(
            fileEventGeneration: 30
        )
        readback?(.notificationReadback)
        readback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .notificationReadback
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testStatusItemActivationPolicyObserverClosesTriggerReadbackRace() {
        var snapshot = statusItemActivationPolicySnapshot(
            contents: ""
        )
        let owner = StatusItemActivationPolicyObservationOwner(
            observationRegistration: nil,
            readback: { snapshot }
        )
        owner.start()
        defer { owner.cancel() }

        snapshot = statusItemActivationPolicyCompleteSnapshot(
            fileEventGeneration: 2
        )
        owner.requestReadback(source: .triggerReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
    }

    func testStatusItemActivationPolicyObserverRejectsStaleGenerationsUnderPressure() {
        for _ in
            0..<StatusItemActivationPolicyObservationTestPolicy
                .pressureIterations
        {
            var snapshot = statusItemActivationPolicySnapshot(
                contents: ""
            )
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner = StatusItemActivationPolicyObservationOwner(
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

            snapshot = statusItemActivationPolicyCompleteSnapshot(
                fileEventGeneration: 2
            )
            staleReadback(.notificationReadback)
            XCTAssertNil(owner.resolvedEvidence)
            callbacks[1](.notificationReadback)
            callbacks[1](.scheduledReadback)
            XCTAssertEqual(owner.resolvedEvidence?.generation, 2)
            owner.cancel()
        }
    }

    func testStatusItemActivationPolicyWatchdogReportsFinalEvidence() {
        let regular =
            StatusItemActivationPolicyUITestPolicy
                .temporaryRegularMarker
        let owner = StatusItemActivationPolicyObservationOwner(
            observationRegistration: nil,
            readback: {
                self.statusItemActivationPolicySnapshot(
                    fileEventGeneration: 9,
                    contents: regular
                )
            }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    StatusItemActivationPolicyObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                StatusItemActivationPolicyUITestPolicy
                    .stableAccessoryMarker
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "baselineFileEventGeneration=1"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "fileEventGeneration=9"
            )
        )
    }

    private func statusItemActivationPolicyCompleteSnapshot(
        fileEventGeneration: UInt64 = 2
    ) -> FlowTabUITestRuntimeLogSnapshot {
        statusItemActivationPolicySnapshot(
            fileEventGeneration: fileEventGeneration,
            contents:
                StatusItemActivationPolicyUITestPolicy
                    .temporaryRegularMarker
                + "\n"
                + StatusItemActivationPolicyUITestPolicy
                    .stableAccessoryMarker
        )
    }

    private func statusItemActivationPolicySnapshot(
        baselineFileEventGeneration: UInt64 = 1,
        fileEventGeneration: UInt64 = 1,
        contents: String
    ) -> FlowTabUITestRuntimeLogSnapshot {
        FlowTabUITestRuntimeLogSnapshot(
            baselineFileEventGeneration:
                baselineFileEventGeneration,
            fileEventGeneration: fileEventGeneration,
            contents: contents
        )
    }
}
