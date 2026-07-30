import CoreGraphics
import Foundation
import XCTest

extension FlowTabUITests {
    func tapFirstHittableAfterScrolling(
        in query: XCUIElementQuery,
        scrollContainer: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let owner =
            FlowTabUITestScrollingHittableElementObservationOwner(
                readback: {
                    self.scrollingHittableElementSnapshot(
                        in: query,
                        scrollContainer: scrollContainer
                    )
                },
                scroll: { deltaY in
                    scrollContainer.scroll(
                        byDeltaX: 0,
                        deltaY: deltaY
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        guard
            let element = owner.waitForResolution(
                timeout: timeout
            )?.value.firstHittableElement
        else {
            print(
                "FlowTab UI scrolling-hittable watchdog expired. "
                    + owner.diagnosticSummary
            )
            return false
        }
        element.tap()
        return true
    }

    private func scrollingHittableElementSnapshot(
        in query: XCUIElementQuery,
        scrollContainer: XCUIElement
    ) -> FlowTabUITestScrollingHittableElementSnapshot<
        XCUIElement
    > {
        let candidateCount = query.count
        let scrollContainerExists =
            scrollContainer.exists
        let scrollContainerFrame =
            scrollContainerExists
            ? scrollContainer.frame
            : nil
        var observedExistingIndices: [Int] = []
        var firstExistingIndex: Int?
        var firstExistingFrame: CGRect?

        for index in 0..<candidateCount {
            let element = query.element(boundBy: index)
            guard element.exists else { continue }
            observedExistingIndices.append(index)
            if firstExistingIndex == nil {
                firstExistingIndex = index
                firstExistingFrame = element.frame
            }
            guard element.isHittable else { continue }
            return FlowTabUITestScrollingHittableElementSnapshot(
                candidateCount: candidateCount,
                observedExistingIndices:
                    observedExistingIndices,
                firstExistingIndex: firstExistingIndex,
                firstExistingFrame: firstExistingFrame,
                firstHittableIndex: index,
                firstHittableElement: element,
                scrollContainerExists:
                    scrollContainerExists,
                scrollContainerFrame:
                    scrollContainerFrame
            )
        }

        return FlowTabUITestScrollingHittableElementSnapshot(
            candidateCount: candidateCount,
            observedExistingIndices:
                observedExistingIndices,
            firstExistingIndex: firstExistingIndex,
            firstExistingFrame: firstExistingFrame,
            firstHittableIndex: nil,
            firstHittableElement: nil,
            scrollContainerExists:
                scrollContainerExists,
            scrollContainerFrame:
                scrollContainerFrame
        )
    }

    func tapElementAfterScrollingIntoView(
        _ element: XCUIElement,
        in scrollContainer: XCUIElement,
        fallbackScrollContainers: [XCUIElement] = [],
        timeout: TimeInterval
    ) -> Bool {
        let owner =
            FlowTabUITestScrollingElementVisibilityObservationOwner(
                readback: {
                    self.scrollingElementVisibilitySnapshot(
                        element,
                        preferredContainer: scrollContainer,
                        fallbackContainers:
                            fallbackScrollContainers
                    )
                },
                scroll: { container, deltaY in
                    container.scroll(
                        byDeltaX: 0,
                        deltaY: deltaY
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        guard
            let resolvedElement =
                owner.waitForResolution(
                    timeout: timeout
                )?.value.resolvedElement
        else {
            print(
                "FlowTab UI scrolling-visibility watchdog expired. "
                    + owner.diagnosticSummary
            )
            return false
        }
        resolvedElement.tap()
        return true
    }

    private func scrollingElementVisibilitySnapshot(
        _ element: XCUIElement,
        preferredContainer: XCUIElement,
        fallbackContainers: [XCUIElement]
    ) -> FlowTabUITestScrollingElementVisibilitySnapshot<
        XCUIElement
    > {
        let elementExists = element.exists
        let elementFrame =
            elementExists ? element.frame : nil
        let elementHittable =
            elementExists && element.isHittable

        let preferredCandidate:
            FlowTabUITestScrollingContainerCandidate<XCUIElement>?
        if preferredContainer.exists {
            preferredCandidate =
                FlowTabUITestScrollingContainerCandidate(
                    source: .preferred,
                    element: preferredContainer,
                    frame: preferredContainer.frame
                )
        } else {
            preferredCandidate = nil
        }
        let fallbackCandidates =
            fallbackContainers.enumerated().compactMap {
                index,
                candidate
                -> FlowTabUITestScrollingContainerCandidate<
                    XCUIElement
                >? in
                guard candidate.exists else { return nil }
                return FlowTabUITestScrollingContainerCandidate(
                    source: .fallback(index: index),
                    element: candidate,
                    frame: candidate.frame
                )
            }
        let selectedContainer =
            FlowTabUITestScrollingContainerSelection.select(
                elementFrame: elementFrame,
                preferred: preferredCandidate,
                fallbacks: fallbackCandidates
            )

        return FlowTabUITestScrollingElementVisibilitySnapshot(
            element: element,
            elementExists: elementExists,
            elementHittable: elementHittable,
            elementFrame: elementFrame,
            scrollContainerSource:
                selectedContainer?.source ?? .unavailable,
            scrollContainer: selectedContainer?.element,
            scrollContainerFrame: selectedContainer?.frame
        )
    }

    func isUsableFrame(_ frame: CGRect) -> Bool {
        !frame.isEmpty && !frame.isNull && !frame.isInfinite
    }
}
