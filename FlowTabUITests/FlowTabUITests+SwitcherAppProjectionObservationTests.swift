import Foundation
import XCTest

private enum FlowTabUITestSwitcherAppProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSwitcherAppProjectionParsesBundleAndWindowCount() {
        let entry = FlowTabUITestSwitcherAppProjectionEntry(
            rawValue: "com.example.browser:2"
        )
        XCTAssertEqual(
            entry.rawValue,
            "com.example.browser:2"
        )
        XCTAssertEqual(
            entry.bundleIdentifier,
            "com.example.browser"
        )
        XCTAssertEqual(entry.windowCount, 2)
        XCTAssertNil(
            FlowTabUITestSwitcherAppProjectionEntry(
                rawValue: "com.example.browser:unknown"
            ).windowCount
        )
    }

    func testSwitcherAppProjectionAcceptsMatchingInitialEntry() {
        var order: [String] = []
        let owner =
            FlowTabUITestSwitcherAppProjectionObservationOwner(
                expectation:
                    .exactEntry("com.example.browser:2"),
                observationRegistration: { _ in
                    order.append("register")
                    return FlowTabUITestObservationCancellation {
                        order.append("cancel")
                    }
                },
                readback: {
                    order.append("readback")
                    return self.switcherAppProjectionTestSnapshot(
                        ["com.example.browser:2"]
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
        XCTAssertEqual(
            order,
            ["register", "readback", "cancel"]
        )
    }

    func testSwitcherAppProjectionWaitsForBundleEntry() {
        var entries = ["com.example.mail:1"]
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestSwitcherAppProjectionObservationOwner(
                expectation:
                    .bundleIdentifier("com.example.browser"),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    self.switcherAppProjectionTestSnapshot(
                        entries
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        for _ in 0..<5 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }
        entries.append("com.example.browser:7")
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
    }

    func testSwitcherAppProjectionRejectsWrongExactCountEntry() {
        var entries = ["com.example.browser:3"]
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestSwitcherAppProjectionObservationOwner(
                expectation:
                    .exactEntry("com.example.browser:2"),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    self.switcherAppProjectionTestSnapshot(
                        entries
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }
        XCTAssertNil(owner.resolvedEvidence)

        entries = ["com.example.browser:2"]
        scheduledReadback?(.scheduledReadback)
        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
    }

    func testSwitcherAppProjectionRejectsStaleReadbacksUnderPressure() {
        for _ in 0..<FlowTabUITestSwitcherAppProjectionTestPolicy
            .pressureIterations
        {
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var entries: [String] = []
            let owner =
                FlowTabUITestSwitcherAppProjectionObservationOwner(
                    expectation:
                        .bundleIdentifier(
                            "com.example.browser"
                        ),
                    observationRegistration: { callback in
                        callbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: {
                        self.switcherAppProjectionTestSnapshot(
                            entries
                        )
                    }
                )
            owner.start()
            let staleReadback = callbacks[0]
            owner.cancel()
            owner.start()
            entries = ["com.example.browser:2"]

            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            callbacks[1](.scheduledReadback)
            callbacks[1](.scheduledReadback)
            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                2
            )
            owner.cancel()
        }
    }

    func testSwitcherAppProjectionWatchdogReportsFinalEntries() {
        let owner =
            FlowTabUITestSwitcherAppProjectionObservationOwner(
                expectation:
                    .exactEntry("com.example.browser:2"),
                observationRegistration: nil,
                readback: {
                    self.switcherAppProjectionTestSnapshot(
                        ["com.example.browser:1"]
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherAppProjectionTestPolicy
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
                "com.example.browser:1"
            )
        )
    }

    private func switcherAppProjectionTestSnapshot(
        _ rawEntries: [String]
    ) -> FlowTabUITestSwitcherAppProjectionSnapshot {
        FlowTabUITestSwitcherAppProjectionSnapshot(
            identifier: "switcher-summary",
            exists: true,
            rawValue: rawEntries.joined(separator: "|"),
            entries: rawEntries.map {
                FlowTabUITestSwitcherAppProjectionEntry(
                    rawValue: $0
                )
            }
        )
    }
}
