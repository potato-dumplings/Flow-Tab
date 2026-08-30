import Foundation
import XCTest

private enum FlowTabUITestLogsRuntimeDeliveryTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
    static let marker = "runtime log observation probe"
}

extension FlowTabUITests {
    func testLogsRuntimeDeliveryExpectationRequiresAtomicTransition() {
        XCTAssertEqual(
            FlowTabUITestLogsRuntimeDeliveryObservationPolicy
                .projectionWatchdog,
            5
        )
        let baselineExpectation =
            logsRuntimeDeliveryTestExpectation(
                requirement: .emptyBaseline
            )
        let targetExpectation =
            logsRuntimeDeliveryTestExpectation(
                requirement: .delivered
            )
        let markerAbsentExpectation =
            logsRuntimeDeliveryTestExpectation(
                requirement: .markerAbsent
            )
        let baseline = logsRuntimeDeliveryTestSnapshot()
        let delivered = logsRuntimeDeliveryTestSnapshot(
            linesContainerExists: true,
            emptyHintExists: false,
            matchingRowContents: [
                "prefix runtime log observation probe suffix"
            ]
        )

        XCTAssertTrue(baselineExpectation.isSatisfied(by: baseline))
        XCTAssertTrue(targetExpectation.isSatisfied(by: delivered))
        XCTAssertFalse(targetExpectation.isSatisfied(by: baseline))
        XCTAssertFalse(baselineExpectation.isSatisfied(by: delivered))
        XCTAssertTrue(markerAbsentExpectation.isSatisfied(by: baseline))
        XCTAssertTrue(
            markerAbsentExpectation.isSatisfied(
                by: logsRuntimeDeliveryTestSnapshot(
                    linesContainerExists: true,
                    emptyHintExists: false
                )
            )
        )
        XCTAssertFalse(markerAbsentExpectation.isSatisfied(by: delivered))

        let sharedInvalidSnapshots = [
            logsRuntimeDeliveryTestSnapshot(
                applicationState: .runningBackground
            ),
            logsRuntimeDeliveryTestSnapshot(
                logsContentExists: false
            ),
            logsRuntimeDeliveryTestSnapshot(
                clearButtonExists: false
            ),
            logsRuntimeDeliveryTestSnapshot(
                clearButtonIsHittable: false
            ),
            logsRuntimeDeliveryTestSnapshot(
                selectedLevel: "WARN"
            )
        ]
        for snapshot in sharedInvalidSnapshots {
            XCTAssertFalse(
                baselineExpectation.isSatisfied(by: snapshot)
            )
            XCTAssertFalse(
                markerAbsentExpectation.isSatisfied(by: snapshot)
            )
        }

        XCTAssertFalse(
            baselineExpectation.isSatisfied(
                by: logsRuntimeDeliveryTestSnapshot(
                    linesContainerExists: true
                )
            )
        )
        XCTAssertFalse(
            baselineExpectation.isSatisfied(
                by: logsRuntimeDeliveryTestSnapshot(
                    emptyHintExists: false
                )
            )
        )
        XCTAssertFalse(
            baselineExpectation.isSatisfied(
                by: logsRuntimeDeliveryTestSnapshot(
                    matchingRowContents: [
                        FlowTabUITestLogsRuntimeDeliveryTestPolicy.marker
                    ]
                )
            )
        )

        for snapshot in sharedInvalidSnapshots {
            let targetSnapshot =
                FlowTabUITestLogsRuntimeDeliverySnapshot(
                    applicationState: snapshot.applicationState,
                    logsContentExists: snapshot.logsContentExists,
                    clearButtonExists: snapshot.clearButtonExists,
                    clearButtonIsHittable:
                        snapshot.clearButtonIsHittable,
                    linesContainerExists: true,
                    emptyHintExists: false,
                    selectedLevel: snapshot.selectedLevel,
                    matchingRowContents:
                        delivered.matchingRowContents
                )
            XCTAssertFalse(
                targetExpectation.isSatisfied(by: targetSnapshot)
            )
        }
        XCTAssertFalse(
            targetExpectation.isSatisfied(
                by: logsRuntimeDeliveryTestSnapshot(
                    emptyHintExists: false,
                    matchingRowContents:
                        delivered.matchingRowContents
                )
            )
        )
        XCTAssertFalse(
            targetExpectation.isSatisfied(
                by: logsRuntimeDeliveryTestSnapshot(
                    linesContainerExists: true,
                    matchingRowContents:
                        delivered.matchingRowContents
                )
            )
        )
        XCTAssertFalse(
            targetExpectation.isSatisfied(
                by: logsRuntimeDeliveryTestSnapshot(
                    linesContainerExists: true,
                    emptyHintExists: false
                )
            )
        )
        XCTAssertFalse(
            targetExpectation.isSatisfied(
                by: logsRuntimeDeliveryTestSnapshot(
                    linesContainerExists: true,
                    emptyHintExists: false,
                    matchingRowContents: ["different row"]
                )
            )
        )
        XCTAssertFalse(
            targetExpectation.isSatisfied(
                by: logsRuntimeDeliveryTestSnapshot(
                    linesContainerExists: true,
                    emptyHintExists: false,
                    matchingRowContents: [
                        FlowTabUITestLogsRuntimeDeliveryTestPolicy.marker,
                        FlowTabUITestLogsRuntimeDeliveryTestPolicy.marker
                    ]
                )
            )
        )
    }

