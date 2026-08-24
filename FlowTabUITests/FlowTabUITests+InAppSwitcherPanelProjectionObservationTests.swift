import Foundation
import XCTest

private enum FlowTabUITestInAppSwitcherPanelProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testInAppSwitcherPanelProjectionPolicyUsesNamedWatchdog() {
        let watchdog =
            FlowTabUITestInAppSwitcherPanelProjectionPolicy
            .readinessWatchdog

        XCTAssertEqual(watchdog, 8)
        XCTAssertTrue(watchdog.isFinite && watchdog > 0)
    }

    func testInAppSwitcherPanelProjectionRequiresOneAtomicProjection() {
        let expectation = inAppSwitcherPanelTestExpectation()

        XCTAssertTrue(
            expectation.isSatisfied(
                by: inAppSwitcherPanelTestSnapshot(
                    titles: ["Document", "Document", "Review"]
                )
            )
        )
        XCTAssertTrue(
            expectation.isSatisfied(
                by: inAppSwitcherPanelTestSnapshot(
                    applicationState: .runningForeground,
                    titles: ["Review", "Document", "Document"]
                )
            )
        )

        let mismatches = [
            inAppSwitcherPanelTestSnapshot(
                selected: "com.example.other",
                titles: ["Document", "Document", "Review"]
            ),
            inAppSwitcherPanelTestSnapshot(
                mode: "appCycle",
                titles: ["Document", "Document", "Review"]
            ),
            inAppSwitcherPanelTestSnapshot(
                apps: "com.example.browser:2",
                titles: ["Document", "Document", "Review"]
            ),
            inAppSwitcherPanelTestSnapshot(
                apps: "com.example.browser:3|com.example.browser:3",
                titles: ["Document", "Document", "Review"]
            ),
            inAppSwitcherPanelTestSnapshot(
                previewBundleIdentifier: "com.example.other",
                titles: ["Document", "Document", "Review"]
            ),
            inAppSwitcherPanelTestSnapshot(
                titles: ["Document", "Review", "Review"]
            ),
            inAppSwitcherPanelTestSnapshot(
                applicationState: .notRunning,
                titles: ["Document", "Document", "Review"]
            ),
            inAppSwitcherPanelTestSnapshot(
                applicationState: .runningBackground,
                applicationStateAfter: .runningForeground,
                titles: ["Document", "Document", "Review"]
            )
        ]
        XCTAssertTrue(
            mismatches.allSatisfy {
                !expectation.isSatisfied(by: $0)
            }
        )
    }

    func testInAppSwitcherPanelProjectionResolvesAfterAbsentBaseline() {
        var snapshot = inAppSwitcherPanelMissingTestSnapshot()
        let owner = makeInAppSwitcherPanelTestOwner {
            snapshot
        }
        XCTAssertTrue(owner.start())
        defer { owner.cancel() }

        snapshot = inAppSwitcherPanelTestSnapshot(
            titles: ["Document", "Document", "Review"]
        )
        owner.markTriggerCompleted()

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
    }

    func testInAppSwitcherPanelProjectionRejectsMatchingStaleBaseline() {
        let owner = makeInAppSwitcherPanelTestOwner {
            self.inAppSwitcherPanelTestSnapshot(
                titles: ["Document", "Document", "Review"]
            )
        }

        XCTAssertFalse(owner.start())
        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertTrue(
            owner.diagnosticSummary.contains("exists=true")
        )
        owner.cancel()
    }

    func testInAppSwitcherPanelProjectionSlowSchedulingOnlyDelaysResult() {
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = inAppSwitcherPanelMissingTestSnapshot()
        let owner = makeInAppSwitcherPanelTestOwner(
            scheduledRegistration: { readback in
                callback = readback
                return FlowTabUITestObservationCancellation {}
            },
            readback: { snapshot }
        )
        XCTAssertTrue(owner.start())
        defer { owner.cancel() }
        owner.markTriggerCompleted()

        for _ in 0..<5 {
            callback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }
        snapshot = inAppSwitcherPanelTestSnapshot(
            titles: ["Document", "Document", "Review"]
        )
        callback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
    }

    func testInAppSwitcherPanelProjectionTerminatesOnFirstCompleteMismatch() {
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = inAppSwitcherPanelMissingTestSnapshot()
        let owner = makeInAppSwitcherPanelTestOwner(
            scheduledRegistration: { readback in
                callback = readback
                return FlowTabUITestObservationCancellation {}
            },
            readback: { snapshot }
        )
        XCTAssertTrue(owner.start())
        defer { owner.cancel() }
        owner.markTriggerCompleted()
        snapshot = inAppSwitcherPanelTestSnapshot(
            apps: "com.example.browser:2",
            titles: ["Document", "Review"]
        )

        callback?(.scheduledReadback)

        XCTAssertEqual(
            owner.terminalMismatchEvidence?.source,
            .scheduledReadback
        )
        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestInAppSwitcherPanelProjectionTestPolicy
                    .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("terminalMismatch=true")
        )
    }

    func testInAppSwitcherPanelProjectionCancellationRejectsLateResult() {
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = inAppSwitcherPanelMissingTestSnapshot()
        let owner = makeInAppSwitcherPanelTestOwner(
            scheduledRegistration: { readback in
                callback = readback
                return FlowTabUITestObservationCancellation {}
            },
            readback: { snapshot }
        )
        XCTAssertTrue(owner.start())
        owner.markTriggerCompleted()
        owner.cancel()

        snapshot = inAppSwitcherPanelTestSnapshot(
            titles: ["Document", "Document", "Review"]
        )
        callback?(.scheduledReadback)

        XCTAssertNil(owner.resolvedEvidence)
    }

    func testInAppSwitcherPanelProjectionWatchdogReportsFinalEvidence() {
        var snapshot = inAppSwitcherPanelMissingTestSnapshot()
        let owner = makeInAppSwitcherPanelTestOwner(
            scheduledRegistration: { _ in
                FlowTabUITestObservationCancellation {}
            },
            readback: { snapshot }
        )
        XCTAssertTrue(owner.start())
        defer { owner.cancel() }
        owner.markTriggerCompleted()
        snapshot = inAppSwitcherPanelTestSnapshot(
            titles: ["Document", "Review", "Review"]
        )

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestInAppSwitcherPanelProjectionTestPolicy
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
                "Document:1|Review:2"
            )
        )
    }

    func testInAppSwitcherPanelProjectionRejectsReplacedCallbacksUnderPressure() {
        for _ in 0..<FlowTabUITestInAppSwitcherPanelProjectionTestPolicy
            .pressureIterations
        {
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var snapshot = inAppSwitcherPanelMissingTestSnapshot()
            let owner = makeInAppSwitcherPanelTestOwner(
                scheduledRegistration: { readback in
                    callbacks.append(readback)
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
            XCTAssertTrue(owner.start())
            owner.markTriggerCompleted()
            let staleCallback = callbacks[0]
            owner.cancel()

            snapshot = inAppSwitcherPanelMissingTestSnapshot()
            XCTAssertTrue(owner.start())
            owner.markTriggerCompleted()
            snapshot = inAppSwitcherPanelTestSnapshot(
                titles: ["Document", "Document", "Review"]
            )
            staleCallback(.scheduledReadback)
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

    private func inAppSwitcherPanelTestExpectation()
        -> FlowTabUITestInAppSwitcherPanelProjectionExpectation
    {
        FlowTabUITestInAppSwitcherPanelProjectionExpectation(
            bundleIdentifier: "com.example.browser",
            windowCount: 3,
            expectedTitles: ["Document", "Document", "Review"]
        )
    }

    private func makeInAppSwitcherPanelTestOwner(
        scheduledRegistration:
            @escaping FlowTabUITestConditionObservationRegistration =
                { _ in FlowTabUITestObservationCancellation {} },
        readback: @escaping () ->
            FlowTabUITestInAppSwitcherPanelProjectionSnapshot
    ) -> FlowTabUITestInAppSwitcherPanelProjectionObservationOwner {
        FlowTabUITestInAppSwitcherPanelProjectionObservationOwner(
            expectation: inAppSwitcherPanelTestExpectation(),
            scheduledRegistration: scheduledRegistration,
            readback: readback
        )
    }

    private func inAppSwitcherPanelMissingTestSnapshot()
        -> FlowTabUITestInAppSwitcherPanelProjectionSnapshot
    {
        FlowTabUITestInAppSwitcherPanelProjectionSnapshot(
            applicationStateBefore: .runningBackground,
            diagnostics: FlowTabUITestSwitcherDiagnosticsSnapshot(
                identifier: "unavailable",
                exists: false,
                rawValue: nil,
                values: [:]
            ),
            applicationStateAfter: .runningBackground
        )
    }

    private func inAppSwitcherPanelTestSnapshot(
        applicationState: XCUIApplication.State = .runningBackground,
        applicationStateAfter: XCUIApplication.State? = nil,
        selected: String = "com.example.browser",
        mode: String = "windowCycle(com.example.browser)",
        apps: String = "com.example.browser:3",
        previewBundleIdentifier: String = "com.example.browser",
        titles: [String]
    ) -> FlowTabUITestInAppSwitcherPanelProjectionSnapshot {
        let preview = previewBundleIdentifier
            + "::"
            + titles.joined(separator: "|")
        let rawValue = [
            "apps=\(apps)",
            "selected=\(selected)",
            "mode=\(mode)",
            "preview=\(preview)"
        ].joined(separator: ";")
        return FlowTabUITestInAppSwitcherPanelProjectionSnapshot(
            applicationStateBefore: applicationState,
            diagnostics: FlowTabUITestSwitcherDiagnosticsSnapshot(
                identifier: "switcher-summary",
                exists: true,
                rawValue: rawValue,
                values: [
                    "apps": apps,
                    "selected": selected,
                    "mode": mode,
                    "preview": preview
                ]
            ),
            applicationStateAfter:
                applicationStateAfter ?? applicationState
        )
    }
}
