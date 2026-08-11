import Foundation
import XCTest

private enum FlowTabUITestElementExistencePhase: String {
    case initialReadback
    case awaitingTrigger
    case triggerCompleted
}

private final class FlowTabUITestElementExistenceState {
    var phase: FlowTabUITestElementExistencePhase =
        .initialReadback

    var acceptsEvidence: Bool {
        phase == .triggerCompleted
    }
}

final class FlowTabUITestElementExistenceObservationOwner {
    private let elementIdentifier: String
    private let state: FlowTabUITestElementExistenceState
    private let deferredReadbacks:
        FlowTabUITestDeferredConditionReadbackRegistration
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestElementExistenceSnapshot
        >

    init(
        elementIdentifier: String,
        scheduledRegistration:
            @escaping FlowTabUITestConditionObservationRegistration =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () -> Bool
    ) {
        let state = FlowTabUITestElementExistenceState()
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration:
                    scheduledRegistration
            )
        self.elementIdentifier = elementIdentifier
        self.state = state
        self.deferredReadbacks = deferredReadbacks
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: { callback in
                deferredReadbacks.register(callback)
            },
            readback: {
                FlowTabUITestElementExistenceSnapshot(
                    exists: readback()
                )
            },
            isSatisfied: { snapshot in
                state.acceptsEvidence && snapshot.exists
            },
            describe: \.diagnosticSummary
        )
    }

    func start() {
        state.phase = .initialReadback
        conditionOwner.start()
        state.phase = .awaitingTrigger
    }

    func markTriggerCompleted() {
        guard conditionOwner.resolvedEvidence == nil else {
            return
        }
        state.phase = .triggerCompleted
        conditionOwner.requestReadback(source: .triggerReadback)
        if conditionOwner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestElementExistenceSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestElementExistenceSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestElementExistenceSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var diagnosticSummary: String {
        "elementIdentifier=\(elementIdentifier) "
            + "phase=\(state.phase.rawValue) "
            + conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    func waitForSettingsControl(
        in app: XCUIApplication,
        identifier: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        trigger: () -> Void
    ) -> XCUIElement? {
        let control = element(in: app, identifier: identifier)
        let observation =
            FlowTabUITestElementExistenceObservationOwner(
                elementIdentifier: identifier,
                readback: { control.exists }
            )
        observation.start()
        defer { observation.cancel() }

        trigger()
        observation.markTriggerCompleted()
        guard
            observation.waitForResolution(
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .settingsControlDiscovery
            ) != nil
        else {
            XCTFail(
                "Settings control readiness watchdog expired. "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return nil
        }
        return control
    }
}
