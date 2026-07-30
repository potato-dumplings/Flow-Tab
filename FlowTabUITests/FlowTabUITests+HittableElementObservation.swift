import Foundation
import XCTest

struct FlowTabUITestHittableElementSnapshot<Element> {
    let candidateCount: Int
    let observedExistingIndices: [Int]
    let firstHittableIndex: Int?
    let firstHittableElement: Element?

    var diagnosticSummary: String {
        "candidateCount=\(candidateCount) "
            + "observedExistingIndices=\(observedExistingIndices) "
            + "firstHittableIndex="
            + "\(firstHittableIndex.map(String.init) ?? "nil")"
    }
}

final class FlowTabUITestHittableElementObservationOwner<Element> {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestHittableElementSnapshot<Element>
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
        readback: @escaping () ->
            FlowTabUITestHittableElementSnapshot<Element>
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: {
                $0.firstHittableElement != nil
            },
            describe: \.diagnosticSummary
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestHittableElementSnapshot<Element>
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
    func tapFirstHittable(
        in query: XCUIElementQuery,
        timeout: TimeInterval
    ) -> Bool {
        guard
            let element = waitForFirstHittableElement(
                in: query,
                timeout: timeout
            )
        else {
            return false
        }
        element.tap()
        return true
    }

    func hasHittableElement(
        in query: XCUIElementQuery,
        timeout: TimeInterval
    ) -> Bool {
        waitForFirstHittableElement(
            in: query,
            timeout: timeout
        ) != nil
    }

    private func waitForFirstHittableElement(
        in query: XCUIElementQuery,
        timeout: TimeInterval
    ) -> XCUIElement? {
        let owner =
            FlowTabUITestHittableElementObservationOwner(
                readback: {
                    self.hittableElementSnapshot(in: query)
                }
            )
        owner.start()
        defer { owner.cancel() }

        guard
            let evidence = owner.waitForResolution(
                timeout: timeout
            )
        else {
            print(
                "FlowTab UI hittable-element watchdog expired. "
                    + owner.diagnosticSummary
            )
            return nil
        }
        return evidence.value.firstHittableElement
    }

    private func hittableElementSnapshot(
        in query: XCUIElementQuery
    ) -> FlowTabUITestHittableElementSnapshot<XCUIElement> {
        let candidateCount = query.count
        var observedExistingIndices: [Int] = []

        for index in 0..<candidateCount {
            let element = query.element(boundBy: index)
            guard element.exists else { continue }
            observedExistingIndices.append(index)
            guard element.isHittable else { continue }
            return FlowTabUITestHittableElementSnapshot(
                candidateCount: candidateCount,
                observedExistingIndices: observedExistingIndices,
                firstHittableIndex: index,
                firstHittableElement: element
            )
        }

        return FlowTabUITestHittableElementSnapshot(
            candidateCount: candidateCount,
            observedExistingIndices: observedExistingIndices,
            firstHittableIndex: nil,
            firstHittableElement: nil
        )
    }
}
