import Foundation
import XCTest

enum FlowTabUITestHomeWindowRecencyWindowProjectionPolicy {
    static let targetWindowRowPublicationWatchdog: TimeInterval = 12

    static func acceptsInitialBaseline<Element>(
        _ snapshot: FlowTabUITestHomeWindowProjectionSnapshot<Element>,
        title: String
    ) -> Bool {
        snapshot.row(containing: title) == nil
    }
}

private enum FlowTabUITestHomeWindowRecencyWindowProjectionPhase: String {
    case initialReadback
    case awaitingAppSelection
    case appSelectionCompleted
}

extension FlowTabUITests {
    func waitForHomeWindowRecencyTargetWindowRowAfterSelectingApp(
        _ appRow: XCUIElement,
        appName: String,
        title: String,
        in app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement? {
        var phase:
            FlowTabUITestHomeWindowRecencyWindowProjectionPhase =
                .initialReadback
        let expectation =
            FlowTabUITestHomeWindowProjectionExpectation
                .rowContaining(title)
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration:
                    FlowTabUITestConditionReadbackScheduler
                        .mainRunLoopRegistration(
                            cadence:
                                FlowTabUITestConditionObservationPolicy
                                    .xcuiReadbackCadence
                        )
            )
        let observation =
            FlowTabUITestHomeWindowProjectionObservationOwner(
                expectation: expectation,
                acceptsEvidence: {
                    phase == .appSelectionCompleted
                },
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                readback: {
                    self.homeWindowProjectionSnapshot(
                        in: app,
                        expectation: expectation
                    )
                }
            )
        observation.start()
        defer { observation.cancel() }
        phase = .awaitingAppSelection

        guard let initialEvidence = observation.latestEvidence,
              initialEvidence.source == .initialReadback,
              FlowTabUITestHomeWindowRecencyWindowProjectionPolicy
                .acceptsInitialBaseline(
                    initialEvidence.value,
                    title: title
                )
        else {
            XCTFail(
                "Home recency target-window observation did not establish "
                    + "its target-row-absent initial readback. "
                    + "target=\(targetDescription) title=\(title) "
                    + "phase=\(phase.rawValue) "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return nil
        }

        tapElement(appRow)
        phase = .appSelectionCompleted
        observation.requestReadback(source: .triggerReadback)
        if observation.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }

        guard let evidence = observation.waitForResolution(
            timeout:
                FlowTabUITestHomeWindowRecencyWindowProjectionPolicy
                    .targetWindowRowPublicationWatchdog
        ), let row = evidence.value.row(containing: title) else {
            XCTFail(
                "Home recency target-window row publication watchdog "
                    + "expired. target=\(targetDescription) "
                    + "app=\(appName) title=\(title) "
                    + "phase=\(phase.rawValue) "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return nil
        }
        return row.element
    }

    func testHomeWindowRecencyWindowProjectionPolicyCompatibility() {
        let watchdog =
            FlowTabUITestHomeWindowRecencyWindowProjectionPolicy
                .targetWindowRowPublicationWatchdog
        XCTAssertEqual(watchdog, 12)
        XCTAssertTrue(watchdog.isFinite)
        XCTAssertGreaterThan(watchdog, 0)

        let initialSnapshot =
            FlowTabUITestHomeWindowProjectionSnapshot(
                rows: [] as [FlowTabUITestHomeWindowRowSnapshot<String>],
                visibleStaticTextTitles: []
            )
        let staleSnapshot =
            FlowTabUITestHomeWindowProjectionSnapshot(
                rows: [
                    FlowTabUITestHomeWindowRowSnapshot(
                        identifier: "flowtab.home.window.test",
                        label: "Draft",
                        value: "Draft",
                        element: "row"
                    )
                ],
                visibleStaticTextTitles: []
            )
        XCTAssertTrue(
            FlowTabUITestHomeWindowRecencyWindowProjectionPolicy
                .acceptsInitialBaseline(initialSnapshot, title: "Draft")
        )
        XCTAssertFalse(
            FlowTabUITestHomeWindowRecencyWindowProjectionPolicy
                .acceptsInitialBaseline(staleSnapshot, title: "Draft")
        )
    }
}
