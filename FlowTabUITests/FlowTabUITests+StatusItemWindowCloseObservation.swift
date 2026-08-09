import Foundation
import XCTest

enum StatusItemWindowCloseUITestPolicy {
    static let projectionWatchdog: TimeInterval = 6
    static let homeWindowTitle = "FlowTab"
}

struct StatusItemWindowCloseSnapshot: Equatable {
    let applicationState: String
    let applicationIsRunning: Bool
    let homeWindowExists: Bool
    let logsContentExists: Bool

    var isOpenLogsProjection: Bool {
        applicationIsRunning
            && homeWindowExists
            && logsContentExists
    }

    var isClosedProjection: Bool {
        applicationIsRunning
            && homeWindowExists == false
            && logsContentExists == false
    }

    var diagnosticSummary: String {
        "applicationState=\(applicationState) "
            + "applicationIsRunning=\(applicationIsRunning) "
            + "homeWindowExists=\(homeWindowExists) "
            + "logsContentExists=\(logsContentExists) "
            + "isOpenLogsProjection=\(isOpenLogsProjection) "
            + "isClosedProjection=\(isClosedProjection)"
    }
}

final class StatusItemWindowCloseObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            StatusItemWindowCloseSnapshot
        >

    init(
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () -> StatusItemWindowCloseSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: \.isClosedProjection,
            describe: \.diagnosticSummary
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
        StatusItemWindowCloseSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        StatusItemWindowCloseSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        StatusItemWindowCloseSnapshot
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
    func assertStatusItemMainWindowCloses(
        in app: XCUIApplication,
        trigger: () -> Void
    ) {
        let observation = makeStatusItemWindowCloseObservation(
            in: app
        )
        observation.start()
        defer { observation.cancel() }

        XCTAssertEqual(
            observation.latestEvidence?.source,
            .initialReadback
        )
        XCTAssertTrue(
            observation.latestEvidence?.value
                .isOpenLogsProjection == true,
            "Status-item window-close baseline was not the exact open Logs projection. "
                + observation.diagnosticSummary
        )
        XCTAssertNil(observation.resolvedEvidence)

        trigger()
        observation.requestReadback(source: .triggerReadback)

        XCTAssertNotNil(
            observation.waitForResolution(
                timeout:
                    StatusItemWindowCloseUITestPolicy
                        .projectionWatchdog
            ),
            "Status-item main-window close watchdog expired. "
                + observation.diagnosticSummary
        )
    }

    private func makeStatusItemWindowCloseObservation(
        in app: XCUIApplication
    ) -> StatusItemWindowCloseObservationOwner {
        let homeWindow = app.windows[
            StatusItemWindowCloseUITestPolicy.homeWindowTitle
        ]
        let logsContent = element(
            in: app,
            identifier: Identifier.logsTabContent
        )
        return StatusItemWindowCloseObservationOwner(
            readback: {
                let applicationState = app.state
                return StatusItemWindowCloseSnapshot(
                    applicationState:
                        self.statusItemWindowCloseStateLabel(
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

    private func statusItemWindowCloseStateLabel(
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
