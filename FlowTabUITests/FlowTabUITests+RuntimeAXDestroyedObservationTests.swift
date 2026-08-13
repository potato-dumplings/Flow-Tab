import CoreGraphics
import Darwin
import Foundation
import XCTest

private enum FlowTabUITestRuntimeAXDestroyedObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
    static let bundleIdentifier =
        "com.example.fixture.chrome+exact"
    static let processIdentifier: pid_t = 42_017
    static let targetCGWindowID: CGWindowID = 730_002
    static var matchingRecord: String {
        record(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            axProcessIdentifier: processIdentifier,
            affectedCGWindowID:
                String(targetCGWindowID)
        )
    }
    static func record(
        bundleIdentifier: String,
        processIdentifier: pid_t,
        axProcessIdentifier: pid_t,
        affectedCGWindowID: String
    ) -> String {
        "[DEBUG] [Projection] runtimeAXDestroyed "
            + "appID=\(bundleIdentifier) "
            + "pid=\(processIdentifier) "
            + "axWindowID=ax:\(axProcessIdentifier):1 "
            + "affectedCGWindowID=\(affectedCGWindowID)\n"
    }
    static func expectation()
        throws -> FlowTabUITestRuntimeLogExpectation
    {
        try .exactRuntimeAXDestroyed(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            affectedCGWindowID: targetCGWindowID
        )
    }
    static func snapshot(
        generation: UInt64,
        contents: String
    ) -> FlowTabUITestRuntimeLogSnapshot {
        FlowTabUITestRuntimeLogSnapshot(
            baselineFileEventGeneration: 10,
            fileEventGeneration: generation,
            contents: contents
        )
    }
}

extension FlowTabUITests {
    func testRuntimeAXDestroyedReconciliationPolicyAndExactIdentity()
        throws
    {
        let watchdog = FlowTabUITestRuntimeLogObservationPolicy
            .multiAppOpenWindowMutationReconciliationWatchdog
        XCTAssertEqual(watchdog, 8)
        XCTAssertTrue(watchdog.isFinite && watchdog > 0)
        let fullscreenWatchdog = FlowTabUITestRuntimeLogObservationPolicy
            .fullscreenMultiAppWindowMutationReconciliationWatchdog
        XCTAssertEqual(fullscreenWatchdog, 8)
        XCTAssertTrue(fullscreenWatchdog.isFinite && fullscreenWatchdog > 0)
        let expectation =
            try FlowTabUITestRuntimeAXDestroyedObservationTestPolicy
                .expectation()
        XCTAssertTrue(
            expectation.isSatisfied(
                by:
                    FlowTabUITestRuntimeAXDestroyedObservationTestPolicy
                        .snapshot(
                            generation: 11,
                            contents:
                                FlowTabUITestRuntimeAXDestroyedObservationTestPolicy
                                    .matchingRecord
                        )
            )
        )
        let policy =
            FlowTabUITestRuntimeAXDestroyedObservationTestPolicy.self
        let mismatchedRecords = [
            policy.record(
                bundleIdentifier:
                    "com.example.fixture.chromeXexact",
                processIdentifier: policy.processIdentifier,
                axProcessIdentifier: policy.processIdentifier,
                affectedCGWindowID:
                    String(policy.targetCGWindowID)
            ),
            policy.record(
                bundleIdentifier: policy.bundleIdentifier,
                processIdentifier:
                    policy.processIdentifier + 1,
                axProcessIdentifier:
                    policy.processIdentifier + 1,
                affectedCGWindowID:
                    String(policy.targetCGWindowID)
            ),
            policy.record(
                bundleIdentifier: policy.bundleIdentifier,
                processIdentifier: policy.processIdentifier,
                axProcessIdentifier:
                    policy.processIdentifier + 1,
                affectedCGWindowID:
                    String(policy.targetCGWindowID)
            ),
            policy.record(
                bundleIdentifier: policy.bundleIdentifier,
                processIdentifier: policy.processIdentifier,
                axProcessIdentifier: policy.processIdentifier,
                affectedCGWindowID:
                    String(policy.targetCGWindowID + 1)
            ),
            policy.record(
                bundleIdentifier: policy.bundleIdentifier,
                processIdentifier: policy.processIdentifier,
                axProcessIdentifier: policy.processIdentifier,
                affectedCGWindowID: "none"
            ),
            policy.matchingRecord
                .replacingOccurrences(
                    of: "\n",
                    with: " extra=unexpected\n"
                )
        ]
        for (index, record) in mismatchedRecords.enumerated() {
            XCTAssertFalse(
                expectation.isSatisfied(
                    by: policy.snapshot(
                        generation: UInt64(12 + index),
                        contents: record
                    )
                ),
                "mismatchIndex=\(index) record=\(record)"
            )
        }
    }

