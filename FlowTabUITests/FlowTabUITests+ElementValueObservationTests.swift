import Foundation
import XCTest

private enum FlowTabUITestElementValueObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
}

extension FlowTabUITests {
    func testElementValueObserverRejectsMatchingBaselineUntilTriggerCompletes() {
        var triggerCompleted = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner = FlowTabUITestElementValueObservationOwner(
            expectedDescription: "equals 1.23",
            acceptsEvidence: {
                triggerCompleted
            },
            observationRegistration: { callback in
                scheduledReadback = callback
                return FlowTabUITestObservationCancellation {}
            },
            readback: {
                FlowTabUITestElementValueSnapshot(
                    identifier: "delay",
                    exists: true,
                    value: "1.23"
                )
            },
            isSatisfied: { $0 == "1.23" }
        )
        owner.start()
        defer { owner.cancel() }
        XCTAssertNil(owner.resolvedEvidence)

        triggerCompleted = true
        scheduledReadback?(.scheduledReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestElementValueObservationTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(evidence?.value.value, "1.23")
    }

    func testElementValueObserverUsesInitialExactValueEvidence() {
        let owner = FlowTabUITestElementValueObservationOwner(
            expectedDescription: "equals dark",
            observationRegistration: nil,
            readback: {
                FlowTabUITestElementValueSnapshot(
                    identifier: "theme",
                    exists: true,
                    value: "dark"
                )
            },
            isSatisfied: { $0 == "dark" }
        )
        owner.start()
        defer { owner.cancel() }

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestElementValueObservationTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .initialReadback)
        XCTAssertEqual(evidence?.value.identifier, "theme")
        XCTAssertEqual(evidence?.value.value, "dark")
    }

    func testElementValueObserverUsesPreinstalledPrefixReadbackAndReportsWatchdogEvidence() {
        var readback = FlowTabUITestElementValueSnapshot(
            identifier: "delay",
            exists: false,
            value: nil
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner = FlowTabUITestElementValueObservationOwner(
            expectedDescription: "hasPrefix 1.23",
            observationRegistration: { callback in
                scheduledReadback = callback
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: { readback },
            isSatisfied: { $0.hasPrefix("1.23") }
        )
        owner.start()

        readback = FlowTabUITestElementValueSnapshot(
            identifier: "delay",
            exists: true,
            value: "1.2345"
        )
        scheduledReadback?(.scheduledReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestElementValueObservationTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(evidence?.value.value, "1.2345")
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()

        let watchdogOwner =
            FlowTabUITestElementValueObservationOwner(
                expectedDescription: "equals expected",
                observationRegistration: nil,
                readback: {
                    FlowTabUITestElementValueSnapshot(
                        identifier: "control",
                        exists: true,
                        value: "actual"
                    )
                },
                isSatisfied: { $0 == "expected" }
            )
        watchdogOwner.start()
        defer { watchdogOwner.cancel() }

        XCTAssertNil(
            watchdogOwner.waitForResolution(
                timeout:
                    FlowTabUITestElementValueObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            watchdogOwner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            watchdogOwner.diagnosticSummary.contains(
                "expected{equals expected}"
            )
        )
        XCTAssertTrue(
            watchdogOwner.diagnosticSummary.contains(
                "actual=actual"
            )
        )
    }
}
