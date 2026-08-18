import Foundation
import XCTest

private enum FlowTabUITestQuitShortcutObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
}

extension FlowTabUITests {
    func testQuitShortcutTerminationRequestRequiresExactPostTriggerRecord()
        throws
    {
        let watchdog =
            FlowTabUITestRuntimeLogObservationPolicy
                .quitShortcutTerminationRequestWatchdog
        XCTAssertEqual(watchdog, 8)
        XCTAssertTrue(watchdog.isFinite && watchdog > 0)

        let bundleIdentifier = "com.example.fixture+exact"
        let pattern =
            FlowTabUITestRuntimeLogRecordPattern
                .exactTerminationRequest(
                    bundleIdentifier: bundleIdentifier
                )
        let expression = try NSRegularExpression(
            pattern: pattern
        )
        let expectation = FlowTabUITestRuntimeLogExpectation
            .regularExpression(
                expression,
                pattern: pattern,
                description: "exact termination request"
            )
        let matchingSnapshot = FlowTabUITestRuntimeLogSnapshot(
            baselineFileEventGeneration: 10,
            fileEventGeneration: 11,
            contents:
                "[DEBUG] terminate request app=Fixture "
                + "appID=\(bundleIdentifier) sent=true\n"
        )
        XCTAssertTrue(expectation.isSatisfied(by: matchingSnapshot))
        XCTAssertFalse(
            expectation.isSatisfied(
                by: FlowTabUITestRuntimeLogSnapshot(
                    baselineFileEventGeneration: 10,
                    fileEventGeneration: 11,
                    contents:
                        "terminate request app=Fixture\n"
                        + "appID=\(bundleIdentifier) sent=true\n"
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: FlowTabUITestRuntimeLogSnapshot(
                    baselineFileEventGeneration: 10,
                    fileEventGeneration: 11,
                    contents:
                        "terminate request app=Fixture "
                        + "appID=com.example.fixtureXexact "
                        + "sent=true\n"
                )
            )
        )

        var acceptsResolution = false
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner = FlowTabUITestRuntimeLogObservationOwner(
            expectation: expectation,
            observationRegistration: { registered in
                callback = registered
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            acceptsResolution: {
                acceptsResolution
            },
            readback: { matchingSnapshot }
        )
        owner.start()

        XCTAssertNil(owner.resolvedEvidence)
        callback?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)
        acceptsResolution = true
        owner.requestReadback(source: .triggerReadback)
        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value,
            matchingSnapshot
        )

        owner.cancel()
        owner.cancel()
        XCTAssertEqual(cancellationCount, 1)
    }

    func testQuitShortcutTerminationRequestAcceptsPostTriggerFileEvent()
        throws
    {
        let bundleIdentifier = "com.example.fixture.event"
        let pattern =
            FlowTabUITestRuntimeLogRecordPattern
                .exactTerminationRequest(
                    bundleIdentifier: bundleIdentifier
                )
        let expression = try NSRegularExpression(
            pattern: pattern
        )
        var snapshot = FlowTabUITestRuntimeLogSnapshot(
            baselineFileEventGeneration: 20,
            fileEventGeneration: 20,
            contents: ""
        )
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner = FlowTabUITestRuntimeLogObservationOwner(
            expectation:
                .regularExpression(
                    expression,
                    pattern: pattern,
                    description:
                        "exact termination request"
                ),
            observationRegistration: { registered in
                callback = registered
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: { snapshot }
        )
        owner.start()

        XCTAssertNil(owner.resolvedEvidence)
        snapshot = FlowTabUITestRuntimeLogSnapshot(
            baselineFileEventGeneration: 20,
            fileEventGeneration: 21,
            contents:
                "terminate request app=Fixture "
                + "appID=\(bundleIdentifier) sent=true\n"
        )
        callback?(.notificationReadback)

        XCTAssertEqual(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestQuitShortcutObservationTestPolicy
                        .watchdog
            )?.source,
            .notificationReadback
        )
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
        XCTAssertEqual(cancellationCount, 1)
    }

    func testQuitShortcutTerminationRequestWatchdogReportsLastRecord()
        throws
    {
        let bundleIdentifier = "com.example.fixture.watchdog"
        let pattern =
            FlowTabUITestRuntimeLogRecordPattern
                .exactTerminationRequest(
                    bundleIdentifier: bundleIdentifier
                )
        let expression = try NSRegularExpression(
            pattern: pattern
        )
        let owner = FlowTabUITestRuntimeLogObservationOwner(
            expectation:
                .regularExpression(
                    expression,
                    pattern: pattern,
                    description:
                        "exact termination request"
                ),
            observationRegistration: nil,
            readback: {
                FlowTabUITestRuntimeLogSnapshot(
                    baselineFileEventGeneration: 30,
                    fileEventGeneration: 31,
                    contents:
                        "terminate request app=Fixture "
                        + "appID=com.example.fixture.other "
                        + "sent=true\n"
                )
            }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestQuitShortcutObservationTestPolicy
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
                "missingPattern=exact termination request"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "appID=com.example.fixture.other"
            )
        )
    }
}
