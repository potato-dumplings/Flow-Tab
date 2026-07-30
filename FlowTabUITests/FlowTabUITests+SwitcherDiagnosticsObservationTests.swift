import Foundation
import XCTest

private enum FlowTabUITestSwitcherDiagnosticsTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSwitcherDiagnosticsObserverAcceptsMatchingInitialProjection() {
        var order: [String] = []
        let owner =
            FlowTabUITestSwitcherDiagnosticsObservationOwner(
                expectations:
                    switcherDiagnosticsTestExpectations,
                observationRegistration: { _ in
                    order.append("register")
                    return FlowTabUITestObservationCancellation {
                        order.append("cancel")
                    }
                },
                readback: {
                    order.append("readback")
                    return self.switcherDiagnosticsTestSnapshot(
                        selectedWindow: "secondary",
                        previewImages: "2"
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(owner.resolvedEvidence?.source, .initialReadback)
        XCTAssertEqual(
            order,
            ["register", "readback", "cancel"]
        )
        XCTAssertEqual(
            switcherPanelDiagnosticsValue(
                in: "search=a%20b;mode=windowCycle",
                key: "search"
            ),
            "a%20b"
        )
        XCTAssertTrue(
            FlowTabUITestSwitcherDiagnosticsExpectation(
                key: "search",
                expectedValue: "a b",
                decodesPercentEncoding: true
            ).isSatisfied(
                by: FlowTabUITestSwitcherDiagnosticsSnapshot(
                    identifier: "summary",
                    exists: true,
                    rawValue: "search=a%20b",
                    values: ["search": "a%20b"]
                )
            )
        )
    }

    func testSwitcherDiagnosticsObserverMatchesPercentDecodedProjection() {
        let owner =
            FlowTabUITestSwitcherDiagnosticsObservationOwner(
                expectations: [
                    FlowTabUITestSwitcherDiagnosticsExpectation(
                        key: "searchSelectedResult",
                        expectedValue: "app:com.example.browser",
                        decodesPercentEncoding: true
                    )
                ],
                observationRegistration: nil,
                readback: {
                    FlowTabUITestSwitcherDiagnosticsSnapshot(
                        identifier: "switcher-summary",
                        exists: true,
                        rawValue:
                            "searchSelectedResult="
                            + "app%3Acom.example.browser",
                        values: [
                            "searchSelectedResult":
                                "app%3Acom.example.browser"
                        ]
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(owner.resolvedEvidence?.source, .initialReadback)
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "[percentDecoded]"
            )
        )
    }

    func testSwitcherDiagnosticsObserverMatchesPrefixProjection() {
        let owner =
            FlowTabUITestSwitcherDiagnosticsObservationOwner(
                expectations: [
                    FlowTabUITestSwitcherDiagnosticsExpectation(
                        key: "mode",
                        expectedPrefix: "windowCycle"
                    )
                ],
                observationRegistration: nil,
                readback: {
                    FlowTabUITestSwitcherDiagnosticsSnapshot(
                        identifier: "switcher-summary",
                        exists: true,
                        rawValue:
                            "mode=windowCycleForward",
                        values: [
                            "mode": "windowCycleForward"
                        ]
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

    func testSwitcherDiagnosticsObserverRequiresPostTriggerProjection() {
        var acceptsEvidence = false
        var cancellationCount = 0
        let owner =
            FlowTabUITestSwitcherDiagnosticsObservationOwner(
                expectations:
                    switcherDiagnosticsTestExpectations,
                acceptsEvidence: {
                    acceptsEvidence
                },
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    self.switcherDiagnosticsTestSnapshot(
                        selectedWindow: "secondary",
                        previewImages: "2"
                    )
                }
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

    func testSwitcherDiagnosticsScheduledReadbacksOnlyDelayResolution() {
        var readback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var previewImages = "1"
        let owner =
            FlowTabUITestSwitcherDiagnosticsObservationOwner(
                expectations:
                    switcherDiagnosticsTestExpectations,
                observationRegistration: { callback in
                    readback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    self.switcherDiagnosticsTestSnapshot(
                        selectedWindow: "secondary",
                        previewImages: previewImages
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        for _ in 0..<5 {
            readback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }
        previewImages = "2"
        readback?(.scheduledReadback)

        XCTAssertEqual(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherDiagnosticsTestPolicy
                        .watchdog
            )?.source,
            .scheduledReadback
        )
    }

    func testSwitcherDiagnosticsRequiresAtomicCommittedSearchIndexProjection() {
        var readback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var readiness = "committedGenerationValidated"
        var resultState = "building"
        let owner =
            FlowTabUITestSwitcherDiagnosticsObservationOwner(
                expectations: [
                    FlowTabUITestSwitcherDiagnosticsExpectation(
                        key: "searchIndexReadiness",
                        expectedValue:
                            "committedGenerationValidated"
                    ),
                    FlowTabUITestSwitcherDiagnosticsExpectation(
                        key: "searchIndexResultState",
                        expectedValue:
                            "committedGenerationResult"
                    ),
                    FlowTabUITestSwitcherDiagnosticsExpectation(
                        key: "searchIndexDegraded",
                        expectedValue: "0"
                    ),
                    FlowTabUITestSwitcherDiagnosticsExpectation(
                        key:
                            "searchIndexCoversCurrentGeneration",
                        expectedValue: "1"
                    ),
                    FlowTabUITestSwitcherDiagnosticsExpectation(
                        key:
                            "searchFreshnessBarrierRequested",
                        expectedValue: "0"
                    )
                ],
                observationRegistration: { callback in
                    readback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    FlowTabUITestSwitcherDiagnosticsSnapshot(
                        identifier: "switcher-summary",
                        exists: true,
                        rawValue: nil,
                        values: [
                            "searchIndexReadiness": readiness,
                            "searchIndexResultState": resultState,
                            "searchIndexDegraded": "0",
                            "searchIndexCoversCurrentGeneration":
                                "1",
                            "searchFreshnessBarrierRequested": "0"
                        ]
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }
        XCTAssertNil(owner.resolvedEvidence)

        readiness = "building"
        resultState = "committedGenerationResult"
        readback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        readiness = "committedGenerationValidated"
        readback?(.scheduledReadback)
        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
    }

    func testSwitcherDiagnosticsObserverRejectsStaleEventsUnderPressure() {
        for _ in 0..<FlowTabUITestSwitcherDiagnosticsTestPolicy
            .pressureIterations
        {
            var readbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var previewImages = "1"
            let owner =
                FlowTabUITestSwitcherDiagnosticsObservationOwner(
                    expectations:
                        switcherDiagnosticsTestExpectations,
                    observationRegistration: { callback in
                        readbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: {
                        self.switcherDiagnosticsTestSnapshot(
                            selectedWindow: "secondary",
                            previewImages: previewImages
                        )
                    }
                )

            owner.start()
            let staleReadback = readbacks[0]
            owner.cancel()
            owner.start()
            previewImages = "2"

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

    func testSwitcherDiagnosticsWatchdogReportsFinalProjection() {
        var readbackCount = 0
        let owner =
            FlowTabUITestSwitcherDiagnosticsObservationOwner(
                expectations:
                    switcherDiagnosticsTestExpectations,
                observationRegistration: nil,
                readback: {
                    defer { readbackCount += 1 }
                    return self.switcherDiagnosticsTestSnapshot(
                        selectedWindow:
                            readbackCount == 0
                                ? "primary"
                                : "secondary",
                        previewImages: "1"
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherDiagnosticsTestPolicy
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
                "selectedWindow=secondary"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "previewImages=1"
            )
        )
    }

    private var switcherDiagnosticsTestExpectations: [
        FlowTabUITestSwitcherDiagnosticsExpectation
    ] {
        [
            FlowTabUITestSwitcherDiagnosticsExpectation(
                key: "selectedWindow",
                expectedValue: "secondary"
            ),
            FlowTabUITestSwitcherDiagnosticsExpectation(
                key: "previewImages",
                expectedValue: "2"
            )
        ]
    }

    private func switcherDiagnosticsTestSnapshot(
        selectedWindow: String,
        previewImages: String
    ) -> FlowTabUITestSwitcherDiagnosticsSnapshot {
        FlowTabUITestSwitcherDiagnosticsSnapshot(
            identifier: "switcher-summary",
            exists: true,
            rawValue:
                "selectedWindow=\(selectedWindow);"
                + "previewImages=\(previewImages)",
            values: [
                "selectedWindow": selectedWindow,
                "previewImages": previewImages
            ]
        )
    }
}
