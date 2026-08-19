import Foundation
import XCTest

private enum FlowTabUITestVisibleSwitcherAppProjectionTestPolicy {
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testVisibleSwitcherAppProjectionRequiresAtomicDiagnosticsAndRows() {
        let expectation = visibleSwitcherAppProjectionTestExpectation()

        XCTAssertTrue(
            expectation.isSatisfied(
                by: visibleSwitcherAppProjectionTestSnapshot()
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: visibleSwitcherAppProjectionTestSnapshot(
                    visibleRowIdentifiers: []
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: visibleSwitcherAppProjectionTestSnapshot(
                    entries: ["com.example.browser:1", "com.example.mail:1"]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: visibleSwitcherAppProjectionTestSnapshot(
                    diagnosticsExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: visibleSwitcherAppProjectionTestSnapshot(
                    applicationState: .runningBackground
                )
            )
        )
    }

    func testVisibleSwitcherAppProjectionGatesPreTriggerEvidence() {
        let matching = visibleSwitcherAppProjectionTestSnapshot()
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestVisibleSwitcherAppProjectionObservationOwner(
                expectation:
                    visibleSwitcherAppProjectionTestExpectation(),
                scheduledRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { matching }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        owner.markTriggerCompleted()

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
    }

    func testVisibleSwitcherAppProjectionWaitsForDelayedRows() {
        var snapshot = visibleSwitcherAppProjectionTestSnapshot(
            visibleRowIdentifiers: []
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestVisibleSwitcherAppProjectionObservationOwner(
                expectation:
                    visibleSwitcherAppProjectionTestExpectation(),
                scheduledRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }
        owner.markTriggerCompleted()

        XCTAssertNil(owner.resolvedEvidence)
        snapshot = visibleSwitcherAppProjectionTestSnapshot()
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
    }

    func testVisibleSwitcherAppProjectionRejectsDisappearedPanel() {
        var snapshot = visibleSwitcherAppProjectionTestSnapshot(
            visibleRowIdentifiers: []
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestVisibleSwitcherAppProjectionObservationOwner(
                expectation:
                    visibleSwitcherAppProjectionTestExpectation(),
                scheduledRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }
        owner.markTriggerCompleted()

        snapshot = visibleSwitcherAppProjectionTestSnapshot(
            diagnosticsExists: false,
            visibleRowIdentifiers: []
        )
        scheduledReadback?(.scheduledReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "diagnosticsExists=false"
            )
        )
    }

    func testVisibleSwitcherAppProjectionCancelsScheduledReadbacks() {
        var cancellationCount = 0
        let owner =
            FlowTabUITestVisibleSwitcherAppProjectionObservationOwner(
                expectation:
                    visibleSwitcherAppProjectionTestExpectation(),
                scheduledRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    self.visibleSwitcherAppProjectionTestSnapshot(
                        visibleRowIdentifiers: []
                    )
                }
            )
        owner.start()
        owner.markTriggerCompleted()

        owner.cancel()
        owner.cancel()

        XCTAssertEqual(cancellationCount, 1)
    }

    func testVisibleSwitcherAppProjectionRejectsStaleReadbacksUnderPressure() {
        var callbacks: [
            (FlowTabUITestConditionObservationSource) -> Void
        ] = []
        var cancellationCount = 0
        var resolutionCount = 0
        var snapshot = visibleSwitcherAppProjectionTestSnapshot(
            visibleRowIdentifiers: []
        )
        let owner =
            FlowTabUITestVisibleSwitcherAppProjectionObservationOwner(
                expectation:
                    visibleSwitcherAppProjectionTestExpectation(),
                scheduledRegistration: { callback in
                    callbacks.append(callback)
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )

        for iteration in
            0..<FlowTabUITestVisibleSwitcherAppProjectionTestPolicy
                .pressureIterations
        {
            owner.start()
            owner.markTriggerCompleted()
            let staleCallback = callbacks.last!
            owner.cancel()

            owner.start()
            owner.markTriggerCompleted()
            snapshot = visibleSwitcherAppProjectionTestSnapshot()
            callbacks.last?(.scheduledReadback)
            if owner.resolvedEvidence != nil {
                resolutionCount += 1
            }
            let resolvedEvidence = owner.resolvedEvidence
            staleCallback(.scheduledReadback)

            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                resolvedEvidence?.generation,
                "iteration=\(iteration)"
            )
            XCTAssertEqual(
                owner.resolvedEvidence?.source,
                resolvedEvidence?.source,
                "iteration=\(iteration)"
            )
            XCTAssertEqual(
                owner.resolvedEvidence?.value,
                resolvedEvidence?.value,
                "iteration=\(iteration)"
            )
            owner.cancel()
            snapshot = visibleSwitcherAppProjectionTestSnapshot(
                visibleRowIdentifiers: []
            )
        }

        XCTAssertEqual(
            resolutionCount,
            FlowTabUITestVisibleSwitcherAppProjectionTestPolicy
                .pressureIterations
        )
        XCTAssertEqual(
            cancellationCount,
            FlowTabUITestVisibleSwitcherAppProjectionTestPolicy
                .pressureIterations * 2
        )
    }

    private func visibleSwitcherAppProjectionTestExpectation()
        -> FlowTabUITestVisibleSwitcherAppProjectionExpectation
    {
        FlowTabUITestVisibleSwitcherAppProjectionExpectation(
            diagnosticsIdentifier: Identifier.switcherSummary,
            appProjection: .bundleIdentifiers(
                required: ["com.example.browser"],
                excluded: ["com.example.mail"]
            ),
            requiredRowIdentifiers: ["browser-row"],
            excludedRowIdentifiers: ["mail-row"]
        )
    }

    private func visibleSwitcherAppProjectionTestSnapshot(
        applicationState: XCUIApplication.State = .runningForeground,
        diagnosticsExists: Bool = true,
        entries: [String] = ["com.example.browser:1"],
        visibleRowIdentifiers: Set<String> = ["browser-row"]
    ) -> FlowTabUITestVisibleSwitcherAppProjectionSnapshot {
        FlowTabUITestVisibleSwitcherAppProjectionSnapshot(
            applicationState: applicationState,
            diagnosticsIdentifier: Identifier.switcherSummary,
            diagnosticsExists: diagnosticsExists,
            rawAppsValue: entries.joined(separator: "|"),
            entries: entries.map {
                FlowTabUITestSwitcherAppProjectionEntry(
                    rawValue: $0
                )
            },
            visibleTargetRowIdentifiers:
                visibleRowIdentifiers
        )
    }
}
