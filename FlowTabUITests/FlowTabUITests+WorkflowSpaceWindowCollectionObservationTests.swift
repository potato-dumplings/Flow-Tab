import Foundation
import XCTest

private enum FlowTabUITestWorkflowSpaceWindowCollectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testWorkflowSpaceWindowCollectionObserverAcceptsMatchingSiblingInitially() {
        var order: [String] = []
        let snapshot =
            workflowSpaceWindowCollectionTestSnapshot(
                windows: [
                    (41, "Noisy", nil),
                    (42, "Fullscreen", nil)
                ]
            )
        let owner =
            FlowTabUITestWorkflowSpaceWindowCollectionObservationOwner(
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
            owner.resolvedEvidence?.value
                .matchingWindow(title: "Fullscreen")?
                .number,
            42
        )
        XCTAssertEqual(
            order,
            ["register", "readback", "cancel"]
        )
    }

    func testWorkflowSpaceWindowCollectionObserverSlowReadbacksOnlyDelayResolution() {
        var readback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot =
            workflowSpaceWindowCollectionTestSnapshot(
                windows: [(41, "Noisy", nil)]
            )
        let owner =
            FlowTabUITestWorkflowSpaceWindowCollectionObservationOwner(
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
        snapshot =
            workflowSpaceWindowCollectionTestSnapshot(
                windows: [
                    (41, "Noisy", nil),
                    (42, "Fullscreen", nil)
                ]
            )
        readback?(.notificationReadback)

        XCTAssertEqual(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestWorkflowSpaceWindowCollectionTestPolicy
                        .watchdog
            )?.source,
            .notificationReadback
        )
    }

    func testWorkflowSpaceWindowCollectionSnapshotAcceptsTitlelessFullscreenSibling() {
        let snapshot =
            workflowSpaceWindowCollectionTestSnapshot(
                windows: [
                    (41, "Noisy", nil),
                    (
                        42,
                        nil,
                        CGRect(
                            x: 0,
                            y: 0,
                            width: 100_000,
                            height: 100_000
                        )
                    )
                ]
            )

        XCTAssertEqual(
            snapshot.matchingWindow(
                title: "Fullscreen"
            )?.number,
            42
        )
    }

    func testWorkflowSpaceWindowCollectionObserverRejectsStaleEventsUnderPressure() {
        for _ in 0..<FlowTabUITestWorkflowSpaceWindowCollectionTestPolicy
            .pressureIterations
        {
            var readbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var snapshot =
                workflowSpaceWindowCollectionTestSnapshot(
                    windows: [(41, "Noisy", nil)]
                )
            let owner =
                FlowTabUITestWorkflowSpaceWindowCollectionObservationOwner(
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
            snapshot =
                workflowSpaceWindowCollectionTestSnapshot(
                    windows: [
                        (41, "Noisy", nil),
                        (42, "Fullscreen", nil)
                    ]
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

    func testWorkflowSpaceWindowCollectionWatchdogReportsFinalReadback() {
        var readbackCount = 0
        let owner =
            FlowTabUITestWorkflowSpaceWindowCollectionObservationOwner(
                expectedTitle: "Fullscreen",
                observationRegistration: nil,
                readback: {
                    defer { readbackCount += 1 }
                    return self
                        .workflowSpaceWindowCollectionTestSnapshot(
                            windows:
                                readbackCount == 0
                                    ? [(41, "Noisy", nil)]
                                    : [
                                        (41, "Noisy", nil),
                                        (42, "Fullscreen", nil)
                                    ]
                        )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestWorkflowSpaceWindowCollectionTestPolicy
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
                "42:Fullscreen"
            )
        )
    }

    private func workflowSpaceWindowCollectionTestSnapshot(
        windows: [
            (
                number: CGWindowID,
                title: String?,
                frame: CGRect?
            )
        ]
    ) -> FlowTabUITestWorkflowSpaceWindowCollectionSnapshot {
        FlowTabUITestWorkflowSpaceWindowCollectionSnapshot(
            observations: windows.map {
                WorkflowCGWindowObservation(
                    number: $0.number,
                    title: $0.title,
                    frame: $0.frame
                )
            }
        )
    }
}
