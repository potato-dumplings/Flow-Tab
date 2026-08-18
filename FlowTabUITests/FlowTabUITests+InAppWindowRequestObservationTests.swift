import CoreGraphics
import Foundation
import XCTest

private enum FlowTabUITestInAppWindowRequestObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

private func makeInAppWindowRequestLine(
    appID: String = "com.example.fixture.chrome",
    processIdentifier: pid_t = 4_321,
    windowIDProcessIdentifier: pid_t = 4_321,
    windowNumber: CGWindowID = 765,
    cgWindowNumber: CGWindowID = 765,
    title: String = "Chrome Normal Tab",
    sticky: String = "true",
    source: String = "stickyBinding",
    level: String = "INFO",
    category: String = "Activation"
) -> String {
    "[12:00:00.000] [\(level)] [\(category)] "
        + "window-request appID=\(appID) "
        + "pid=\(processIdentifier) "
        + "windowID=cg:\(windowIDProcessIdentifier):\(windowNumber) "
        + "title=\(title) mode=normal "
        + "identity=ax:ax:\(processIdentifier):0 "
        + "cg=\(cgWindowNumber) handle=ax:\(processIdentifier):0 "
        + "ax=1 fallbackAX=0 spaces=[1] frame=1,2,3x4 "
        + "restore=false sticky=\(sticky) source=\(source) "
        + "publicAXRecovery=1"
}

private func makeInAppWindowRequestRuntimeLogSnapshot(
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
    func testInAppWindowRequestPolicyPreservesCompatibleWatchdog() {
        XCTAssertEqual(
            FlowTabUITestInAppWindowRequestObservationPolicy
                .watchdog,
            8
        )
    }

    func testInAppWindowRequestRecordRequiresAtomicExactIdentity() {
        XCTAssertEqual(
            FlowTabUITestInAppWindowRequestRecord.records(
                in: makeInAppWindowRequestLine()
            ),
            [
                FlowTabUITestInAppWindowRequestRecord(
                    appID: "com.example.fixture.chrome",
                    processIdentifier: 4_321,
                    windowID: "cg:4321:765",
                    windowNumber: 765,
                    title: "Chrome Normal Tab"
                )
            ]
        )

        let invalidLines = [
            makeInAppWindowRequestLine(
                windowIDProcessIdentifier: 4_322
            ),
            makeInAppWindowRequestLine(cgWindowNumber: 766),
            makeInAppWindowRequestLine(sticky: "false"),
            makeInAppWindowRequestLine(
                source: "publicExactMatch"
            ),
            makeInAppWindowRequestLine(processIdentifier: 0),
            makeInAppWindowRequestLine(level: "DEBUG"),
            makeInAppWindowRequestLine(category: "RuntimeFacts")
        ]
        XCTAssertTrue(
            FlowTabUITestInAppWindowRequestRecord.records(
                in: invalidLines.joined(separator: "\n")
            )
            .isEmpty
        )
    }

    func testInAppWindowRequestResolvesFromInitialReadback() {
        var cancellationCount = 0
        let owner = FlowTabUITestInAppWindowRequestObservationOwner(
            expectedAppID: "com.example.fixture.chrome",
            expectedProcessIdentifier: 4_321,
            expectedWindowID: "cg:4321:765",
            expectedWindowNumber: 765,
            expectedTitle: "Chrome Normal Tab",
            observationRegistration: { _ in
                FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: {
                makeInAppWindowRequestRuntimeLogSnapshot(
                    contents: makeInAppWindowRequestLine()
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
            owner.resolvedEvidence?.value.windowNumber,
            765
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testInAppWindowRequestRequiresEveryExactFieldOnEvent() {
        var contents = ""
        var generation: UInt64 = 1
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner = FlowTabUITestInAppWindowRequestObservationOwner(
            expectedAppID: "com.example.fixture.chrome",
            expectedProcessIdentifier: 4_321,
            expectedWindowID: "cg:4321:765",
            expectedWindowNumber: 765,
            expectedTitle: "Chrome Normal Tab",
            observationRegistration: { registered in
                callback = registered
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: {
                makeInAppWindowRequestRuntimeLogSnapshot(
                    contents: contents,
                    generation: generation
                )
            }
        )
        owner.start()
        defer { owner.cancel() }

        contents = [
            makeInAppWindowRequestLine(appID: "other.app"),
            makeInAppWindowRequestLine(
                processIdentifier: 4_322,
                windowIDProcessIdentifier: 4_322
            ),
            makeInAppWindowRequestLine(
                windowNumber: 766,
                cgWindowNumber: 766
            ),
            makeInAppWindowRequestLine(
                title: "Chrome Fullscreen Tab"
            )
        ].joined(separator: "\n")
        generation += 1
        callback?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)

        contents += "\n" + makeInAppWindowRequestLine()
        generation += 1
        callback?(.notificationReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .notificationReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.windowID,
            "cg:4321:765"
        )
        XCTAssertEqual(cancellationCount, 1)
        callback?(.notificationReadback)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testInAppWindowRequestCancellationRejectsLateEvent() {
        var contents = ""
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner = FlowTabUITestInAppWindowRequestObservationOwner(
            expectedAppID: "com.example.fixture.chrome",
            expectedProcessIdentifier: 4_321,
            expectedWindowID: "cg:4321:765",
            expectedWindowNumber: 765,
            expectedTitle: "Chrome Normal Tab",
            observationRegistration: { registered in
                callback = registered
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: {
                makeInAppWindowRequestRuntimeLogSnapshot(
                    contents: contents
                )
            }
        )
        owner.start()
        owner.cancel()

        contents = makeInAppWindowRequestLine()
        callback?(.notificationReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
        XCTAssertEqual(cancellationCount, 1)
    }

    func testInAppWindowRequestWatchdogReportsLastEvidence() {
        let owner = FlowTabUITestInAppWindowRequestObservationOwner(
            expectedAppID: "com.example.fixture.chrome",
            expectedProcessIdentifier: 4_321,
            expectedWindowID: "cg:4321:765",
            expectedWindowNumber: 765,
            expectedTitle: "Chrome Normal Tab",
            observationRegistration: nil,
            readback: {
                makeInAppWindowRequestRuntimeLogSnapshot(
                    contents: makeInAppWindowRequestLine(
                        processIdentifier: 4_322,
                        windowIDProcessIdentifier: 4_322
                    )
                )
            }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestInAppWindowRequestObservationTestPolicy
                    .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "expectedPID=4321"
            ),
            owner.diagnosticSummary
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("pid=4322"),
            owner.diagnosticSummary
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "waitResult=timedOut"
            ),
            owner.diagnosticSummary
        )
    }

    func testInAppWindowRequestLifecycleUnderPressure() {
        for iteration in
            0..<FlowTabUITestInAppWindowRequestObservationTestPolicy
                .pressureIterations
        {
            var contents = ""
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var cancellationCount = 0
            let owner = FlowTabUITestInAppWindowRequestObservationOwner(
                expectedAppID: "com.example.fixture.chrome",
                expectedProcessIdentifier: 4_321,
                expectedWindowID: "cg:4321:765",
                expectedWindowNumber: 765,
                expectedTitle: "Chrome Normal Tab",
                observationRegistration: { callback in
                    callbacks.append(callback)
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    makeInAppWindowRequestRuntimeLogSnapshot(
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

            contents = makeInAppWindowRequestLine()
            staleCallback(.notificationReadback)
            XCTAssertNil(owner.resolvedEvidence)
            currentCallback(.notificationReadback)

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
