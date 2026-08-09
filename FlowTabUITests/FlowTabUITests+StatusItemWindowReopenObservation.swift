import Foundation
import XCTest

enum StatusItemWindowReopenUITestPolicy {
    static let projectionWatchdog: TimeInterval = 8
}

final class StatusItemWindowReopenObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            StatusItemWindowProjectionSnapshot
        >

    init(
        acceptsEvidence: @escaping () -> Bool = {
            true
        },
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            StatusItemWindowProjectionSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: { snapshot in
                acceptsEvidence()
                    && snapshot.isOpenLogsProjection
            },
            describe: { snapshot in
                "expected=openLogs "
                    + "acceptanceEnabled=\(acceptsEvidence()) "
                    + snapshot.diagnosticSummary
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func requestReadback(
        source: FlowTabUITestConditionObservationSource
    ) {
        conditionOwner.requestReadback(source: source)
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        StatusItemWindowProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        StatusItemWindowProjectionSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        StatusItemWindowProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    func assertStatusItemMainWindowReopens(
        in app: XCUIApplication,
        trigger: () -> Void
    ) {
        var triggerCompleted = false
        let observation = makeStatusItemWindowReopenObservation(
            in: app,
            acceptsEvidence: {
                triggerCompleted
            }
        )
        observation.start()
        defer { observation.cancel() }

        XCTAssertEqual(
            observation.latestEvidence?.source,
            .initialReadback
        )
        XCTAssertTrue(
            observation.latestEvidence?.value
                .isClosedProjection == true,
            "Status-item window-reopen baseline was not the exact closed projection. "
                + observation.diagnosticSummary
        )
        XCTAssertNil(observation.resolvedEvidence)

        trigger()
        triggerCompleted = true
        observation.requestReadback(source: .triggerReadback)

        XCTAssertNotNil(
            observation.waitForResolution(
                timeout:
                    StatusItemWindowReopenUITestPolicy
                        .projectionWatchdog
            ),
            "Status-item main-window reopen watchdog expired. "
                + observation.diagnosticSummary
        )
    }

    private func makeStatusItemWindowReopenObservation(
        in app: XCUIApplication,
        acceptsEvidence: @escaping () -> Bool
    ) -> StatusItemWindowReopenObservationOwner {
        let homeWindow = app.windows[
            StatusItemWindowUITestIdentity.homeWindowTitle
        ]
        let logsContent = element(
            in: app,
            identifier: Identifier.logsTabContent
        )
        return StatusItemWindowReopenObservationOwner(
            acceptsEvidence: acceptsEvidence,
            readback: {
                let applicationState = app.state
                return StatusItemWindowProjectionSnapshot(
                    applicationState:
                        self.statusItemWindowReopenStateLabel(
                            applicationState
                        ),
                    applicationIsRunning:
                        applicationState == .runningForeground
                            || applicationState == .runningBackground,
                    homeWindowExists: homeWindow.exists,
                    logsContentExists: logsContent.exists
                )
            }
        )
    }

    private func statusItemWindowReopenStateLabel(
        _ state: XCUIApplication.State
    ) -> String {
        switch state {
        case .unknown:
            "unknown"
        case .notRunning:
            "notRunning"
        case .runningBackground:
            "runningBackground"
        case .runningForeground:
            "runningForeground"
        @unknown default:
            String(describing: state)
        }
    }
}
