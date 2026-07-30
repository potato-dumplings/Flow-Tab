import Foundation
import XCTest

private enum FlowTabUITestAverageLuminanceTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testAverageLuminanceObserverAcceptsMatchingInitialReadback() {
        var order: [String] = []
        let owner =
            FlowTabUITestAverageLuminanceObservationOwner(
                expectedDescription: "greater than 0.45",
                observationRegistration: { _ in
                    order.append("register")
                    return FlowTabUITestObservationCancellation {
                        order.append("cancel")
                    }
                },
                readback: {
                    order.append("readback")
                    return self.averageLuminanceTestSnapshot(
                        luminance: 0.8
                    )
                },
                isSatisfied: { $0 > 0.45 }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.luminance,
            0.8
        )
        XCTAssertEqual(
            order,
            ["register", "readback", "cancel"]
        )
    }

    func testAverageLuminanceObserverRequiresPostTriggerEvidence() {
        var acceptsEvidence = false
        var cancellationCount = 0
        let owner =
            FlowTabUITestAverageLuminanceObservationOwner(
                expectedDescription: "greater than 0.45",
                acceptsEvidence: {
                    acceptsEvidence
                },
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    self.averageLuminanceTestSnapshot(
                        luminance: 0.8
                    )
                },
                isSatisfied: { $0 > 0.45 }
            )
        owner.start()
        defer { owner.cancel() }
        XCTAssertNil(owner.resolvedEvidence)

        acceptsEvidence = true
        owner.requestReadback(source: .triggerReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testAverageLuminanceScheduledReadbacksOnlyDelayResolution() {
        var readback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var luminance: CGFloat = 0.2
        let owner =
            FlowTabUITestAverageLuminanceObservationOwner(
                expectedDescription: "greater than 0.45",
                observationRegistration: { callback in
                    readback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    self.averageLuminanceTestSnapshot(
                        luminance: luminance
                    )
                },
                isSatisfied: { $0 > 0.45 }
            )
        owner.start()
        defer { owner.cancel() }

        for _ in 0..<5 {
            readback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }
        luminance = 0.8
        readback?(.scheduledReadback)

        XCTAssertEqual(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestAverageLuminanceTestPolicy
                        .watchdog
            )?.source,
            .scheduledReadback
        )
    }

    func testAverageLuminanceObserverRejectsStaleEventsUnderPressure() {
        for _ in 0..<FlowTabUITestAverageLuminanceTestPolicy
            .pressureIterations
        {
            var readbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var luminance: CGFloat = 0.2
            let owner =
                FlowTabUITestAverageLuminanceObservationOwner(
                    expectedDescription: "greater than 0.45",
                    observationRegistration: { callback in
                        readbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: {
                        self.averageLuminanceTestSnapshot(
                            luminance: luminance
                        )
                    },
                    isSatisfied: { $0 > 0.45 }
                )

            owner.start()
            let staleReadback = readbacks[0]
            owner.cancel()
            owner.start()
            luminance = 0.8

            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            readbacks[1](.scheduledReadback)
            readbacks[1](.scheduledReadback)
            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                2
            )
            owner.cancel()
        }
    }

    func testAverageLuminanceWatchdogReportsFinalReadback() {
        var readbackCount = 0
        let owner =
            FlowTabUITestAverageLuminanceObservationOwner(
                expectedDescription: "greater than 0.45",
                observationRegistration: nil,
                readback: {
                    defer { readbackCount += 1 }
                    return self.averageLuminanceTestSnapshot(
                        luminance:
                            readbackCount == 0
                                ? 0.2
                                : 0.3
                    )
                },
                isSatisfied: { $0 > 0.45 }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestAverageLuminanceTestPolicy
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
                "identifier=settings-content"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "luminance=0.3"
            )
        )
    }

    private func averageLuminanceTestSnapshot(
        luminance: CGFloat?
    ) -> FlowTabUITestAverageLuminanceSnapshot {
        FlowTabUITestAverageLuminanceSnapshot(
            identifier: "settings-content",
            exists: true,
            luminance: luminance
        )
    }
}
