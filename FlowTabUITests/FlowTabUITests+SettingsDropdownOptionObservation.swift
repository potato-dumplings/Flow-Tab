import Foundation
import XCTest

enum FlowTabUITestSettingsDropdownOptionIdentity: String {
    case scoped
    case raw
}

struct FlowTabUITestSettingsDropdownOptionSnapshot<Element> {
    let scopedExists: Bool
    let rawExists: Bool
    let selectedIdentity:
        FlowTabUITestSettingsDropdownOptionIdentity?
    let selectedElement: Element?

    init(
        scopedElement: Element?,
        rawElement: Element?
    ) {
        scopedExists = scopedElement != nil
        rawExists = rawElement != nil
        if let scopedElement {
            selectedIdentity = .scoped
            selectedElement = scopedElement
        } else if let rawElement {
            selectedIdentity = .raw
            selectedElement = rawElement
        } else {
            selectedIdentity = nil
            selectedElement = nil
        }
    }

    var diagnosticSummary: String {
        "scopedExists=\(scopedExists ? 1 : 0) "
            + "rawExists=\(rawExists ? 1 : 0) "
            + "selectedIdentity="
            + "\(selectedIdentity?.rawValue ?? "nil")"
    }
}

enum FlowTabUITestSettingsDropdownOptionWatchdogPolicy {
    static let projection: TimeInterval = 5
}

private enum FlowTabUITestSettingsDropdownOptionPhase: String {
    case initialReadback
    case awaitingTrigger
    case triggerCompleted
}

private final class FlowTabUITestSettingsDropdownOptionState {
    var phase: FlowTabUITestSettingsDropdownOptionPhase =
        .initialReadback

    var acceptsEvidence: Bool {
        phase == .triggerCompleted
    }
}

final class FlowTabUITestSettingsDropdownOptionObservationOwner<Element> {
    private let scopedIdentifier: String
    private let rawIdentifier: String
    private let state: FlowTabUITestSettingsDropdownOptionState
    private let deferredReadbacks:
        FlowTabUITestDeferredConditionReadbackRegistration
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSettingsDropdownOptionSnapshot<Element>
        >

    init(
        scopedIdentifier: String,
        rawIdentifier: String,
        scheduledRegistration:
            @escaping FlowTabUITestConditionObservationRegistration =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestSettingsDropdownOptionSnapshot<Element>
    ) {
        let state = FlowTabUITestSettingsDropdownOptionState()
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration:
                    scheduledRegistration
            )
        self.scopedIdentifier = scopedIdentifier
        self.rawIdentifier = rawIdentifier
        self.state = state
        self.deferredReadbacks = deferredReadbacks
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: { callback in
                deferredReadbacks.register(callback)
            },
            readback: readback,
            isSatisfied: { snapshot in
                state.acceptsEvidence
                    && snapshot.selectedElement != nil
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
        FlowTabUITestSettingsDropdownOptionSnapshot<Element>
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsDropdownOptionSnapshot<Element>
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsDropdownOptionSnapshot<Element>
    >? {
        conditionOwner.latestEvidence
    }

    var diagnosticSummary: String {
        "scopedIdentifier=\(scopedIdentifier) "
            + "rawIdentifier=\(rawIdentifier) "
            + "phase=\(state.phase.rawValue) "
            + conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    func waitForSettingsDropdownOption(
        in app: XCUIApplication,
        controlIdentifier: String,
        optionIdentifier: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        trigger: () -> Void
    ) -> XCUIElement? {
        let scopedOptionIdentifier =
            "\(controlIdentifier).option.\(optionIdentifier)"
        let scopedOption = app.descendants(matching: .any)
            .matching(identifier: scopedOptionIdentifier)
            .firstMatch
        let rawOption = app.descendants(matching: .any)
            .matching(identifier: optionIdentifier)
            .firstMatch
        let optionObservation =
            FlowTabUITestSettingsDropdownOptionObservationOwner(
                scopedIdentifier: scopedOptionIdentifier,
                rawIdentifier: optionIdentifier,
                readback: {
                    let scopedElement =
                        scopedOption.exists ? scopedOption : nil
                    let rawElement =
                        rawOption.exists ? rawOption : nil
                    return FlowTabUITestSettingsDropdownOptionSnapshot(
                        scopedElement: scopedElement,
                        rawElement: rawElement
                    )
                }
            )
        optionObservation.start()
        defer { optionObservation.cancel() }

        trigger()
        optionObservation.markTriggerCompleted()
        guard
            let evidence = optionObservation.waitForResolution(
                timeout:
                    FlowTabUITestSettingsDropdownOptionWatchdogPolicy
                        .projection
            ),
            let option = evidence.value.selectedElement
        else {
            XCTFail(
                "Settings dropdown option projection watchdog expired. "
                    + optionObservation.diagnosticSummary,
                file: file,
                line: line
            )
            return nil
        }
        return option
    }
}
