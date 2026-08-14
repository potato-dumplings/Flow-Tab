import Foundation
import XCTest

private enum
    FlowTabUITestInAppFilteredArtifactObservationTestPolicy
{
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

private func makeInAppFilteredArtifactLine(
    appName: String = "Chrome Fixture",
    kind: FlowTabUITestInAppFilteredArtifactRecord.Kind =
        .fullscreenHostArtifacts,
    stage: String = "presentation",
    droppedCount: Int = 2,
    processIdentifier: pid_t = 4_321,
    level: String = "DEBUG",
    category: String = "AXMatch",
    suffix: String = ""
) -> String {
    "[12:00:00.000] [\(level)] [\(category)] "
        + "\(appName) \(kind.rawValue) "
        + "stage=\(stage) dropped=\(droppedCount) "
        + "pid=\(processIdentifier)\(suffix)"
}

private func makeInAppFilteredArtifactRuntimeLogSnapshot(
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
    func testInAppFilteredArtifactPolicyPreservesCompatibleWatchdog() {
        XCTAssertEqual(
            FlowTabUITestInAppFilteredArtifactObservationPolicy
                .watchdog,
            8
        )
    }

    func testInAppFilteredArtifactRecordRequiresExactValidRecord() {
        let validSpecifications: [
            (FlowTabUITestInAppFilteredArtifactRecord.Kind, String)
        ] = [
            (.fullscreenHostArtifacts, "pre-dedupe"),
            (.fullscreenHostArtifacts, "presentation"),
            (.fullscreenHostArtifacts, "window-record-projection"),
            (.fullscreenHostArtifacts, "read-model-app-switcher-normalization"),
            (.fullscreenHostArtifacts, "read-model-current-app-normalization"),
            (.fullscreenSiblingArtifacts, "pre-dedupe"),
            (.fullscreenSiblingArtifacts, "presentation"),
            (.fullscreenSiblingArtifacts, "window-record-projection"),
            (.fullscreenSiblingArtifacts, "read-model-app-switcher-normalization"),
            (.fullscreenSiblingArtifacts, "read-model-current-app-normalization"),
            (.fullscreenDuplicateSurfaces, "ordering"),
            (.fullscreenDuplicateSurfaces, "presentation-final"),
            (.fullscreenDuplicateSurfaces, "window-record-projection-final"),
            (.fullscreenDuplicateSurfaces, "read-model-app-switcher-normalization-final"),
            (.fullscreenDuplicateSurfaces, "read-model-current-app-normalization-final"),
            (.cgOnlyCoveredByActivation, "presentation"),
            (.cgOnlyCoveredByActivation, "window-record-projection"),
            (.cgOnlyCoveredByActivation, "read-model-app-switcher-normalization"),
            (.cgOnlyCoveredByActivation, "read-model-current-app-normalization")
        ]
        let validLines = validSpecifications.map { kind, stage in
            makeInAppFilteredArtifactLine(
                kind: kind,
                stage: stage
            )
        }
        let records =
            FlowTabUITestInAppFilteredArtifactRecord.records(
                in: validLines.joined(separator: "\n")
            )

        XCTAssertEqual(records.count, validSpecifications.count)
        XCTAssertEqual(records.first?.appName, "Chrome Fixture")
        XCTAssertEqual(
            records.first?.processIdentifier,
            4_321
        )
        XCTAssertEqual(records.first?.droppedCount, 2)
        XCTAssertEqual(
            records.map(\.kind),
            validSpecifications.map(\.0)
        )
        XCTAssertEqual(
            records.map(\.stage),
            validSpecifications.map(\.1)
        )

        let invalidLines = [
            makeInAppFilteredArtifactLine(
                stage: "unexpected"
            ),
            makeInAppFilteredArtifactLine(
                droppedCount: 0
            ),
            makeInAppFilteredArtifactLine(
                processIdentifier: 0
            ),
            makeInAppFilteredArtifactLine(level: "INFO"),
            makeInAppFilteredArtifactLine(
                suffix: " unexpected=field"
            ),
            makeInAppFilteredArtifactLine(
                kind: .fullscreenDuplicateSurfaces,
                stage: "window-record-projection"
            ),
            makeInAppFilteredArtifactLine(
                kind: .cgOnlyCoveredByActivation,
                stage: "pre-dedupe"
            )
        ]
        XCTAssertTrue(
            FlowTabUITestInAppFilteredArtifactRecord.records(
                in: invalidLines.joined(separator: "\n")
            )
            .isEmpty
        )
    }

    func testInAppFilteredArtifactResolvesFromInitialReadback() {
        var cancellationCount = 0
        let owner =
            FlowTabUITestInAppFilteredArtifactObservationOwner(
                expectedAppName: "Chrome Fixture",
                expectedProcessIdentifier: 4_321,
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    makeInAppFilteredArtifactRuntimeLogSnapshot(
                        contents:
                            makeInAppFilteredArtifactLine()
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
            owner.resolvedEvidence?.value.processIdentifier,
            4_321
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testInAppFilteredArtifactRequiresExactPIDAndAppOnEvent() {
        var contents = ""
        var generation: UInt64 = 1
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestInAppFilteredArtifactObservationOwner(
                expectedAppName: "Chrome Fixture",
                expectedProcessIdentifier: 4_321,
                observationRegistration: { registered in
                    callback = registered
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    makeInAppFilteredArtifactRuntimeLogSnapshot(
                        contents: contents,
                        generation: generation
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        contents = [
            makeInAppFilteredArtifactLine(
                processIdentifier: 4_322
            ),
            makeInAppFilteredArtifactLine(
                appName: "Other Fixture"
            ),
            makeInAppFilteredArtifactLine(
                stage: "unexpected"
            )
        ].joined(separator: "\n")
        generation += 1
        callback?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)

        contents += "\n" + makeInAppFilteredArtifactLine(
            kind: .fullscreenSiblingArtifacts,
            stage: "presentation",
            droppedCount: 5
        )
        generation += 1
        callback?(.notificationReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .notificationReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.kind,
            .fullscreenSiblingArtifacts
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.droppedCount,
            5
        )
        XCTAssertEqual(cancellationCount, 1)
        callback?(.notificationReadback)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testInAppFilteredArtifactCancellationRejectsLateEvent() {
        var contents = ""
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestInAppFilteredArtifactObservationOwner(
                expectedAppName: "Chrome Fixture",
                expectedProcessIdentifier: 4_321,
                observationRegistration: { registered in
                    callback = registered
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    makeInAppFilteredArtifactRuntimeLogSnapshot(
                        contents: contents
                    )
                }
            )
        owner.start()
        owner.cancel()

        contents = makeInAppFilteredArtifactLine()
        callback?(.notificationReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
        XCTAssertEqual(cancellationCount, 1)
    }

    func testInAppFilteredArtifactWatchdogReportsLastEvidence() {
        let owner =
            FlowTabUITestInAppFilteredArtifactObservationOwner(
                expectedAppName: "Chrome Fixture",
                expectedProcessIdentifier: 4_321,
                observationRegistration: nil,
                readback: {
                    makeInAppFilteredArtifactRuntimeLogSnapshot(
                        contents:
                            makeInAppFilteredArtifactLine(
                                processIdentifier: 4_322
                            )
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestInAppFilteredArtifactObservationTestPolicy
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

    func testInAppFilteredArtifactLifecycleUnderPressure() {
        for iteration in
            0..<FlowTabUITestInAppFilteredArtifactObservationTestPolicy
                .pressureIterations
        {
            var contents = ""
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var cancellationCount = 0
            let owner =
                FlowTabUITestInAppFilteredArtifactObservationOwner(
                    expectedAppName: "Chrome Fixture",
                    expectedProcessIdentifier: 4_321,
                    observationRegistration: { callback in
                        callbacks.append(callback)
                        return FlowTabUITestObservationCancellation {
                            cancellationCount += 1
                        }
                    },
                    readback: {
                        makeInAppFilteredArtifactRuntimeLogSnapshot(
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

            contents = makeInAppFilteredArtifactLine()
            staleCallback(.notificationReadback)
            XCTAssertNil(owner.resolvedEvidence)
            currentCallback(.notificationReadback)

            XCTAssertEqual(
                owner.resolvedEvidence?.value.processIdentifier,
                4_321
            )
            XCTAssertEqual(cancellationCount, 2)
            owner.cancel()
            staleCallback(.notificationReadback)
            XCTAssertEqual(cancellationCount, 2)
        }
    }
}