    func testLogsRuntimeDeliveryOwnerUsesPostTriggerEvidence() {
        let expectation = logsRuntimeDeliveryTestExpectation(
            requirement: .delivered
        )
        let baseline = logsRuntimeDeliveryTestSnapshot()
        let delivered = logsRuntimeDeliveryTestSnapshot(
            linesContainerExists: true,
            emptyHintExists: false,
            matchingRowContents: [
                FlowTabUITestLogsRuntimeDeliveryTestPolicy.marker
            ]
        )
        var snapshot = delivered
        var acceptsResolution = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner = FlowTabUITestLogsRuntimeDeliveryObservationOwner(
            expectation: expectation,
            observationRegistration: { callback in
                scheduledReadback = callback
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            acceptsResolution: { acceptsResolution },
            readback: { snapshot }
        )
        owner.start()

        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)
        XCTAssertEqual(owner.latestEvidence?.value, delivered)
        XCTAssertNil(owner.resolvedEvidence)
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        acceptsResolution = true
        owner.requestReadback(source: .triggerReadback)
        let triggerEvidence = owner.waitForResolution(
            timeout:
                FlowTabUITestLogsRuntimeDeliveryTestPolicy.watchdog
        )
        XCTAssertEqual(triggerEvidence?.source, .triggerReadback)
        XCTAssertEqual(triggerEvidence?.value, delivered)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()

        snapshot = baseline
        acceptsResolution = false
        scheduledReadback = nil
        cancellationCount = 0
        var readbackCount = 0
        let delayedOwner =
            FlowTabUITestLogsRuntimeDeliveryObservationOwner(
                expectation: expectation,
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                acceptsResolution: { acceptsResolution },
                readback: {
                    readbackCount += 1
                    return snapshot
                }
            )
        delayedOwner.start()
        acceptsResolution = true
        delayedOwner.requestReadback(source: .triggerReadback)
        XCTAssertNil(delayedOwner.resolvedEvidence)

        snapshot = delivered
        scheduledReadback?(.scheduledReadback)
        let delayedEvidence = delayedOwner.waitForResolution(
            timeout:
                FlowTabUITestLogsRuntimeDeliveryTestPolicy.watchdog
        )
        let resolvedReadbackCount = readbackCount
        scheduledReadback?(.scheduledReadback)
        delayedOwner.requestReadback(source: .triggerReadback)
        XCTAssertEqual(delayedEvidence?.source, .scheduledReadback)
        XCTAssertEqual(delayedEvidence?.value, delivered)
        XCTAssertEqual(readbackCount, resolvedReadbackCount)
        XCTAssertEqual(cancellationCount, 1)
        delayedOwner.cancel()
    }

