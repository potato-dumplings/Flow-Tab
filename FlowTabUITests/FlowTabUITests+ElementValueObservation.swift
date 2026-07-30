import Foundation
import XCTest

struct FlowTabUITestElementValueSnapshot {
    let identifier: String
    let exists: Bool
    let value: String?
}

final class FlowTabUITestElementValueObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestElementValueSnapshot
        >

    init(
        expectedDescription: String,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestElementValueSnapshot,
        isSatisfied: @escaping (String) -> Bool
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: { snapshot in
                snapshot.exists
                    && snapshot.value.map(isSatisfied) == true
            },
            describe: { snapshot in
                "identifier=\(snapshot.identifier) "
                    + "exists=\(snapshot.exists) "
                    + "expected{\(expectedDescription)} "
                    + "actual=\(snapshot.value ?? "nil")"
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestElementValueSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    func assertValue(
        of element: XCUIElement,
        equals expectedValue: String,
        timeout: TimeInterval = 5
    ) {
        assertElementValue(
            of: element,
            expectedDescription: "equals \(expectedValue)",
            timeout: timeout,
            isSatisfied: { $0 == expectedValue }
        )
    }

    func assertValuePrefix(
        of element: XCUIElement,
        expectedPrefix: String,
        timeout: TimeInterval = 5
    ) {
        assertElementValue(
            of: element,
            expectedDescription: "hasPrefix \(expectedPrefix)",
            timeout: timeout,
            isSatisfied: { $0.hasPrefix(expectedPrefix) }
        )
    }

    private func assertElementValue(
        of element: XCUIElement,
        expectedDescription: String,
        timeout: TimeInterval,
        isSatisfied: @escaping (String) -> Bool
    ) {
        let owner = FlowTabUITestElementValueObservationOwner(
            expectedDescription: expectedDescription,
            readback: {
                let exists = element.exists
                return FlowTabUITestElementValueSnapshot(
                    identifier: element.identifier,
                    exists: exists,
                    value: exists
                        ? self.elementStringValue(element)
                        : nil
                )
            },
            isSatisfied: isSatisfied
        )
        owner.start()
        defer { owner.cancel() }

        guard
            owner.waitForResolution(timeout: timeout) != nil
        else {
            XCTFail(
                "Element value did not satisfy "
                    + "\(expectedDescription). "
                    + owner.diagnosticSummary
            )
            return
        }
    }
}
