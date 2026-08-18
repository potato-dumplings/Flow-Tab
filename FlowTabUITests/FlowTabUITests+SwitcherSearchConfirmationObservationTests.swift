import Foundation
import XCTest

private enum FlowTabUITestSwitcherSearchConfirmationTestPolicy {
    static let immediateWatchdog: TimeInterval = 0.01
    static let scheduledReadbackCadence: TimeInterval = 0.001
    static let scheduledReadbackWatchdog: TimeInterval = 1
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSwitcherSearchConfirmationEvidenceRulesAndPolicy() {
        XCTAssertEqual(
            FlowTabUITestSwitcherSearchConfirmationPolicy
                .applicationEvidenceLaunchArguments,
            [
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs"
            ]
        )
        XCTAssertEqual(
            FlowTabUITestSwitcherSearchConfirmationPolicy
                .confirmationWatchdog,
            4,
            accuracy: 0.000_001
        )

        let expectedQuery = "Docs \"Final\""
        let marker =
            FlowTabUITestSwitcherSearchConfirmationEvidence
                .markedTextClearedMarker(
                    expectedQuery: expectedQuery
                )
        XCTAssertEqual(
            marker,
            "markedText changed=0 active=1 inputFocused=1 "
                + "query=\(expectedQuery.debugDescription)"
        )
        XCTAssertEqual(
            searchConfirmationSnapshot(
                searchInputExists: false,
                contents: marker
            ).outcome(
                satisfying: .dismissalOrMarkedTextClear,
                markedTextClearedMarker: marker
            ),
            .searchInputDismissed
        )
        XCTAssertEqual(
            searchConfirmationSnapshot(
                searchInputExists: true,
                contents: marker
            ).outcome(
                satisfying: .dismissalOrMarkedTextClear,
                markedTextClearedMarker: marker
            ),
            .markedTextCleared
        )
        XCTAssertNil(
            searchConfirmationSnapshot(
                searchInputExists: true,
                contents: marker
            ).outcome(
                satisfying: .dismissal,
                markedTextClearedMarker: marker
            )
        )
        XCTAssertNil(
            searchConfirmationSnapshot(
                searchInputExists: true,
                contents:
                    "markedText changed=0 active=1 "
                    + "inputFocused=1 query=\"Other\""
            ).outcome(
                satisfying: .dismissalOrMarkedTextClear,
                markedTextClearedMarker: marker
            )
        )
    }

