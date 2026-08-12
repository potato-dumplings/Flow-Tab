import Foundation
import XCTest

private enum FlowTabUITestFlowTabForegroundObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testHomeWindowRecencyFlowTabActivationPolicyCompatibility() {
        let watchdog =
            FlowTabUITestHomeWindowRecencyFlowTabActivationPolicy
                .foregroundActivationWatchdog
        XCTAssertEqual(watchdog, 10)
        XCTAssertTrue(watchdog.isFinite)
        XCTAssertGreaterThan(watchdog, 0)
    }

    func testFlowTabForegroundObserverInstallsBeforeReadbackAndGatesMatchingBaseline() {
        var order: [String] = []
        var activationHandler:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let snapshot = flowTabForegroundTestSnapshot(
            bundleIdentifier: "io.example.flowtab",
            state: .runningForeground
        )
        let owner = FlowTabUITestFlowTabForegroundObservationOwner(
            expectedBundleIdentifier: "io.example.flowtab",
            activationRegistration: { readback in
                order.append("registerActivation")
                activationHandler = readback
                return FlowTabUITestObservationCancellation {
                    order.append("cancelActivation")
                }
            },
            scheduledRegistration: { _ in
                order.append("registerSchedule")
                return FlowTabUITestObservationCancellation {
                    order.append("cancelSchedule")
                }
            },
            readback: {
                order.append("readback")
                return snapshot
            }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(order, ["registerActivation", "readback"])
        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)

        activationHandler?(.notificationReadback)
        XCTAssertEqual(order, ["registerActivation", "readback"])
        XCTAssertNil(owner.resolvedEvidence)

        owner.markActivationCompleted()

        XCTAssertEqual(owner.resolvedEvidence?.source, .triggerReadback)
        XCTAssertEqual(
            owner.resolvedEvidence?.value.applicationState,
            .runningForeground
        )
        XCTAssertEqual(
            order,
            ["registerActivation", "readback", "readback", "cancelActivation"]
        )
    }

    func testFlowTabForegroundObserverAcceptsExactNotificationTransition() {
        var activationHandler:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = flowTabForegroundTestSnapshot(
            bundleIdentifier: "io.example.fixture",
            state: .runningBackground
        )
        let owner = FlowTabUITestFlowTabForegroundObservationOwner(
            expectedBundleIdentifier: "io.example.flowtab",
            activationRegistration: { readback in
                activationHandler = readback
                return FlowTabUITestObservationCancellation {}
            },
            scheduledRegistration: { _ in
                FlowTabUITestObservationCancellation {}
            },
            readback: { snapshot }
        )
        owner.start()
        defer { owner.cancel() }
        owner.markActivationCompleted()

        snapshot = flowTabForegroundTestSnapshot(
            bundleIdentifier: "io.example.flowtab",
            state: .runningBackground
        )
        activationHandler?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = flowTabForegroundTestSnapshot(
            bundleIdentifier: "io.example.fixture",
            state: .runningForeground
        )
        activationHandler?(.notificationReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = flowTabForegroundTestSnapshot(
            bundleIdentifier: "io.example.flowtab",
            state: .runningForeground
        )
        activationHandler?(.notificationReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .notificationReadback
        )
    }

    func testFlowTabForegroundObserverSlowSchedulingOnlyDelaysResolution() {
        var scheduledHandler:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot = flowTabForegroundTestSnapshot(
            bundleIdentifier: "io.example.fixture",
            state: .runningBackground
        )
        let owner = FlowTabUITestFlowTabForegroundObservationOwner(
            expectedBundleIdentifier: "io.example.flowtab",
            activationRegistration: { _ in
                FlowTabUITestObservationCancellation {}
            },
            scheduledRegistration: { readback in
                scheduledHandler = readback
                return FlowTabUITestObservationCancellation {}
            },
            readback: { snapshot }
        )
        owner.start()
        defer { owner.cancel() }
        owner.markActivationCompleted()

        for _ in 0..<5 {
            scheduledHandler?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }
        snapshot = flowTabForegroundTestSnapshot(
            bundleIdentifier: "io.example.flowtab",
            state: .runningForeground
        )
        scheduledHandler?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
    }

    func testFlowTabForegroundObserverRejectsCancelledAndReplacedEventsUnderPressure() {
        for _ in 0..<FlowTabUITestFlowTabForegroundObservationTestPolicy
            .pressureIterations
        {
            var activationHandlers: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var snapshot = flowTabForegroundTestSnapshot(
                bundleIdentifier: "io.example.fixture",
                state: .runningBackground
            )
            let owner = FlowTabUITestFlowTabForegroundObservationOwner(
                expectedBundleIdentifier: "io.example.flowtab",
                activationRegistration: { readback in
                    activationHandlers.append(readback)
                    return FlowTabUITestObservationCancellation {}
                },
                scheduledRegistration: { _ in
                    FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )

            owner.start()
            let staleHandler = activationHandlers[0]
            owner.cancel()
            owner.start()
            owner.markActivationCompleted()
            snapshot = flowTabForegroundTestSnapshot(
                bundleIdentifier: "io.example.flowtab",
                state: .runningForeground
            )

            staleHandler(.notificationReadback)
            XCTAssertNil(owner.resolvedEvidence)
            activationHandlers[1](.notificationReadback)
            activationHandlers[1](.notificationReadback)
            XCTAssertEqual(owner.resolvedEvidence?.generation, 2)
            owner.cancel()
        }
    }

    func testFlowTabForegroundWatchdogReportsFinalReadback() {
        var readbackCount = 0
        let owner = FlowTabUITestFlowTabForegroundObservationOwner(
            expectedBundleIdentifier: "io.example.flowtab",
            activationRegistration: { _ in
                FlowTabUITestObservationCancellation {}
            },
            scheduledRegistration: { _ in
                FlowTabUITestObservationCancellation {}
            },
            readback: {
                defer { readbackCount += 1 }
                return self.flowTabForegroundTestSnapshot(
                    bundleIdentifier:
                        readbackCount >= 2
                            ? "io.example.flowtab"
                            : "io.example.fixture",
                    state:
                        readbackCount >= 2
                            ? .runningForeground
                            : .runningBackground
                )
            }
        )
        owner.start()
        defer { owner.cancel() }
        owner.markActivationCompleted()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestFlowTabForegroundObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("source=watchdogReadback")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "frontmostBundle=io.example.flowtab"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("waitResult=")
        )
    }

    private func flowTabForegroundTestSnapshot(
        bundleIdentifier: String?,
        state: XCUIApplication.State
    ) -> FlowTabUITestFlowTabForegroundSnapshot {
        FlowTabUITestFlowTabForegroundSnapshot(
            frontmostBundleIdentifier: bundleIdentifier,
            applicationState: state
        )
    }
}
