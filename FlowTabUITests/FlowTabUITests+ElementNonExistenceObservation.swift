import Foundation
import XCTest

private enum FlowTabUITestElementNonExistencePhase: String {
    case initialReadback
    case awaitingTrigger
    case triggerCompleted
}

private final class FlowTabUITestElementNonExistenceState {
    var phase: FlowTabUITestElementNonExistencePhase =
        .initialReadback

    var acceptsEvidence: Bool {
        phase == .triggerCompleted
    }
}

struct FlowTabUITestElementExistenceSnapshot: Equatable {
    let exists: Bool

    var diagnosticSummary: String {
        "exists=\(exists ? 1 : 0)"
    }
}

final class FlowTabUITestElementNonExistenceObservationOwner {
    private let elementIdentifier: String
    private let state: FlowTabUITestElementNonExistenceState
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
        let state = FlowTabUITestElementNonExistenceState()
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
                state.acceptsEvidence && !snapshot.exists
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
        conditionOwner.requestReadback(
            source: .triggerReadback
        )
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
    func assertElementDoesNotExistAfterTrigger(
        _ element: XCUIElement,
        timeout: TimeInterval,
        description: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        trigger: () -> Void
    ) {
        let observation =
            FlowTabUITestElementNonExistenceObservationOwner(
                elementIdentifier: element.identifier,
                readback: { element.exists }
            )
        observation.start()
        defer { observation.cancel() }

        if observation.latestEvidence?.value.exists != true {
            XCTFail(
                "\(description) baseline mismatch; expectedExists=1. "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
        }

        trigger()
        observation.markTriggerCompleted()
        guard observation.waitForResolution(timeout: timeout) != nil else {
            XCTFail(
                "\(description) watchdog expired. "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return
        }
    }
}
