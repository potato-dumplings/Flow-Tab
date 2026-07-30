import Foundation
import XCTest

private enum FlowTabUITestConditionObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 500
}

extension FlowTabUITests {
    func testUIConditionObserverUsesInitialReadbackAndPreinstalledEvents() {
        var registrationOrder: [String] = []
        var eventHandler: (() -> Void)?
        var isSatisfied = true
        let owner = FlowTabUITestConditionObservationOwner(
            eventRegistration: { callback in
                registrationOrder.append("observer")
                eventHandler = callback
                return FlowTabUITestObservationCancellation {
                    registrationOrder.append("cancel")
                }
            },
            readback: {
                registrationOrder.append("readback")
                return isSatisfied
            },
            isSatisfied: { $0 },
            describe: { "satisfied=\($0)" }
        )

        owner.start()
        let initialEvidence = owner.waitForResolution(
            timeout: FlowTabUITestConditionObservationTestPolicy.watchdog
        )

        XCTAssertEqual(
            registrationOrder,
            ["observer", "readback", "cancel"]
        )
        XCTAssertEqual(initialEvidence?.source, .initialReadback)
        isSatisfied = false
        eventHandler?()
        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)
        owner.cancel()
    }

    func testFrontmostApplicationObserverUsesActivationNotificationEvidence() {
        let notificationCenter = NotificationCenter()
        let notificationName = Notification.Name(
            "FlowTabUITestFrontmostApplicationDidActivate"
        )
        var frontmostBundleIdentifier = "com.example.other"
        let owner = FlowTabUITestFrontmostApplicationObservationOwner(
            expectedBundleIdentifier: "com.example.target",
            notificationCenter: notificationCenter,
            activationNotificationName: notificationName,
            readback: { frontmostBundleIdentifier }
        )
        owner.start()
        defer { owner.cancel() }

        notificationCenter.post(
            name: notificationName,
            object: nil
        )
        XCTAssertNil(owner.resolvedEvidence)

        frontmostBundleIdentifier = "com.example.target"
        notificationCenter.post(
            name: notificationName,
            object: nil
        )

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestConditionObservationTestPolicy
                    .watchdog
        )
        XCTAssertEqual(evidence?.source, .eventReadback)
        XCTAssertEqual(
            evidence?.value.bundleIdentifier,
            "com.example.target"
        )
    }

    func testUIConditionObserverRejectsCancelledAndReplacedEventsUnderPressure() {
        for _ in 0..<FlowTabUITestConditionObservationTestPolicy.pressureIterations {
            var isSatisfied = false
            var eventHandlers: [() -> Void] = []
            let owner = FlowTabUITestConditionObservationOwner(
                eventRegistration: { callback in
                    eventHandlers.append(callback)
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { isSatisfied },
                isSatisfied: { $0 },
                describe: { "satisfied=\($0)" }
            )

            owner.start()
            let staleHandler = eventHandlers[0]
            owner.cancel()
            owner.start()
            isSatisfied = true
            staleHandler()
            XCTAssertNil(owner.resolvedEvidence)

            let currentHandler = eventHandlers[1]
            currentHandler()
            currentHandler()
            XCTAssertEqual(owner.resolvedEvidence?.generation, 2)
            XCTAssertEqual(owner.resolvedEvidence?.source, .eventReadback)
            owner.cancel()
        }
    }

    func testUIConditionObserverWatchdogReportsFinalReadback() {
        var readbackCount = 0
        let owner = FlowTabUITestConditionObservationOwner(
            readback: {
                defer { readbackCount += 1 }
                return readbackCount == 0
                    ? "com.example.other"
                    : "com.example.target"
            },
            isSatisfied: { $0 == "com.example.target" },
            describe: { "frontmost=\($0)" }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestConditionObservationTestPolicy
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
                "frontmost=com.example.target"
            )
        )
    }
}
