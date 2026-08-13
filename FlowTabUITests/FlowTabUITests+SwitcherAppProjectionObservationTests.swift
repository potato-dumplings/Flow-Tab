import Foundation
import XCTest

private enum FlowTabUITestSwitcherAppProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSwitcherAppProjectionPolicyPreservesPostLaunchBound() {
        XCTAssertEqual(
            FlowTabUITestSwitcherAppProjectionPolicy.postLaunchWatchdog,
            10
        )
        XCTAssertTrue(
            FlowTabUITestSwitcherAppProjectionPolicy
                .postLaunchWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSwitcherAppProjectionPolicy.postLaunchWatchdog,
            0
        )
        XCTAssertEqual(
            switcherAppRowIdentifier("com.flowtab.mock.browser"),
            "flowtab.switcher.app.com-flowtab-mock-browser.id-5034d04b"
        )
    }

    func testSwitcherAppProjectionRuntimeOrderPolicyPreservesCompatibleBound() {
        XCTAssertEqual(
            FlowTabUITestSwitcherAppProjectionPolicy.runtimeOrderWatchdog,
            5
        )
        XCTAssertTrue(
            FlowTabUITestSwitcherAppProjectionPolicy
                .runtimeOrderWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSwitcherAppProjectionPolicy.runtimeOrderWatchdog,
            0
        )
    }

    func testSwitcherAppProjectionStandardFixturePolicyPreservesCompatibleBound() {
        XCTAssertEqual(
            FlowTabUITestSwitcherAppProjectionPolicy
                .standardFixtureProjectionWatchdog,
            8
        )
        XCTAssertTrue(
            FlowTabUITestSwitcherAppProjectionPolicy
                .standardFixtureProjectionWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSwitcherAppProjectionPolicy
                .standardFixtureProjectionWatchdog,
            0
        )
    }

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

    func testSwitcherAppProjectionRequiresExactBundleIdentifierOrder() {
        let expectation =
            FlowTabUITestSwitcherAppProjectionExpectation
                .orderedBundleIdentifiers(
                    ["com.example.browser", "com.example.mail"]
                )

        XCTAssertTrue(
            expectation.isSatisfied(
                by: switcherAppProjectionTestSnapshot(
                    [
                        "com.example.browser:99",
                        "com.example.mail:unknown"
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherAppProjectionTestSnapshot(
                    ["com.example.mail:1", "com.example.browser:2"]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherAppProjectionTestSnapshot(
                    ["com.example.browser:99"]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherAppProjectionTestSnapshot(
                    [
                        "com.example.browser.backup:99",
                        "com.example.mail:1"
                    ]
                )
            )
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

    func testSwitcherAppProjectionRequiresAtomicIncludedAndExcludedApps() {
        let expectation =
            FlowTabUITestSwitcherAppProjectionExpectation.bundleIdentifiers(
                required: ["com.example.browser"],
                excluded: ["com.example.mail"]
            )

        XCTAssertTrue(
            expectation.isSatisfied(
                by: switcherAppProjectionTestSnapshot(
                    ["com.example.browser:2", "com.example.notes:1"]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherAppProjectionTestSnapshot(
                    ["com.example.notes:1"]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherAppProjectionTestSnapshot(
                    ["com.example.browser:2", "com.example.mail:1"]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherAppProjectionTestSnapshot(
                    ["com.example.browser.backup:2"]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherAppProjectionTestSnapshot(
                    ["com.example.browser:2"],
                    applicationState: .runningBackground
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherAppProjectionTestSnapshot(
                    ["com.example.browser:2"],
                    exists: false
                )
            )
        )
    }

    func testSwitcherAppProjectionGatesPostLaunchResolution() {
        let matching = switcherAppProjectionTestSnapshot(
            ["com.example.browser:2"]
        )
        var triggerDidComplete = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner = FlowTabUITestSwitcherAppProjectionObservationOwner(
            expectation: .bundleIdentifiers(
                required: ["com.example.browser"],
                excluded: ["com.example.mail"]
            ),
            observationRegistration: { callback in
                scheduledReadback = callback
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            acceptsResolution: { triggerDidComplete },
            readback: { matching }
        )
        owner.start()

        XCTAssertNil(owner.resolvedEvidence)
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)

        XCTAssertEqual(owner.resolvedEvidence?.source, .triggerReadback)
        XCTAssertEqual(owner.resolvedEvidence?.value, matching)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
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

    func testSwitcherAppProjectionBundleEntryRejectsPrefixCollision() {
        var entries = [
            "com.example.browser.backup:2"
        ]
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

        XCTAssertNil(owner.resolvedEvidence)
        entries = ["com.example.browser:2"]
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.value.entries.first?
                .bundleIdentifier,
            "com.example.browser"
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
                    .bundleIdentifiers(
                        required: ["com.example.browser"],
                        excluded: ["com.example.mail"]
                    ),
                observationRegistration: nil,
                readback: {
                    self.switcherAppProjectionTestSnapshot(
                        ["com.example.mail:1"]
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
                "com.example.mail:1"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "requiredBundleIDs=[\"com.example.browser\"]"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "excludedBundleIDs=[\"com.example.mail\"]"
            )
        )
    }

    private func switcherAppProjectionTestSnapshot(
        _ rawEntries: [String],
        applicationState: XCUIApplication.State = .runningForeground,
        exists: Bool = true
    ) -> FlowTabUITestSwitcherAppProjectionSnapshot {
        FlowTabUITestSwitcherAppProjectionSnapshot(
            applicationState: applicationState,
            identifier: "switcher-summary",
            exists: exists,
            rawValue: exists ? rawEntries.joined(separator: "|") : nil,
            entries: exists ? rawEntries.map {
                FlowTabUITestSwitcherAppProjectionEntry(
                    rawValue: $0
                )
            } : []
        )
    }
}
