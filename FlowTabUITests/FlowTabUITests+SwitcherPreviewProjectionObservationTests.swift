import Foundation
import XCTest

private enum FlowTabUITestSwitcherPreviewProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSwitcherPreviewProjectionParsesPublishedTitles() {
        XCTAssertEqual(
            switcherPreviewProjectionTestSnapshot(
                "com.example.browser::Primary|Secondary|Primary"
            ).titles,
            ["Primary", "Secondary", "Primary"]
        )
        XCTAssertTrue(
            switcherPreviewProjectionTestSnapshot(
                "inactive"
            ).titles.isEmpty
        )
        XCTAssertTrue(
            switcherPreviewProjectionTestSnapshot(
                "missing-separator"
            ).titles.isEmpty
        )
    }

    func testSwitcherPreviewProjectionReadsAtomicDiagnostics() {
        let rawValue =
            "selected=com.example.browser;"
            + "mode=windowCycle(com.example.browser);"
            + "preview=com.example.browser::Primary|Secondary"
        let snapshot =
            FlowTabUITestSwitcherPreviewProjectionSnapshot(
                diagnostics:
                    FlowTabUITestSwitcherDiagnosticsSnapshot(
                        identifier: "switcher-summary",
                        exists: true,
                        rawValue: rawValue,
                        values: [
                            "selected": "com.example.browser",
                            "mode":
                                "windowCycle(com.example.browser)",
                            "preview":
                                "com.example.browser::Primary|Secondary",
                        ]
                    )
            )

        XCTAssertEqual(snapshot.rawValue, rawValue)
        XCTAssertEqual(
            snapshot.selectedBundleIdentifier,
            "com.example.browser"
        )
        XCTAssertEqual(
            snapshot.previewBundleIdentifier,
            "com.example.browser"
        )
        XCTAssertEqual(
            snapshot.titles,
            ["Primary", "Secondary"]
        )
    }

    func testSwitcherPreviewProjectionAcceptsMatchingInitialTitles() {
        var order: [String] = []
        let owner =
            FlowTabUITestSwitcherPreviewProjectionObservationOwner(
                expectation:
                    .exactTitles(["Primary", "Secondary"]),
                observationRegistration: { _ in
                    order.append("register")
                    return FlowTabUITestObservationCancellation {
                        order.append("cancel")
                    }
                },
                readback: {
                    order.append("readback")
                    return self
                        .switcherPreviewProjectionTestSnapshot(
                            "com.example.browser::Primary|Secondary"
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

    func testSwitcherPreviewProjectionWaitsForExactTitles() {
        var previewValue =
            "com.example.browser::Primary"
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestSwitcherPreviewProjectionObservationOwner(
                expectation:
                    .exactTitles(["Primary", "Secondary"]),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    self.switcherPreviewProjectionTestSnapshot(
                        previewValue
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        for _ in 0..<5 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }
        previewValue =
            "com.example.browser::Secondary|Primary"
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
    }

    func testSwitcherPreviewProjectionRequiresExactTitleCount() {
        let expectation =
            FlowTabUITestSwitcherPreviewProjectionExpectation
                .exactTitleCount(
                    titles: ["Document"],
                    count: 2
                )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherPreviewProjectionTestSnapshot(
                    "com.example.browser::Document"
                )
            )
        )
        XCTAssertTrue(
            expectation.isSatisfied(
                by: switcherPreviewProjectionTestSnapshot(
                    "com.example.browser::Document|Document"
                )
            )
        )
    }

    func testSwitcherPreviewProjectionRequiresRealNoisyWindows() {
        let expectation =
            FlowTabUITestSwitcherPreviewProjectionExpectation
                .requiredRealWindows(
                    standardTitles: ["Primary"],
                    fullscreenTitles: [
                        "Fullscreen A",
                        "Fullscreen B"
                    ]
                )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherPreviewProjectionTestSnapshot(
                    "com.example.browser::Primary"
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherPreviewProjectionTestSnapshot(
                    "com.example.browser::Fullscreen A"
                )
            )
        )
        XCTAssertTrue(
            expectation.isSatisfied(
                by: switcherPreviewProjectionTestSnapshot(
                    "com.example.browser::Primary|Fullscreen B"
                )
            )
        )
        XCTAssertTrue(
            FlowTabUITestSwitcherPreviewProjectionExpectation
                .requiredRealWindows(
                    standardTitles: ["Primary"],
                    fullscreenTitles: []
                )
                .isSatisfied(
                    by: switcherPreviewProjectionTestSnapshot(
                        "com.example.browser::Primary|Noisy"
                    )
                )
        )
    }

    func testSwitcherPreviewProjectionRejectsStaleReadbacksUnderPressure() {
        for _ in 0..<FlowTabUITestSwitcherPreviewProjectionTestPolicy
            .pressureIterations
        {
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var previewValue =
                "com.example.browser::Primary"
            let owner =
                FlowTabUITestSwitcherPreviewProjectionObservationOwner(
                    expectation:
                        .exactTitles(
                            ["Primary", "Secondary"]
                        ),
                    observationRegistration: { callback in
                        callbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: {
                        self
                            .switcherPreviewProjectionTestSnapshot(
                                previewValue
                            )
                    }
                )
            owner.start()
            let staleReadback = callbacks[0]
            owner.cancel()
            owner.start()
            previewValue =
                "com.example.browser::Primary|Secondary"

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

    func testSwitcherPreviewProjectionWatchdogReportsFinalTitles() {
        let owner =
            FlowTabUITestSwitcherPreviewProjectionObservationOwner(
                expectation:
                    .exactTitles(["Primary", "Secondary"]),
                observationRegistration: nil,
                readback: {
                    self.switcherPreviewProjectionTestSnapshot(
                        "com.example.browser::Primary"
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherPreviewProjectionTestPolicy
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
                "titles=[\"Primary\"]"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "com.example.browser::Primary"
            )
        )
    }

    private func switcherPreviewProjectionTestSnapshot(
        _ previewValue: String
    ) -> FlowTabUITestSwitcherPreviewProjectionSnapshot {
        FlowTabUITestSwitcherPreviewProjectionSnapshot(
            identifier: "switcher-summary",
            exists: true,
            rawValue:
                "preview=\(previewValue);mode=windowCycle",
            previewValue: previewValue
        )
    }
}
