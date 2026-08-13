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

    func testSwitcherAppProjectionQuitShortcutRemovalPolicyPreservesCompatibleBound() {
        XCTAssertEqual(
            FlowTabUITestSwitcherAppProjectionPolicy
                .quitShortcutRemovalWatchdog,
            8
        )
        XCTAssertTrue(
            FlowTabUITestSwitcherAppProjectionPolicy
                .quitShortcutRemovalWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSwitcherAppProjectionPolicy
                .quitShortcutRemovalWatchdog,
            0
        )
    }

    func testSwitcherAppProjectionQuitShortcutInitialPolicyPreservesCompatibleBound() {
        XCTAssertEqual(
            FlowTabUITestSwitcherAppProjectionPolicy
                .quitShortcutInitialProjectionWatchdog,
            12
        )
        XCTAssertTrue(
            FlowTabUITestSwitcherAppProjectionPolicy
                .quitShortcutInitialProjectionWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSwitcherAppProjectionPolicy
                .quitShortcutInitialProjectionWatchdog,
            0
        )
    }

    func testSwitcherAppProjectionOpenWindowMutationInitialPolicyPreservesCompatibleBound() {
        XCTAssertEqual(
            FlowTabUITestSwitcherAppProjectionPolicy
                .openWindowMutationInitialProjectionWatchdog,
            12
        )
        XCTAssertTrue(
            FlowTabUITestSwitcherAppProjectionPolicy
                .openWindowMutationInitialProjectionWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSwitcherAppProjectionPolicy
                .openWindowMutationInitialProjectionWatchdog,
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

    func testSwitcherAppRemovalObservationUsesExactInitialAndTriggerEvidence() {
        var entries = ["com.example.fixture:1"]
        var rowExists = true
        var scheduledRegistrationCount = 0
        let owner =
            FlowTabUITestSwitcherAppRemovalObservationOwner(
                bundleIdentifier: "com.example.fixture",
                expectedInitialWindowCount: 1,
                scheduledRegistration: { _ in
                    scheduledRegistrationCount += 1
                    return FlowTabUITestObservationCancellation {}
                },
                projectionReadback: {
                    self.switcherAppProjectionTestSnapshot(
                        entries
                    )
                },
                rowRepresentationCount: {
                    rowExists ? 2 : 0
                },
                rowExists: { rowExists }
            )
        XCTAssertTrue(owner.start())
        defer { owner.cancel() }

        entries = []
        rowExists = false
        owner.markTriggerCompleted()

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.entries,
            []
        )
        XCTAssertEqual(scheduledRegistrationCount, 0)
    }

    func testSwitcherAppRemovalObservationRejectsMismatchedInitialBaseline() {
        var scheduledRegistrationCount = 0
        let owner =
            FlowTabUITestSwitcherAppRemovalObservationOwner(
                bundleIdentifier: "com.example.fixture",
                expectedInitialWindowCount: 1,
                scheduledRegistration: { _ in
                    scheduledRegistrationCount += 1
                    return FlowTabUITestObservationCancellation {}
                },
                projectionReadback: {
                    self.switcherAppProjectionTestSnapshot(
                        ["com.example.fixture:2"]
                    )
                },
                rowRepresentationCount: { 2 },
                rowExists: { true }
            )

        XCTAssertFalse(owner.start())
        owner.markTriggerCompleted()

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(scheduledRegistrationCount, 0)
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "initialEvidenceSatisfied=false"
            )
        )
        owner.cancel()
    }

    func testSwitcherAppRemovalObservationWaitsForProjectionAndFreshRowAbsence() {
        var entries = ["com.example.fixture:1"]
        var rowExists = true
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSwitcherAppRemovalObservationOwner(
                bundleIdentifier: "com.example.fixture",
                expectedInitialWindowCount: 1,
                scheduledRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                projectionReadback: {
                    self.switcherAppProjectionTestSnapshot(
                        entries
                    )
                },
                rowRepresentationCount: {
                    rowExists ? 2 : 0
                },
                rowExists: { rowExists }
            )
        XCTAssertTrue(owner.start())
        defer { owner.cancel() }
        owner.markTriggerCompleted()

        for _ in 0..<5 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }
        entries = []
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        rowExists = false
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSwitcherAppRemovalObservationCancellationRejectsLateReadback() {
        var entries = ["com.example.fixture:1"]
        var rowExists = true
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSwitcherAppRemovalObservationOwner(
                bundleIdentifier: "com.example.fixture",
                expectedInitialWindowCount: 1,
                scheduledRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                projectionReadback: {
                    self.switcherAppProjectionTestSnapshot(
                        entries
                    )
                },
                rowRepresentationCount: {
                    rowExists ? 2 : 0
                },
                rowExists: { rowExists }
            )
        XCTAssertTrue(owner.start())
        owner.markTriggerCompleted()
        owner.cancel()

        entries = []
        rowExists = false
        scheduledReadback?(.scheduledReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSwitcherAppRemovalObservationWatchdogReportsFinalEvidence() {
        let owner =
            FlowTabUITestSwitcherAppRemovalObservationOwner(
                bundleIdentifier: "com.example.fixture",
                expectedInitialWindowCount: 1,
                scheduledRegistration: { _ in
                    FlowTabUITestObservationCancellation {}
                },
                projectionReadback: {
                    self.switcherAppProjectionTestSnapshot(
                        ["com.example.fixture:1"]
                    )
                },
                rowRepresentationCount: { 2 },
                rowExists: { true }
            )
        XCTAssertTrue(owner.start())
        defer { owner.cancel() }
        owner.markTriggerCompleted()

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
                "expectedInitialEntry=com.example.fixture:1"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "finalRepresentationCount=2"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("finalExists=true")
        )
    }

    func testSwitcherAppRemovalObservationRejectsStaleReadbacksUnderPressure() {
        for _ in 0..<FlowTabUITestSwitcherAppProjectionTestPolicy
            .pressureIterations
        {
            var entries = ["com.example.fixture:1"]
            var rowExists = true
            var scheduledReadbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner =
                FlowTabUITestSwitcherAppRemovalObservationOwner(
                    bundleIdentifier: "com.example.fixture",
                    expectedInitialWindowCount: 1,
                    scheduledRegistration: { callback in
                        scheduledReadbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    projectionReadback: {
                        self.switcherAppProjectionTestSnapshot(
                            entries
                        )
                    },
                    rowRepresentationCount: {
                        rowExists ? 2 : 0
                    },
                    rowExists: { rowExists }
                )

            XCTAssertTrue(owner.start())
            owner.markTriggerCompleted()
            let staleReadback = scheduledReadbacks[0]
            owner.cancel()

            XCTAssertTrue(owner.start())
            owner.markTriggerCompleted()
            let currentReadback = scheduledReadbacks[1]
            entries = []
            rowExists = false

            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            currentReadback(.scheduledReadback)
            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                2
            )
            owner.cancel()
        }
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
