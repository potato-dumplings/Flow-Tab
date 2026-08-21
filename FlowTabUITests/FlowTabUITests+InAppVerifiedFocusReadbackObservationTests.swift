import CoreGraphics
import Foundation
import XCTest

private enum
    FlowTabUITestInAppVerifiedFocusReadbackObservationTestPolicy
{
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

private func makeInAppVerifiedFocusReadbackLine(
    windowIDProcessIdentifier: pid_t = 4_321,
    windowNumber: CGWindowID = 765,
    cgWindowNumber: CGWindowID = 765,
    axProcessIdentifier: pid_t = 4_321,
    axWindowIndex: Int = 0,
    confidence: String = "sticky->exact",
    source: String = "stickyBinding->verifiedFocusReadback",
    verifiedFocusFallbackAX: Int = 0,
    level: String = "DEBUG",
    category: String = "AXMatch"
) -> String {
    "[12:00:00.000] [\(level)] [\(category)] "
        + "binding-confidence-change "
        + "windowID=cg:\(windowIDProcessIdentifier):\(windowNumber) "
        + "cg=\(cgWindowNumber) "
        + "ax=ax:\(axProcessIdentifier):\(axWindowIndex) "
        + "confidence=\(confidence) source=\(source) "
        + "verifiedFocusFallbackAX=\(verifiedFocusFallbackAX)"
}

private func makeInAppVerifiedFocusReadbackRuntimeLogSnapshot(
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
    func testInAppVerifiedFocusReadbackPolicyPreservesCompatibleWatchdog() {
        XCTAssertEqual(
            FlowTabUITestInAppVerifiedFocusReadbackObservationPolicy
                .watchdog,
            8
        )
    }

    func testInAppVerifiedFocusReadbackRecordRequiresAtomicExactTransition() {
        let records =
            FlowTabUITestInAppVerifiedFocusReadbackRecord.records(
                in: [
                    makeInAppVerifiedFocusReadbackLine(),
                    makeInAppVerifiedFocusReadbackLine(
                        windowNumber: 766,
                        cgWindowNumber: 766,
                        axWindowIndex: 1,
                        confidence: "exact->exact",
                        source:
                            "privateExactBridge->verifiedFocusReadback"
                    )
                ].joined(separator: "\n")
            )

        XCTAssertEqual(
            records,
            [
                FlowTabUITestInAppVerifiedFocusReadbackRecord(
                    processIdentifier: 4_321,
                    windowID: "cg:4321:765",
                    windowNumber: 765,
                    axWindowID: "ax:4321:0",
                    reusableWindowEvidence: .stickyBinding
                ),
                FlowTabUITestInAppVerifiedFocusReadbackRecord(
                    processIdentifier: 4_321,
                    windowID: "cg:4321:766",
                    windowNumber: 766,
                    axWindowID: "ax:4321:1",
                    reusableWindowEvidence: .privateExactBridge
                )
            ]
        )

        let invalidLines = [
            makeInAppVerifiedFocusReadbackLine(
                cgWindowNumber: 766
            ),
            makeInAppVerifiedFocusReadbackLine(
                axProcessIdentifier: 4_322
            ),
            makeInAppVerifiedFocusReadbackLine(
                windowIDProcessIdentifier: 0
            ),
            makeInAppVerifiedFocusReadbackLine(
                confidence: "exact->exact"
            ),
            makeInAppVerifiedFocusReadbackLine(
                source:
                    "privateExactBridge->verifiedFocusReadback"
            ),
            makeInAppVerifiedFocusReadbackLine(
                confidence: "exact->exact",
                source:
                    "stickyBinding->verifiedFocusReadback"
            ),
            makeInAppVerifiedFocusReadbackLine(
                source: "publicExactMatch->verifiedFocusReadback"
            ),
            makeInAppVerifiedFocusReadbackLine(
                source: "verifiedFocusReadback->stickyBinding"
            ),
            makeInAppVerifiedFocusReadbackLine(
                verifiedFocusFallbackAX: 1
            ),
            makeInAppVerifiedFocusReadbackLine(level: "INFO"),
            makeInAppVerifiedFocusReadbackLine(
                category: "RuntimeFacts"
            )
        ]
        XCTAssertTrue(
            FlowTabUITestInAppVerifiedFocusReadbackRecord.records(
                in: invalidLines.joined(separator: "\n")
            )
            .isEmpty
        )
    }

    func testInAppVerifiedFocusReadbackRejectsMatchingPretriggerBaseline() {
        var cancellationCount = 0
        let owner =
            FlowTabUITestInAppVerifiedFocusReadbackObservationOwner(
                expectedProcessIdentifier: 4_321,
                expectedWindowID: "cg:4321:765",
                expectedWindowNumber: 765,
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    makeInAppVerifiedFocusReadbackRuntimeLogSnapshot(
                        contents:
                            makeInAppVerifiedFocusReadbackLine()
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        owner.markTriggerStarted()
        owner.markTriggerCompleted()

        XCTAssertEqual(
            owner.baselineIssue,
            .matchingRecordBeforeTrigger
        )
        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 0)
    }

    func testInAppVerifiedFocusReadbackRequiresExactEventAfterTrigger() {
        var contents = ""
        var generation: UInt64 = 1
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestInAppVerifiedFocusReadbackObservationOwner(
                expectedProcessIdentifier: 4_321,
                expectedWindowID: "cg:4321:765",
                expectedWindowNumber: 765,
                observationRegistration: { registered in
                    callback = registered
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    makeInAppVerifiedFocusReadbackRuntimeLogSnapshot(
                        contents: contents,
                        generation: generation
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }
        owner.markTriggerStarted()
        owner.markTriggerCompleted()

        contents = [
            makeInAppVerifiedFocusReadbackLine(
                windowIDProcessIdentifier: 4_322,
                axProcessIdentifier: 4_322
            ),
            makeInAppVerifiedFocusReadbackLine(
                windowNumber: 766,
                cgWindowNumber: 766
            )
        ].joined(separator: "\n")
        generation += 1
        callback?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)

        contents += "\n" + makeInAppVerifiedFocusReadbackLine()
        generation += 1
        callback?(.notificationReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .notificationReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.axWindowID,
            "ax:4321:0"
        )
        XCTAssertEqual(cancellationCount, 1)
        callback?(.notificationReadback)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testInAppVerifiedFocusReadbackTriggerReadbackClosesDeliveryRace() {
        var contents = ""
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestInAppVerifiedFocusReadbackObservationOwner(
                expectedProcessIdentifier: 4_321,
                expectedWindowID: "cg:4321:765",
                expectedWindowNumber: 765,
                observationRegistration: { registered in
                    callback = registered
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    makeInAppVerifiedFocusReadbackRuntimeLogSnapshot(
                        contents: contents
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }
        owner.markTriggerStarted()

        contents = makeInAppVerifiedFocusReadbackLine()
        callback?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)

        owner.markTriggerCompleted()
        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.windowID,
            "cg:4321:765"
        )
    }

    func testInAppVerifiedFocusReadbackCancellationRejectsLateEvent() {
        var contents = ""
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestInAppVerifiedFocusReadbackObservationOwner(
                expectedProcessIdentifier: 4_321,
                expectedWindowID: "cg:4321:765",
                expectedWindowNumber: 765,
                observationRegistration: { registered in
                    callback = registered
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    makeInAppVerifiedFocusReadbackRuntimeLogSnapshot(
                        contents: contents
                    )
                }
            )
        owner.start()
        owner.markTriggerStarted()
        owner.cancel()

        contents = makeInAppVerifiedFocusReadbackLine()
        callback?(.notificationReadback)
        owner.markTriggerCompleted()

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
        XCTAssertEqual(cancellationCount, 1)
    }

    func testInAppVerifiedFocusReadbackWatchdogReportsLastEvidence() {
        let owner =
            FlowTabUITestInAppVerifiedFocusReadbackObservationOwner(
                expectedProcessIdentifier: 4_321,
                expectedWindowID: "cg:4321:765",
                expectedWindowNumber: 765,
                observationRegistration: nil,
                readback: {
                    makeInAppVerifiedFocusReadbackRuntimeLogSnapshot(
                        contents:
                            makeInAppVerifiedFocusReadbackLine(
                                windowIDProcessIdentifier: 4_322,
                                axProcessIdentifier: 4_322
                            )
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }
        owner.markTriggerStarted()
        owner.markTriggerCompleted()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestInAppVerifiedFocusReadbackObservationTestPolicy
                    .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("expectedPID=4321"),
            owner.diagnosticSummary
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("pid=4322"),
            owner.diagnosticSummary
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("waitResult=timedOut"),
            owner.diagnosticSummary
        )
    }

    func testInAppVerifiedFocusReadbackLifecycleUnderPressure() {
        for iteration in
            0..<FlowTabUITestInAppVerifiedFocusReadbackObservationTestPolicy
                .pressureIterations
        {
            var contents = ""
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var cancellationCount = 0
            let owner =
                FlowTabUITestInAppVerifiedFocusReadbackObservationOwner(
                    expectedProcessIdentifier: 4_321,
                    expectedWindowID: "cg:4321:765",
                    expectedWindowNumber: 765,
                    observationRegistration: { callback in
                        callbacks.append(callback)
                        return FlowTabUITestObservationCancellation {
                            cancellationCount += 1
                        }
                    },
                    readback: {
                        makeInAppVerifiedFocusReadbackRuntimeLogSnapshot(
                            contents: contents,
                            generation: UInt64(iteration + 1)
                        )
                    }
                )

            owner.start()
            let staleCallback = callbacks[0]
            owner.cancel()
            owner.start()
            let currentCallback = callbacks[1]
            owner.markTriggerStarted()

            contents = makeInAppVerifiedFocusReadbackLine()
            staleCallback(.notificationReadback)
            XCTAssertNil(owner.resolvedEvidence)
            currentCallback(.notificationReadback)
            XCTAssertNil(owner.resolvedEvidence)
            owner.markTriggerCompleted()

            XCTAssertEqual(
                owner.resolvedEvidence?.value.windowNumber,
                765
            )
            XCTAssertEqual(cancellationCount, 2)
            owner.cancel()
            staleCallback(.notificationReadback)
            XCTAssertEqual(cancellationCount, 2)
        }
    }
}
