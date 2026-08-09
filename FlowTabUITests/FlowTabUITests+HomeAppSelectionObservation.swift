import Foundation

private enum FlowTabUITestHomeAppSelectionPhase: String {
    case initialReadback
    case awaitingTrigger
    case triggerCompleted
}

private final class FlowTabUITestHomeAppSelectionState {
    var phase: FlowTabUITestHomeAppSelectionPhase =
        .initialReadback

    var acceptsEvidence: Bool {
        phase != .awaitingTrigger
    }
}

struct FlowTabUITestHomeAppSelectionWatchdogBudget {
    private let deadline: TimeInterval
    private let monotonicTime: () -> TimeInterval

    init(
        timeout: TimeInterval,
        monotonicTime: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.monotonicTime = monotonicTime
        deadline =
            monotonicTime()
            + max(0, timeout)
    }

    var remaining: TimeInterval {
        max(0, deadline - monotonicTime())
    }
}

final class FlowTabUITestHomeAppSelectionObservationOwner<
    Element
> {
    private let state:
        FlowTabUITestHomeAppSelectionState
    private let deferredReadbacks:
        FlowTabUITestDeferredConditionReadbackRegistration
    private let projectionOwner:
        FlowTabUITestHomeWindowProjectionObservationOwner<Element>

    init(
        expectedTitle: String,
        scheduledRegistration:
            @escaping FlowTabUITestConditionObservationRegistration =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestHomeWindowProjectionSnapshot<Element>
    ) {
        let state = FlowTabUITestHomeAppSelectionState()
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration:
                    scheduledRegistration
            )
        self.state = state
        self.deferredReadbacks = deferredReadbacks
        projectionOwner =
            FlowTabUITestHomeWindowProjectionObservationOwner(
                expectation: .titleVisible(expectedTitle),
                acceptsEvidence: {
                    state.acceptsEvidence
                },
                observationRegistration: {
                    readback in
                    deferredReadbacks.register(readback)
                },
                readback: readback
            )
    }

    func start() {
        state.phase = .initialReadback
        projectionOwner.start()
        if projectionOwner.resolvedEvidence == nil {
            state.phase = .awaitingTrigger
        }
    }

    func markTriggerCompleted() {
        guard projectionOwner.resolvedEvidence == nil else {
            return
        }
        state.phase = .triggerCompleted
        projectionOwner.requestReadback(
            source: .triggerReadback
        )
        if projectionOwner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestHomeWindowProjectionSnapshot<Element>
    >? {
        projectionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestHomeWindowProjectionSnapshot<Element>
    >? {
        projectionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        "phase=\(state.phase.rawValue) "
            + projectionOwner.diagnosticSummary
    }

    func cancel() {
        projectionOwner.cancel()
    }
}
