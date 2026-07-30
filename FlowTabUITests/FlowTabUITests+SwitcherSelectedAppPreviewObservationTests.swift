import Foundation
import XCTest

private enum FlowTabUITestSwitcherSelectedAppPreviewTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSwitcherSelectedAppPreviewAcceptsAtomicInitialMatch() {
        var order: [String] = []
        let expectation =
            selectedAppPreviewTestExpectation()
        let owner =
            FlowTabUITestSwitcherSelectedAppPreviewObservationOwner(
                expectation: expectation,
                observationRegistration: { _ in
                    order.append("register")
                    return FlowTabUITestObservationCancellation {
                        order.append("cancel")
                    }
                },
                readback: {
                    order.append("readback")
                    return self
                        .switcherSelectedAppPreviewTestSnapshot(
                            bundleIdentifier:
                                "com.example.browser",
                            titles: ["Browser"]
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

    func testSwitcherSelectedAppPreviewRejectsMixedProjection() {
        var snapshot =
            switcherSelectedAppPreviewTestSnapshot(
                bundleIdentifier: "com.example.browser",
                titles: ["Mail"]
            )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let expectation =
            selectedAppPreviewTestExpectation()
        let owner =
            FlowTabUITestSwitcherSelectedAppPreviewObservationOwner(
                expectation: expectation,
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        for _ in 0..<5 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }
        snapshot = switcherSelectedAppPreviewTestSnapshot(
            bundleIdentifier: "com.example.mail",
            titles: ["Mail"]
        )
        scheduledReadback?(.scheduledReadback)

        let evidence = owner.resolvedEvidence
        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(
            evidence.flatMap {
                expectation.matchingCandidate(in: $0.value)
            }?.appID,
            "mail"
        )
    }

    func testSwitcherSelectedAppPreviewHonorsEligibleCandidates() {
        let expectation =
            FlowTabUITestSwitcherSelectedAppPreviewExpectation(
                candidates: [
                    FlowTabUITestSwitcherSelectedAppPreviewCandidate(
                        appID: "mail",
                        bundleIdentifier: "com.example.mail",
                        expectedTitles: ["Mail"]
                    )
                ]
            )
        XCTAssertNil(
            expectation.matchingCandidate(
                in: switcherSelectedAppPreviewTestSnapshot(
                    bundleIdentifier:
                        "com.example.browser",
                    titles: ["Browser"]
                )
            )
        )
    }

    func testSwitcherSelectedAppPreviewRejectsAmbiguousCandidates() {
        let candidates = ["browser-primary", "browser-secondary"]
            .map {
                FlowTabUITestSwitcherSelectedAppPreviewCandidate(
                    appID: $0,
                    bundleIdentifier: "com.example.browser",
                    expectedTitles: ["Browser"]
                )
            }
        let expectation =
            FlowTabUITestSwitcherSelectedAppPreviewExpectation(
                candidates: candidates
            )

        XCTAssertNil(
            expectation.matchingCandidate(
                in: switcherSelectedAppPreviewTestSnapshot(
                    bundleIdentifier:
                        "com.example.browser",
                    titles: ["Browser"]
                )
            )
        )
    }

    func testSwitcherSelectedAppPreviewRejectsStaleReadbacksUnderPressure() {
        for _ in 0..<FlowTabUITestSwitcherSelectedAppPreviewTestPolicy
            .pressureIterations
        {
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var snapshot =
                switcherSelectedAppPreviewTestSnapshot(
                    bundleIdentifier:
                        "com.example.browser",
                    titles: ["Mail"]
                )
            let owner =
                FlowTabUITestSwitcherSelectedAppPreviewObservationOwner(
                    expectation:
                        selectedAppPreviewTestExpectation(),
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
            snapshot = switcherSelectedAppPreviewTestSnapshot(
                bundleIdentifier: "com.example.browser",
                titles: ["Browser"]
            )

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

    func testSwitcherSelectedAppPreviewWatchdogReportsAtomicProjection() {
        let owner =
            FlowTabUITestSwitcherSelectedAppPreviewObservationOwner(
                expectation:
                    selectedAppPreviewTestExpectation(),
                observationRegistration: nil,
                readback: {
                    self.switcherSelectedAppPreviewTestSnapshot(
                        bundleIdentifier:
                            "com.example.browser",
                        titles: ["Mail"]
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherSelectedAppPreviewTestPolicy
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
                "selectedBundleID=com.example.browser"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "titles=[\"Mail\"]"
            )
        )
    }

    private func selectedAppPreviewTestExpectation()
        -> FlowTabUITestSwitcherSelectedAppPreviewExpectation {
        FlowTabUITestSwitcherSelectedAppPreviewExpectation(
            candidates: [
                FlowTabUITestSwitcherSelectedAppPreviewCandidate(
                    appID: "browser",
                    bundleIdentifier: "com.example.browser",
                    expectedTitles: ["Browser"]
                ),
                FlowTabUITestSwitcherSelectedAppPreviewCandidate(
                    appID: "mail",
                    bundleIdentifier: "com.example.mail",
                    expectedTitles: ["Mail"]
                )
            ]
        )
    }

    private func switcherSelectedAppPreviewTestSnapshot(
        bundleIdentifier: String,
        titles: [String]
    ) -> FlowTabUITestSwitcherPreviewProjectionSnapshot {
        let previewValue =
            "\(bundleIdentifier)::"
            + titles.joined(separator: "|")
        return FlowTabUITestSwitcherPreviewProjectionSnapshot(
            identifier: "switcher-summary",
            exists: true,
            rawValue:
                "selected=\(bundleIdentifier);"
                + "preview=\(previewValue)",
            previewValue: previewValue,
            selectedBundleIdentifier: bundleIdentifier
        )
    }
}
