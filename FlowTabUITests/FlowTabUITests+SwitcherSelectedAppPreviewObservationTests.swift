import Foundation
import XCTest

private enum FlowTabUITestSwitcherSelectedAppPreviewTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 200
}

extension FlowTabUITests {
    func testSwitcherSelectedAppPreviewTransitionPolicyPreservesCompatibleBound() {
        XCTAssertEqual(
            FlowTabUITestSwitcherSelectedAppPreviewPolicy
                .transitionWatchdog,
            12
        )
        XCTAssertTrue(
            FlowTabUITestSwitcherSelectedAppPreviewPolicy
                .transitionWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSwitcherSelectedAppPreviewPolicy
                .transitionWatchdog,
            0
        )
    }

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

    func testSwitcherSelectedAppPreviewRejectsMatchUntilTriggerCompletes() {
        var triggerDidComplete = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let matchingSnapshot =
            switcherSelectedAppPreviewTestSnapshot(
                bundleIdentifier: "com.example.browser",
                titles: ["Browser"]
            )
        let owner =
            FlowTabUITestSwitcherSelectedAppPreviewObservationOwner(
                expectation:
                    selectedAppPreviewTestExpectation(
                        appID: "browser"
                    ),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                acceptsResolution: {
                    triggerDidComplete
                },
                readback: { matchingSnapshot }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value,
            matchingSnapshot
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
        XCTAssertNil(
            expectation.matchingCandidate(
                in: switcherSelectedAppPreviewTestSnapshot(
                    bundleIdentifier:
                        "com.example.mail",
                    titles: ["Mail", "Unexpected"]
                )
            )
        )
        XCTAssertNil(
            expectation.matchingCandidate(
                in: switcherSelectedAppPreviewTestSnapshot(
                    bundleIdentifier:
                        "com.example.mail",
                    titles: ["Mail"],
                    previewBundleIdentifier:
                        "com.example.browser"
                )
            )
        )
        XCTAssertNil(
            expectation.matchingCandidate(
                in: switcherSelectedAppPreviewTestSnapshot(
                    bundleIdentifier:
                        "com.example.mail",
                    titles: ["Mail", "Mail"]
                )
            )
        )
        XCTAssertEqual(
            expectation.matchingCandidate(
                in: switcherSelectedAppPreviewTestSnapshot(
                    bundleIdentifier:
                        "com.example.mail",
                    titles: ["Mail"]
                )
            )?.appID,
            "mail"
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

    func testSwitcherSelectedAppPreviewRejectsDuplicateAndOutOfOrderReadbacksUnderPressure() {
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

    func testSwitcherSelectedAppPreviewCancellationRejectsLaterReadback() {
        var snapshot =
            switcherSelectedAppPreviewTestSnapshot(
                bundleIdentifier: "com.example.browser",
                titles: ["Mail"]
            )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSwitcherSelectedAppPreviewObservationOwner(
                expectation:
                    selectedAppPreviewTestExpectation(),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()
        owner.cancel()

        snapshot = switcherSelectedAppPreviewTestSnapshot(
            bundleIdentifier: "com.example.browser",
            titles: ["Browser"]
        )
        scheduledReadback?(.scheduledReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSwitcherSelectedAppPreviewSlowSchedulingOnlyDelaysResolution() {
        var snapshot =
            switcherSelectedAppPreviewTestSnapshot(
                bundleIdentifier: "com.example.browser",
                titles: ["Mail"]
            )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let expectation = selectedAppPreviewTestExpectation()
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

        snapshot = switcherSelectedAppPreviewTestSnapshot(
            bundleIdentifier: "com.example.mail",
            titles: ["Mail"]
        )
        XCTAssertNil(owner.resolvedEvidence)

        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence.flatMap {
                expectation.matchingCandidate(in: $0.value)
            }?.appID,
            "mail"
        )
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

    private func selectedAppPreviewTestExpectation(
        appID: String
    ) -> FlowTabUITestSwitcherSelectedAppPreviewExpectation {
        let candidates =
            selectedAppPreviewTestExpectation().candidates
                .filter { $0.appID == appID }
        return FlowTabUITestSwitcherSelectedAppPreviewExpectation(
            candidates: candidates
        )
    }

    private func switcherSelectedAppPreviewTestSnapshot(
        bundleIdentifier: String,
        titles: [String],
        previewBundleIdentifier: String? = nil
    ) -> FlowTabUITestSwitcherPreviewProjectionSnapshot {
        let resolvedPreviewBundleIdentifier =
            previewBundleIdentifier ?? bundleIdentifier
        let previewValue =
            "\(resolvedPreviewBundleIdentifier)::"
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