    func testLogsRuntimeDeliveryOwnerLifecycleUnderPressure() {
        let expectation = logsRuntimeDeliveryTestExpectation(
            requirement: .delivered
        )
        let baseline = logsRuntimeDeliveryTestSnapshot()
        let delivered = logsRuntimeDeliveryTestSnapshot(
            linesContainerExists: true,
            emptyHintExists: false,
            matchingRowContents: [
                FlowTabUITestLogsRuntimeDeliveryTestPolicy.marker
            ]
        )

        for iteration in
            0..<FlowTabUITestLogsRuntimeDeliveryTestPolicy
                .pressureIterations
        {
            var snapshot = baseline
            var acceptsResolution = false
            var scheduledReadback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var cancellationCount = 0
            var readbackCount = 0
            let owner =
                FlowTabUITestLogsRuntimeDeliveryObservationOwner(
                    expectation: expectation,
                    observationRegistration: { callback in
                        scheduledReadback = callback
                        return FlowTabUITestObservationCancellation {
                            cancellationCount += 1
                        }
                    },
                    acceptsResolution: { acceptsResolution },
                    readback: {
                        readbackCount += 1
                        return snapshot
                    }
                )
            owner.start()
            scheduledReadback?(.scheduledReadback)
            acceptsResolution = true

            if iteration.isMultiple(of: 2) {
                snapshot = delivered
                owner.requestReadback(source: .triggerReadback)
            } else {
                owner.requestReadback(source: .triggerReadback)
                snapshot = delivered
                scheduledReadback?(.scheduledReadback)
            }
            let evidence = owner.waitForResolution(
                timeout:
                    FlowTabUITestLogsRuntimeDeliveryTestPolicy
                        .watchdog
            )
            let resolvedReadbackCount = readbackCount
            scheduledReadback?(.scheduledReadback)
            owner.requestReadback(source: .triggerReadback)

            XCTAssertEqual(
                evidence?.value,
                delivered,
                "iteration=\(iteration)"
            )
            XCTAssertEqual(readbackCount, resolvedReadbackCount)
            XCTAssertEqual(cancellationCount, 1)
            owner.cancel()
        }

        var cancelledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancelledReadbackCount = 0
        var cancellationCount = 0
        let cancelledOwner =
            FlowTabUITestLogsRuntimeDeliveryObservationOwner(
                expectation: expectation,
                observationRegistration: { callback in
                    cancelledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    cancelledReadbackCount += 1
                    return baseline
                }
            )
        cancelledOwner.start()
        cancelledOwner.cancel()
        cancelledReadback?(.scheduledReadback)
        XCTAssertEqual(cancelledReadbackCount, 1)
        XCTAssertEqual(cancellationCount, 1)

        let watchdogOwner =
            FlowTabUITestLogsRuntimeDeliveryObservationOwner(
                expectation: expectation,
                observationRegistration: nil,
                readback: { baseline }
            )
        watchdogOwner.start()
        XCTAssertNil(
            watchdogOwner.waitForResolution(
                timeout:
                    FlowTabUITestLogsRuntimeDeliveryTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            watchdogOwner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            watchdogOwner.diagnosticSummary.contains(
                "matchingRowCount=0"
            )
        )
        XCTAssertTrue(
            watchdogOwner.diagnosticSummary.contains(
                "emptyHintExists=true"
            )
        )
        watchdogOwner.cancel()
    }

    private func logsRuntimeDeliveryTestExpectation(
        requirement: FlowTabUITestLogsRuntimeDeliveryRequirement
    ) -> FlowTabUITestLogsRuntimeDeliveryExpectation {
        FlowTabUITestLogsRuntimeDeliveryExpectation(
            requirement: requirement,
            selectedLevel: "INFO",
            marker:
                FlowTabUITestLogsRuntimeDeliveryTestPolicy.marker
        )
    }

    private func logsRuntimeDeliveryTestSnapshot(
        applicationState: XCUIApplication.State = .runningForeground,
        logsContentExists: Bool = true,
        clearButtonExists: Bool = true,
        clearButtonIsHittable: Bool = true,
        linesContainerExists: Bool = false,
        emptyHintExists: Bool = true,
        selectedLevel: String? = "INFO",
        matchingRowContents: [String] = []
    ) -> FlowTabUITestLogsRuntimeDeliverySnapshot {
        FlowTabUITestLogsRuntimeDeliverySnapshot(
            applicationState: applicationState,
            logsContentExists: logsContentExists,
            clearButtonExists: clearButtonExists,
            clearButtonIsHittable: clearButtonIsHittable,
            linesContainerExists: linesContainerExists,
            emptyHintExists: emptyHintExists,
            selectedLevel: selectedLevel,
            matchingRowContents: matchingRowContents
        )
    }
}
