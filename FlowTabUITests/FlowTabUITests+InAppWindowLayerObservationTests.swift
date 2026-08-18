import CoreGraphics
import Foundation
import XCTest

private enum FlowTabUITestInAppWindowLayerObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

private func makeInAppWindowLayerLine(
    appName: String = "Chrome Fixture",
    processIdentifier: pid_t = 4_321,
    windowIDProcessIdentifier: pid_t = 4_321,
    windowNumber: CGWindowID = 765,
    cgWindowNumber: CGWindowID = 765,
    title: String = "Chrome Normal Tab",
    sticky: Int = 1,
    source: String = "stickyBinding",
    spaceEvidence: String = "observed",
    level: String = "DEBUG",
    category: String = "RuntimeFacts"
) -> String {
    "[12:00:00.000] [\(level)] [\(category)] "
        + "window-entries app=\(appName) "
        + "pid=\(processIdentifier) ax=1 entries=1 "
        + "cgOnly=0 sticky=\(sticky) detail=["
        + "0:id=cg:\(windowIDProcessIdentifier):\(windowNumber)"
        + ":title=\(title):mode=normal"
        + ":identity=ax:ax:\(processIdentifier):0"
        + ":handle=ax:\(processIdentifier):0:ax=1"
        + ":cg=\(cgWindowNumber):sticky=\(sticky)"
        + ":source=\(source):spaceEvidence=\(spaceEvidence)"
        + ":publicAXRecovery=1:spaces=[1]:on"
        + ":minimized=0:frame=1,2,3x4]"
}

private func makeInAppWindowLayerRuntimeLogSnapshot(
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
    func testInAppWindowLayerPolicyPreservesCompatibleWatchdog() {
        XCTAssertEqual(
            FlowTabUITestInAppWindowLayerObservationPolicy
                .watchdog,
            8
        )
    }

    func testInAppWindowLayerRecordRequiresAtomicExactIdentity() {
        let records = FlowTabUITestInAppWindowLayerRecord.records(
            in: [
                makeInAppWindowLayerLine(),
                makeInAppWindowLayerLine(
                    windowNumber: 766,
                    cgWindowNumber: 766,
                    title: "Chrome Fullscreen Tab",
                    spaceEvidence: "inferredFromTopology"
                )
            ].joined(separator: "\n")
        )

        XCTAssertEqual(
            records,
            [
                FlowTabUITestInAppWindowLayerRecord(
                    appName: "Chrome Fixture",
                    processIdentifier: 4_321,
                    windowID: "cg:4321:765",
                    windowNumber: 765,
                    title: "Chrome Normal Tab",
                    spaceEvidence: .observed
                ),
                FlowTabUITestInAppWindowLayerRecord(
                    appName: "Chrome Fixture",
                    processIdentifier: 4_321,
                    windowID: "cg:4321:766",
                    windowNumber: 766,
                    title: "Chrome Fullscreen Tab",
                    spaceEvidence: .inferredFromTopology
                )
            ]
        )

        let invalidLines = [
            makeInAppWindowLayerLine(
                windowIDProcessIdentifier: 4_322
            ),
            makeInAppWindowLayerLine(cgWindowNumber: 766),
            makeInAppWindowLayerLine(sticky: 0),
            makeInAppWindowLayerLine(source: "publicExactMatch"),
            makeInAppWindowLayerLine(
                spaceEvidence:
                    "inferredFromFullscreenGeometry"
            ),
            makeInAppWindowLayerLine(processIdentifier: 0),
            makeInAppWindowLayerLine(level: "INFO"),
            makeInAppWindowLayerLine(category: "AXMatch")
        ]
        XCTAssertTrue(
            FlowTabUITestInAppWindowLayerRecord.records(
                in: invalidLines.joined(separator: "\n")
            )
            .isEmpty
        )
    }

    func testInAppWindowLayerResolvesFromInitialReadback() {
        var cancellationCount = 0
        let owner = FlowTabUITestInAppWindowLayerObservationOwner(
            expectedAppName: "Chrome Fixture",
            expectedProcessIdentifier: 4_321,
            expectedTitle: "Chrome Normal Tab",
            observationRegistration: { _ in
                FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: {
                makeInAppWindowLayerRuntimeLogSnapshot(
                    contents: makeInAppWindowLayerLine()
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

    func testInAppWindowLayerRequiresExactAppPIDAndTitleOnEvent() {
        var contents = ""
        var generation: UInt64 = 1
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner = FlowTabUITestInAppWindowLayerObservationOwner(
            expectedAppName: "Chrome Fixture",
            expectedProcessIdentifier: 4_321,
            expectedTitle: "Chrome Normal Tab",
            observationRegistration: { registered in
                callback = registered
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: {
                makeInAppWindowLayerRuntimeLogSnapshot(
                    contents: contents,
                    generation: generation
                )
            }
        )
        owner.start()
        defer { owner.cancel() }

        contents = [
            makeInAppWindowLayerLine(
                appName: "Other Fixture"
            ),
            makeInAppWindowLayerLine(
                processIdentifier: 4_322,
                windowIDProcessIdentifier: 4_322
            ),
            makeInAppWindowLayerLine(
                title: "Chrome Fullscreen Tab"
            )
        ].joined(separator: "\n")
        generation += 1
        callback?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)

        contents += "\n" + makeInAppWindowLayerLine(
            windowNumber: 768,
            cgWindowNumber: 768
        )
        generation += 1
        callback?(.notificationReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .notificationReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.windowID,
            "cg:4321:768"
        )
        XCTAssertEqual(cancellationCount, 1)
        callback?(.notificationReadback)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testInAppWindowLayerCancellationRejectsLateEvent() {
        var contents = ""
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner = FlowTabUITestInAppWindowLayerObservationOwner(
            expectedAppName: "Chrome Fixture",
            expectedProcessIdentifier: 4_321,
            expectedTitle: "Chrome Normal Tab",
            observationRegistration: { registered in
                callback = registered
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: {
                makeInAppWindowLayerRuntimeLogSnapshot(
                    contents: contents
                )
            }
        )
        owner.start()
        owner.cancel()

        contents = makeInAppWindowLayerLine()
        callback?(.notificationReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
        XCTAssertEqual(cancellationCount, 1)
    }

    func testInAppWindowLayerWatchdogReportsLastEvidence() {
        let owner = FlowTabUITestInAppWindowLayerObservationOwner(
            expectedAppName: "Chrome Fixture",
            expectedProcessIdentifier: 4_321,
            expectedTitle: "Chrome Normal Tab",
            observationRegistration: nil,
            readback: {
                makeInAppWindowLayerRuntimeLogSnapshot(
                    contents: makeInAppWindowLayerLine(
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
                    FlowTabUITestInAppWindowLayerObservationTestPolicy
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

    func testInAppWindowLayerLifecycleUnderPressure() {
        for iteration in
            0..<FlowTabUITestInAppWindowLayerObservationTestPolicy
                .pressureIterations
        {
            var contents = ""
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var cancellationCount = 0
            let owner = FlowTabUITestInAppWindowLayerObservationOwner(
                expectedAppName: "Chrome Fixture",
                expectedProcessIdentifier: 4_321,
                expectedTitle: "Chrome Normal Tab",
                observationRegistration: { callback in
                    callbacks.append(callback)
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    makeInAppWindowLayerRuntimeLogSnapshot(
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

            contents = makeInAppWindowLayerLine()
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