    func testSwitcherSearchConfirmationUsesInitialDismissalAndCancels() {
        var cancellationCount = 0
        let owner =
            FlowTabUITestSwitcherSearchConfirmationObservationOwner(
                expectedQuery: "Docs",
                requirement: .dismissalOrMarkedTextClear,
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    self.searchConfirmationSnapshot(
                        searchInputExists: false
                    )
                }
            )
        owner.start()

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSwitcherSearchConfirmationTestPolicy
                    .immediateWatchdog
        )

        XCTAssertEqual(evidence?.source, .initialReadback)
        XCTAssertEqual(
            owner.resolvedOutcome,
            .searchInputDismissed
        )
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSwitcherSearchConfirmationRequiresExactMarkedTextEvidence() {
        let expectedQuery = "Docs"
        let marker =
            FlowTabUITestSwitcherSearchConfirmationEvidence
                .markedTextClearedMarker(
                    expectedQuery: expectedQuery
                )
        var snapshot = searchConfirmationSnapshot(
            searchInputExists: true
        )
        var eventHandler:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSwitcherSearchConfirmationObservationOwner(
                expectedQuery: expectedQuery,
                requirement: .dismissalOrMarkedTextClear,
                observationRegistration: { callback in
                    eventHandler = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        snapshot = searchConfirmationSnapshot(
            searchInputExists: true,
            contents:
                "markedText changed=0 active=1 "
                + "inputFocused=1 query=\"Other\""
        )
        eventHandler?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = searchConfirmationSnapshot(
            searchInputExists: true,
            contents: marker
        )
        eventHandler?(.notificationReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSwitcherSearchConfirmationTestPolicy
                    .immediateWatchdog
        )

        XCTAssertEqual(evidence?.source, .notificationReadback)
        XCTAssertEqual(owner.resolvedOutcome, .markedTextCleared)
        XCTAssertEqual(cancellationCount, 1)
        snapshot = searchConfirmationSnapshot(
            searchInputExists: false,
            contents: marker
        )
        eventHandler?(.notificationReadback)
        XCTAssertEqual(owner.resolvedOutcome, .markedTextCleared)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSwitcherSearchConfirmationScheduledReadbackPreservesOutcome() {
        var snapshot = searchConfirmationSnapshot(
            searchInputExists: true
        )
        let owner =
            FlowTabUITestSwitcherSearchConfirmationObservationOwner(
                expectedQuery: "Docs",
                requirement: .dismissal,
                observationRegistration:
                    FlowTabUITestConditionReadbackScheduler
                        .mainRunLoopRegistration(
                            cadence:
                                FlowTabUITestSwitcherSearchConfirmationTestPolicy
                                    .scheduledReadbackCadence
                        ),
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        DispatchQueue.main.async {
            snapshot = self.searchConfirmationSnapshot(
                searchInputExists: false
            )
        }
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSwitcherSearchConfirmationTestPolicy
                    .scheduledReadbackWatchdog
        )

        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(
            owner.resolvedOutcome,
            .searchInputDismissed
        )
    }

    func testSwitcherSearchConfirmationWatchdogReportsFinalEvidence() {
        var cancellationCount = 0
        let owner =
            FlowTabUITestSwitcherSearchConfirmationObservationOwner(
                expectedQuery: "Docs",
                requirement: .dismissalOrMarkedTextClear,
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    self.searchConfirmationSnapshot(
                        searchInputExists: true,
                        contents: "unrelated"
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherSearchConfirmationTestPolicy
                        .immediateWatchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "searchInputExists=true"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "missingMarkedTextClearMarker=true"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "waitResult="
            )
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSwitcherSearchConfirmationLifecycleUnderPressure() {
        for iteration in 0..<FlowTabUITestSwitcherSearchConfirmationTestPolicy
            .pressureIterations
        {
            let expectedQuery = "query-\(iteration)"
            var snapshot = searchConfirmationSnapshot(
                searchInputExists: true
            )
            var eventHandlers: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var cancellationCount = 0
            let owner =
                FlowTabUITestSwitcherSearchConfirmationObservationOwner(
                    expectedQuery: expectedQuery,
                    requirement: .dismissalOrMarkedTextClear,
                    observationRegistration: { callback in
                        eventHandlers.append(callback)
                        return FlowTabUITestObservationCancellation {
                            cancellationCount += 1
                        }
                    },
                    readback: { snapshot }
                )

            owner.start()
            let staleHandler = eventHandlers[0]
            owner.cancel()
            owner.start()
            let currentHandler = eventHandlers[1]
            staleHandler(.notificationReadback)
            XCTAssertNil(owner.resolvedEvidence)

            let expectedOutcome:
                FlowTabUITestSwitcherSearchConfirmationOutcome
            if iteration.isMultiple(of: 2) {
                snapshot = searchConfirmationSnapshot(
                    searchInputExists: false
                )
                expectedOutcome = .searchInputDismissed
            } else {
                snapshot = searchConfirmationSnapshot(
                    searchInputExists: true,
                    contents:
                        FlowTabUITestSwitcherSearchConfirmationEvidence
                        .markedTextClearedMarker(
                            expectedQuery: expectedQuery
                        )
                )
                expectedOutcome = .markedTextCleared
            }
            currentHandler(.notificationReadback)
            currentHandler(.notificationReadback)

            XCTAssertEqual(owner.resolvedOutcome, expectedOutcome)
            XCTAssertEqual(owner.resolvedEvidence?.generation, 2)
            XCTAssertEqual(cancellationCount, 2)
            owner.cancel()
            staleHandler(.notificationReadback)
            currentHandler(.notificationReadback)
            XCTAssertEqual(cancellationCount, 2)
        }
    }

    private func searchConfirmationSnapshot(
        searchInputExists: Bool,
        contents: String = ""
    ) -> FlowTabUITestSwitcherSearchConfirmationSnapshot {
        FlowTabUITestSwitcherSearchConfirmationSnapshot(
            searchInputExists: searchInputExists,
            runtimeLog: FlowTabUITestRuntimeLogSnapshot(
                baselineFileEventGeneration: 0,
                fileEventGeneration: 0,
                contents: contents
            )
        )
    }
}
