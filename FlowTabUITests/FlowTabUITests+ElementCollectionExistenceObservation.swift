import Foundation
import XCTest

struct FlowTabUITestElementExistenceReadback: Equatable {
    let identifier: String
    let exists: Bool
}

struct FlowTabUITestElementCollectionExistenceSnapshot: Equatable {
    let expectedIdentifiers: [String]
    let elements: [FlowTabUITestElementExistenceReadback]

    var isCompleteProjection: Bool {
        !expectedIdentifiers.isEmpty
            && elements.map(\.identifier) == expectedIdentifiers
            && elements.allSatisfy(\.exists)
    }

    var diagnosticSummary: String {
        let expected = expectedIdentifiers.joined(separator: ",")
        let observed = elements.map {
            "\($0.identifier)=\($0.exists ? 1 : 0)"
        }.joined(separator: ",")
        return "isCompleteProjection=\(isCompleteProjection) "
            + "expected=[\(expected)] observed=[\(observed)]"
    }
}

private enum FlowTabUITestElementCollectionExistencePhase: String {
    case initialReadback
    case awaitingTrigger
    case triggerCompleted
}

private final class FlowTabUITestElementCollectionExistenceState {
    var phase: FlowTabUITestElementCollectionExistencePhase =
        .initialReadback

    var acceptsEvidence: Bool {
        phase == .triggerCompleted
    }
}

final class FlowTabUITestElementCollectionExistenceObservationOwner {
    private let state: FlowTabUITestElementCollectionExistenceState
    private let deferredReadbacks:
        FlowTabUITestDeferredConditionReadbackRegistration
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestElementCollectionExistenceSnapshot
        >

    init(
        expectedIdentifiers: [String],
        scheduledRegistration:
            @escaping FlowTabUITestConditionObservationRegistration =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            [FlowTabUITestElementExistenceReadback]
    ) {
        let state = FlowTabUITestElementCollectionExistenceState()
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration:
                    scheduledRegistration
            )
        self.state = state
        self.deferredReadbacks = deferredReadbacks
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: { callback in
                deferredReadbacks.register(callback)
            },
            readback: {
                FlowTabUITestElementCollectionExistenceSnapshot(
                    expectedIdentifiers: expectedIdentifiers,
                    elements: readback()
                )
            },
            isSatisfied: { snapshot in
                state.acceptsEvidence
                    && snapshot.isCompleteProjection
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
        FlowTabUITestElementCollectionExistenceSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestElementCollectionExistenceSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestElementCollectionExistenceSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var diagnosticSummary: String {
        "phase=\(state.phase.rawValue) "
            + conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    func waitForExactElementCollection(
        in app: XCUIApplication,
        identifiers: [String],
        watchdog: TimeInterval,
        targetDescription: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        trigger: () -> Void
    ) -> [XCUIElement]? {
        let elements = identifiers.map {
            element(in: app, identifier: $0)
        }
        let observation =
            FlowTabUITestElementCollectionExistenceObservationOwner(
                expectedIdentifiers: identifiers,
                readback: {
                    zip(identifiers, elements).map {
                        FlowTabUITestElementExistenceReadback(
                            identifier: $0.0,
                            exists: $0.1.exists
                        )
                    }
                }
            )
        observation.start()
        defer { observation.cancel() }

        guard observation.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "\(targetDescription) did not establish its initial "
                    + "readback. " + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return nil
        }

        trigger()
        observation.markTriggerCompleted()
        guard
            observation.waitForResolution(timeout: watchdog) != nil
        else {
            XCTFail(
                "\(targetDescription) projection watchdog expired. "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return nil
        }
        return elements
    }
}
