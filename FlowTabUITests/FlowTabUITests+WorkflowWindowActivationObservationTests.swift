import Foundation
import XCTest

private enum FlowTabUITestWorkflowWindowActivationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testWorkflowWindowActivationObserverAcceptsExactInitialState() {
        var registrationOrder: [String] = []
        let owner =
            FlowTabUITestWorkflowWindowActivationObservationOwner(
                expectedBundleIdentifier:
                    "com.example.target",
                expectedWindowNumber: 42,
                expectedTitle: "Draft",
                observationRegistration: { _ in
                    registrationOrder.append("register")
                    return FlowTabUITestObservationCancellation {
                        registrationOrder.append("cancel")
                    }
                },
                readback: {
                    registrationOrder.append("readback")
                    return self
                        .workflowWindowActivationTestSnapshot(
                            bundleIdentifier:
                                "com.example.target",
                            windowNumber: 42,
                            title: "Draft"
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
            registrationOrder,
            ["register", "readback", "cancel"]
        )
    }

    func testWorkflowWindowActivationObserverInstallsBeforeReadbackAndGatesBaseline() {
        var order: [String] = []
        var eventHandler:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var acceptsEvidence = false
        let snapshot = workflowWindowActivationTestSnapshot(
            bundleIdentifier: "com.example.target",
            windowNumber: 42,
            title: "Draft"
        )
        let owner =
            FlowTabUITestWorkflowWindowActivationObservationOwner(
                expectedBundleIdentifier: "com.example.target",
                expectedWindowNumber: 42,
                expectedTitle: "Draft",
                acceptsEvidence: {
                    acceptsEvidence
                },
                observationRegistration: { readback in
                    order.append("register")
                    eventHandler = readback
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

        XCTAssertEqual(order, ["register", "readback"])
        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(
            owner.latestEvidence?.source,
            .initialReadback
        )

        acceptsEvidence = true
        eventHandler?(.notificationReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestWorkflowWindowActivationTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .notificationReadback)
        XCTAssertEqual(
            evidence?.value.topmostCGWindow?.number,
            42
        )
        XCTAssertEqual(
            order,
            ["register", "readback", "readback", "cancel"]
        )
    }

    func testWorkflowWindowActivationObserverRequiresExactBundleAndWindow() {
        var eventHandler:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = workflowWindowActivationTestSnapshot(
            bundleIdentifier: "com.example.other",
            windowNumber: 41,
            title: "Other"
        )
        let owner =
            FlowTabUITestWorkflowWindowActivationObservationOwner(
                expectedBundleIdentifier: "com.example.target",
                expectedWindowNumber: 42,
                expectedTitle: "Draft",
                observationRegistration: { readback in
                    eventHandler = readback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    snapshot
                }
            )
        owner.start()
        defer { owner.cancel() }

        snapshot = workflowWindowActivationTestSnapshot(
            bundleIdentifier: "com.example.target",
            windowNumber: 41,
            title: "Draft"
        )
        eventHandler?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = workflowWindowActivationTestSnapshot(
            bundleIdentifier: "com.example.other",
            windowNumber: 42,
            title: "Draft"
        )
        eventHandler?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = workflowWindowActivationTestSnapshot(
            bundleIdentifier: "com.example.target",
            windowNumber: 42,
            title: nil
        )
        eventHandler?(.notificationReadback)

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestWorkflowWindowActivationTestPolicy
                    .watchdog
        )
        XCTAssertEqual(
            evidence?.value.frontmostBundleIdentifier,
            "com.example.target"
        )
        XCTAssertEqual(
            evidence?.value.topmostCGWindow?.number,
            42
        )
    }

    func testWorkflowWindowActivationObserverSlowReadbacksOnlyDelayResolution() {
        var eventHandler:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = workflowWindowActivationTestSnapshot(
            bundleIdentifier: "com.example.other",
            windowNumber: 41,
            title: "Other"
        )
        let owner =
            FlowTabUITestWorkflowWindowActivationObservationOwner(
                expectedBundleIdentifier: "com.example.target",
                expectedWindowNumber: 42,
                expectedTitle: "Draft",
                observationRegistration: { readback in
                    eventHandler = readback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    snapshot
                }
            )
        owner.start()
        defer { owner.cancel() }

        for _ in 0..<5 {
            eventHandler?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = workflowWindowActivationTestSnapshot(
            bundleIdentifier: "com.example.target",
            windowNumber: 42,
            title: "Draft"
        )
        eventHandler?(.scheduledReadback)

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestWorkflowWindowActivationTestPolicy
                    .watchdog
        )
        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(
            evidence?.value.topmostCGWindow?.number,
            42
        )
    }

    func testWorkflowWindowActivationObserverRejectsCancelledAndReplacedEventsUnderPressure() {
        for _ in 0..<FlowTabUITestWorkflowWindowActivationTestPolicy
            .pressureIterations
        {
            var eventHandlers: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var snapshot = workflowWindowActivationTestSnapshot(
                bundleIdentifier: "com.example.other",
                windowNumber: 41,
                title: "Other"
            )
            let owner =
                FlowTabUITestWorkflowWindowActivationObservationOwner(
                    expectedBundleIdentifier:
                        "com.example.target",
                    expectedWindowNumber: 42,
                    expectedTitle: "Draft",
                    observationRegistration: { readback in
                        eventHandlers.append(readback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: {
                        snapshot
                    }
                )

            owner.start()
            let staleHandler = eventHandlers[0]
            owner.cancel()
            owner.start()
            snapshot = workflowWindowActivationTestSnapshot(
                bundleIdentifier: "com.example.target",
                windowNumber: 42,
                title: "Draft"
            )

            staleHandler(.notificationReadback)
            XCTAssertNil(owner.resolvedEvidence)
            eventHandlers[1](.notificationReadback)
            eventHandlers[1](.notificationReadback)
            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                2
            )
            owner.cancel()
        }
    }

    func testWorkflowWindowActivationWatchdogReportsFinalReadback() {
        var readbackCount = 0
        let owner =
            FlowTabUITestWorkflowWindowActivationObservationOwner(
                expectedBundleIdentifier: "com.example.target",
                expectedWindowNumber: 42,
                expectedTitle: "Draft",
                observationRegistration: nil,
                readback: {
                    defer { readbackCount += 1 }
                    return self
                        .workflowWindowActivationTestSnapshot(
                            bundleIdentifier:
                                "com.example.target",
                            windowNumber:
                                readbackCount == 0 ? 41 : 42,
                            title: "Draft"
                        )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestWorkflowWindowActivationTestPolicy
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
                "topmostCGWindow=42:"
            )
        )
    }

    private func workflowWindowActivationTestSnapshot(
        bundleIdentifier: String?,
        windowNumber: CGWindowID?,
        title: String?
    ) -> FlowTabUITestWorkflowWindowActivationSnapshot {
        FlowTabUITestWorkflowWindowActivationSnapshot(
            frontmostBundleIdentifier: bundleIdentifier,
            topmostCGWindow: windowNumber.map {
                WorkflowCGWindowObservation(
                    number: $0,
                    title: title,
                    frame: CGRect(
                        x: 0,
                        y: 0,
                        width: 1_200,
                        height: 800
                    )
                )
            },
            activeWindowTitle: title,
            expectedTitleIsObservable: title != nil
        )
    }
}