    func testRuntimeAXDestroyedReconciliationRequiresPostTriggerEvent()
        throws
    {
        let policy =
            FlowTabUITestRuntimeAXDestroyedObservationTestPolicy.self
        var snapshot = policy.snapshot(
            generation: 20,
            contents: policy.matchingRecord
        )
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        var acceptsResolution = false
        let owner = FlowTabUITestRuntimeLogObservationOwner(
            expectation: try policy.expectation(),
            observationRegistration: { registered in
                callback = registered
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            acceptsResolution: {
                acceptsResolution
            },
            readback: { snapshot }
        )
        owner.start()
        XCTAssertNil(owner.resolvedEvidence)
        callback?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)
        snapshot = policy.snapshot(
            generation: 20,
            contents: policy.record(
                bundleIdentifier: policy.bundleIdentifier,
                processIdentifier: policy.processIdentifier,
                axProcessIdentifier: policy.processIdentifier,
                affectedCGWindowID: "none"
            )
        )
        acceptsResolution = true
        owner.requestReadback(source: .triggerReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = policy.snapshot(
            generation: 21,
            contents: policy.matchingRecord
        )
        callback?(.notificationReadback)
        XCTAssertEqual(
            owner.waitForResolution(
                timeout: policy.watchdog
            )?.source,
            .notificationReadback
        )
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
        XCTAssertEqual(cancellationCount, 1)
    }

    func testRuntimeAXDestroyedReconciliationCancellationRejectsLateDelivery()
        throws
    {
        let policy =
            FlowTabUITestRuntimeAXDestroyedObservationTestPolicy.self
        var snapshot = policy.snapshot(
            generation: 30,
            contents: ""
        )
        var callback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var readbackCount = 0
        var cancellationCount = 0
        let owner = FlowTabUITestRuntimeLogObservationOwner(
            expectation: try policy.expectation(),
            observationRegistration: { registered in
                callback = registered
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: {
                readbackCount += 1
                return snapshot
            }
        )
        owner.start()
        owner.cancel()
        let readbackCountAfterCancellation = readbackCount
        snapshot = policy.snapshot(
            generation: 31,
            contents: policy.matchingRecord
        )
        callback?(.notificationReadback)
        owner.requestReadback(source: .triggerReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(
            readbackCount,
            readbackCountAfterCancellation
        )
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
        XCTAssertEqual(cancellationCount, 1)
    }

    func testRuntimeAXDestroyedReconciliationWatchdogReportsLastWrongIdentity()
        throws
    {
        let policy =
            FlowTabUITestRuntimeAXDestroyedObservationTestPolicy.self
        let wrongRecord = policy.record(
            bundleIdentifier: policy.bundleIdentifier,
            processIdentifier: policy.processIdentifier,
            axProcessIdentifier: policy.processIdentifier,
            affectedCGWindowID: "none"
        )
        let owner = FlowTabUITestRuntimeLogObservationOwner(
            expectation: try policy.expectation(),
            observationRegistration: nil,
            readback: {
                policy.snapshot(
                    generation: 41,
                    contents: wrongRecord
                )
            }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout: policy.watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "missingPattern=exact runtime AX-destroyed "
                    + "bundle/PID/CG reconciliation"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "pid=\(policy.processIdentifier)"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "affectedCGWindowID=none"
            )
        )
    }

    func testRuntimeAXDestroyedReconciliationFiltersWrongIdentityUnderPressure()
        throws
    {
        let policy =
            FlowTabUITestRuntimeAXDestroyedObservationTestPolicy.self
        for iteration in 0..<policy.pressureIterations {
            var snapshot = policy.snapshot(
                generation: UInt64(100 + iteration),
                contents: ""
            )
            var callback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var readbackCount = 0
            var cancellationCount = 0
            let owner = FlowTabUITestRuntimeLogObservationOwner(
                expectation: try policy.expectation(),
                observationRegistration: { registered in
                    callback = registered
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    readbackCount += 1
                    return snapshot
                }
            )
            owner.start()

            let wrongRecords = [
                policy.record(
                    bundleIdentifier:
                        "com.example.fixture.other",
                    processIdentifier:
                        policy.processIdentifier,
                    axProcessIdentifier:
                        policy.processIdentifier,
                    affectedCGWindowID:
                        String(policy.targetCGWindowID)
                ),
                policy.record(
                    bundleIdentifier:
                        policy.bundleIdentifier,
                    processIdentifier:
                        policy.processIdentifier + 1,
                    axProcessIdentifier:
                        policy.processIdentifier + 1,
                    affectedCGWindowID:
                        String(policy.targetCGWindowID)
                ),
                policy.record(
                    bundleIdentifier:
                        policy.bundleIdentifier,
                    processIdentifier:
                        policy.processIdentifier,
                    axProcessIdentifier:
                        policy.processIdentifier,
                    affectedCGWindowID: "none"
                )
            ]
            for (offset, record) in wrongRecords.enumerated() {
                snapshot = policy.snapshot(
                    generation:
                        UInt64(200 + iteration + offset),
                    contents: record
                )
                callback?(.notificationReadback)
                XCTAssertNil(
                    owner.resolvedEvidence,
                    "iteration=\(iteration) offset=\(offset)"
                )
            }

            snapshot = policy.snapshot(
                generation: UInt64(400 + iteration),
                contents: policy.matchingRecord
            )
            callback?(.notificationReadback)
            XCTAssertEqual(
                owner.waitForResolution(
                    timeout: policy.watchdog
                )?.source,
                .notificationReadback,
                "iteration=\(iteration)"
            )
            let resolvedReadbackCount = readbackCount
            callback?(.notificationReadback)
            XCTAssertEqual(
                readbackCount,
                resolvedReadbackCount,
                "iteration=\(iteration)"
            )
            XCTAssertEqual(
                cancellationCount,
                1,
                "iteration=\(iteration)"
            )
            owner.cancel()
        }
    }
}
