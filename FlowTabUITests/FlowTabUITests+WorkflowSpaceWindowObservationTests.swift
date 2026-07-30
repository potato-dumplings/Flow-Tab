import Foundation
import XCTest

private enum FlowTabUITestWorkflowSpaceWindowTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testWorkflowSpaceWindowObserverAcceptsExactInitialState() {
        var order: [String] = []
        let snapshot = workflowSpaceWindowTestSnapshot(
            bundleIdentifier: "com.example.target",
            windowNumber: 42,
            title: "Fullscreen"
        )
        let owner =
            FlowTabUITestWorkflowSpaceWindowObservationOwner(
                expectedBundleIdentifier:
                    "com.example.target",
                expectedTitle: "Fullscreen",
                observationRegistration: { _ in
                    order.append("register")
                    return FlowTabUITestObservationCancellation {
                        order.append("cancel")
                    }
                },
                readback: {
                    order.append("readback")
                    return snapshot
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.topmostCGWindow?
                .number,
            42
        )
        XCTAssertEqual(
            order,
            ["register", "readback", "cancel"]
        )
    }

    func testWorkflowSpaceWindowObserverRequiresFrontmostBundleAndWindowMatch() {
        var readback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = workflowSpaceWindowTestSnapshot(
            bundleIdentifier: "com.example.other",
            windowNumber: 41,
            title: "Fullscreen"
        )
        let owner =
            FlowTabUITestWorkflowSpaceWindowObservationOwner(
                expectedBundleIdentifier:
                    "com.example.target",
                expectedTitle: "Fullscreen",
                observationRegistration: { callback in
                    readback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        snapshot = workflowSpaceWindowTestSnapshot(
            bundleIdentifier: "com.example.target",
            windowNumber: 42,
            title: "Other"
        )
        readback?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = workflowSpaceWindowTestSnapshot(
            bundleIdentifier: "com.example.target",
            windowNumber: 42,
            title: "Fullscreen"
        )
        readback?(.notificationReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .notificationReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.topmostCGWindow?
                .number,
            42
        )
    }

    func testWorkflowSpaceWindowSnapshotAcceptsTitlelessFullscreenEvidence() {
        let snapshot = workflowSpaceWindowTestSnapshot(
            bundleIdentifier: "com.example.target",
            windowNumber: 42,
            title: nil,
            frame: CGRect(
                x: 0,
                y: 0,
                width: 100_000,
                height: 100_000
            )
        )

        XCTAssertEqual(
            snapshot.matchingWindow(
                bundleIdentifier: "com.example.target",
                title: "Fullscreen"
            )?.number,
            42
        )
    }

    func testWorkflowSpaceWindowObserverSlowReadbacksOnlyDelayResolution() {
        var readback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = workflowSpaceWindowTestSnapshot(
            bundleIdentifier: "com.example.target",
            windowNumber: 41,
            title: "Other"
        )
        let owner =
            FlowTabUITestWorkflowSpaceWindowObservationOwner(
                expectedBundleIdentifier:
                    "com.example.target",
                expectedTitle: "Fullscreen",
                observationRegistration: { callback in
                    readback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        for _ in 0..<5 {
            readback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }
        snapshot = workflowSpaceWindowTestSnapshot(
            bundleIdentifier: "com.example.target",
            windowNumber: 42,
            title: "Fullscreen"
        )
        readback?(.scheduledReadback)

        XCTAssertEqual(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestWorkflowSpaceWindowTestPolicy
                        .watchdog
            )?.source,
            .scheduledReadback
        )
    }

    func testWorkflowSpaceWindowObserverRejectsStaleEventsUnderPressure() {
        for _ in 0..<FlowTabUITestWorkflowSpaceWindowTestPolicy
            .pressureIterations
        {
            var readbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var snapshot = workflowSpaceWindowTestSnapshot(
                bundleIdentifier: "com.example.other",
                windowNumber: 41,
                title: "Other"
            )
            let owner =
                FlowTabUITestWorkflowSpaceWindowObservationOwner(
                    expectedBundleIdentifier:
                        "com.example.target",
                    expectedTitle: "Fullscreen",
                    observationRegistration: { callback in
                        readbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: { snapshot }
                )

            owner.start()
            let staleReadback = readbacks[0]
            owner.cancel()
            owner.start()
            snapshot = workflowSpaceWindowTestSnapshot(
                bundleIdentifier: "com.example.target",
                windowNumber: 42,
                title: "Fullscreen"
            )

            staleReadback(.notificationReadback)
            XCTAssertNil(owner.resolvedEvidence)
            readbacks[1](.notificationReadback)
            readbacks[1](.notificationReadback)
            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                2
            )
            owner.cancel()
        }
    }

    func testWorkflowSpaceWindowWatchdogReportsFinalReadback() {
        var readbackCount = 0
        let owner =
            FlowTabUITestWorkflowSpaceWindowObservationOwner(
                expectedBundleIdentifier:
                    "com.example.target",
                expectedTitle: "Fullscreen",
                observationRegistration: nil,
                readback: {
                    defer { readbackCount += 1 }
                    return self.workflowSpaceWindowTestSnapshot(
                        bundleIdentifier:
                            "com.example.target",
                        windowNumber: 42,
                        title:
                            readbackCount == 0
                                ? "Other"
                                : "Fullscreen"
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestWorkflowSpaceWindowTestPolicy
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
                "topmostCGWindow=42:Fullscreen"
            )
        )
    }

    private func workflowSpaceWindowTestSnapshot(
        bundleIdentifier: String?,
        windowNumber: CGWindowID?,
        title: String?,
        frame: CGRect? = CGRect(
            x: 0,
            y: 0,
            width: 1_200,
            height: 800
        )
    ) -> FlowTabUITestWorkflowSpaceWindowSnapshot {
        FlowTabUITestWorkflowSpaceWindowSnapshot(
            frontmostBundleIdentifier: bundleIdentifier,
            topmostCGWindow: windowNumber.map {
                WorkflowCGWindowObservation(
                    number: $0,
                    title: title,
                    frame: frame
                )
            }
        )
    }
}
