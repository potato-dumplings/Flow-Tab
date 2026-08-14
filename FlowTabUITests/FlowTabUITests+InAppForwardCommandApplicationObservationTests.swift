import Foundation
import XCTest

private enum
    FlowTabUITestInAppForwardCommandApplicationObservationTestPolicy
{
    static let watchdog: TimeInterval = 0.01
}

private func makeInAppHotkeyAdvanceApplicationRecord(
    direction: String = "forward",
    key: String = "tabForward",
    sequence: UInt64 = 7,
    inputGeneration: UInt64 = 9,
    sourceRegistrationGeneration: UInt64 = 3,
    sessionGeneration: Int = 5,
    previousWindowID: String = "cg:420:7001",
    selectedWindowID: String = "cg:420:7002"
) -> String {
    "[12:00:00.000] [DEBUG] [InputTrace] "
        + "inAppHotkeyAdvance result=applied "
        + "dir=\(direction) key=\(key) "
        + "route=inAppWindowSwitcher "
        + "source=7A9D58C2-46B3-43EF-935B-6E6C050E4D53 "
        + "sequence=\(sequence) "
        + "inputGeneration=\(inputGeneration) "
        + "sourceRegistrationGeneration="
        + "\(sourceRegistrationGeneration) "
        + "sessionGeneration=\(sessionGeneration) "
        + "previousWindowID=\(previousWindowID) "
        + "selectedWindowID=\(selectedWindowID)"
}

private func makeInAppForwardApplicationRuntimeLogSnapshot(
    contents: String,
    generation: UInt64 = 1
) -> FlowTabUITestRuntimeLogSnapshot {
    FlowTabUITestRuntimeLogSnapshot(
        baselineFileEventGeneration: 0,
        fileEventGeneration: generation,
        contents: contents
    )
}

extension FlowTabUITests {
    func testInAppForwardCommandApplicationPolicyPreservesCompatibleWatchdog() {
        XCTAssertEqual(
            FlowTabUITestInAppForwardCommandApplicationObservationPolicy
                .watchdog,
            8
        )
    }

    func testInAppHotkeyAdvanceApplicationRecordRequiresOneExactRecord() {
        let exact = makeInAppHotkeyAdvanceApplicationRecord()
        let records =
            FlowTabUITestInAppHotkeyAdvanceApplicationRecord
                .records(
                    in: "unrelated\n\(exact)\n"
                )

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.direction, "forward")
        XCTAssertEqual(records.first?.key, "tabForward")
        XCTAssertEqual(records.first?.sequence, 7)
        XCTAssertEqual(records.first?.inputGeneration, 9)
        XCTAssertEqual(
            records.first?.sourceRegistrationGeneration,
            3
        )
        XCTAssertEqual(records.first?.sessionGeneration, 5)
        XCTAssertEqual(
            records.first?.previousWindowID,
            "cg:420:7001"
        )
        XCTAssertEqual(
            records.first?.selectedWindowID,
            "cg:420:7002"
        )

        XCTAssertTrue(
            FlowTabUITestInAppHotkeyAdvanceApplicationRecord
                .records(
                    in:
                        "inAppHotkeyPressed dir=forward "
                        + "panelVisible=1\n"
                        + "advance key=tabForward\n"
                )
                .isEmpty
        )
        XCTAssertTrue(
            FlowTabUITestInAppHotkeyAdvanceApplicationRecord
                .records(in: exact + " unexpected=field")
                .isEmpty
        )
        XCTAssertTrue(
            FlowTabUITestInAppHotkeyAdvanceApplicationRecord
                .records(
                    in: exact.replacingOccurrences(
                        of:
                            "sequence=7 inputGeneration=9",
                        with:
                            "inputGeneration=9 sequence=7"
                    )
                )
                .isEmpty
        )
    }

    func testInAppForwardCommandApplicationRejectsInitialAndOutOfOrderRecords() {
        var contents =
            makeInAppHotkeyAdvanceApplicationRecord()
        var generation: UInt64 = 1
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestInAppForwardCommandApplicationObservationOwner(
                expectedPreviousWindowID: "cg:420:7001",
                observationRegistration: { registered in
                    callback = registered
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    makeInAppForwardApplicationRuntimeLogSnapshot(
                        contents: contents,
                        generation: generation
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        owner.markTriggerStarted()
        XCTAssertNil(owner.resolvedEvidence)

        contents += "\n" +
            makeInAppHotkeyAdvanceApplicationRecord(
                sequence: 8,
                inputGeneration: 10,
                previousWindowID: "cg:420:7999",
                selectedWindowID: "cg:420:7003"
            )
        generation += 1
        callback?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)

        contents += "\n" +
            makeInAppHotkeyAdvanceApplicationRecord(
                sequence: 9,
                inputGeneration: 11,
                previousWindowID: "cg:420:7001",
                selectedWindowID: "cg:420:7004"
            )
        generation += 1
        callback?(.notificationReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .notificationReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.selectedWindowID,
            "cg:420:7004"
        )
        XCTAssertEqual(cancellationCount, 1)

        callback?(.notificationReadback)
        XCTAssertEqual(
            owner.resolvedEvidence?.value.sequence,
            9
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testInAppForwardCommandApplicationResolvesFromTriggerReadback() {
        var contents = ""
        let owner =
            FlowTabUITestInAppForwardCommandApplicationObservationOwner(
                expectedPreviousWindowID: "cg:420:7001",
                observationRegistration: nil,
                readback: {
                    makeInAppForwardApplicationRuntimeLogSnapshot(
                        contents: contents
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        contents = makeInAppHotkeyAdvanceApplicationRecord()
        owner.markTriggerStarted()

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.previousWindowID,
            "cg:420:7001"
        )
    }

    func testInAppForwardCommandApplicationCancellationRejectsLateEvent() {
        var contents = ""
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestInAppForwardCommandApplicationObservationOwner(
                expectedPreviousWindowID: "cg:420:7001",
                observationRegistration: { registered in
                    callback = registered
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    makeInAppForwardApplicationRuntimeLogSnapshot(
                        contents: contents
                    )
                }
            )
        owner.start()
        owner.markTriggerStarted()
        owner.cancel()

        contents = makeInAppHotkeyAdvanceApplicationRecord()
        callback?(.notificationReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testInAppForwardCommandApplicationWatchdogReportsLastEvidence() {
        let owner =
            FlowTabUITestInAppForwardCommandApplicationObservationOwner(
                expectedPreviousWindowID: "cg:420:7001",
                observationRegistration: nil,
                readback: {
                    makeInAppForwardApplicationRuntimeLogSnapshot(
                        contents:
                            makeInAppHotkeyAdvanceApplicationRecord(
                                direction: "backward",
                                key: "tabBackward"
                            )
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }
        owner.markTriggerStarted()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestInAppForwardCommandApplicationObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "expectedPreviousWindowID=cg:420:7001"
            ),
            owner.diagnosticSummary
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "dir=backward key=tabBackward"
            ),
            owner.diagnosticSummary
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "waitResult=timedOut"
            ),
            owner.diagnosticSummary
        )
    }
}
