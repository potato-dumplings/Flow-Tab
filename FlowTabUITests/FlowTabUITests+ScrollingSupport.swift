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
        let deadline = Date().addingTimeInterval(timeout)
        var attempt = 0
        repeat {
            if let container = scrollContainerForElement(
                element,
                preferredContainer: scrollContainer,
                fallbackContainers: fallbackScrollContainers
            ) {
                if element.isHittable && isElementFullyVisible(element, in: container) {
                    element.tap()
                    return true
                }
                let deltaY = scrollDeltaY(for: element, in: container, attempt: attempt)
                container.scroll(byDeltaX: 0, deltaY: deltaY)
                attempt = (attempt + 1) % 24
            } else if element.exists && element.isHittable {
                element.tap()
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        if let container = scrollContainerForElement(
            element,
            preferredContainer: scrollContainer,
            fallbackContainers: fallbackScrollContainers
        ), element.isHittable, isElementFullyVisible(element, in: container) {
            element.tap()
            return true
        }
        return false
    }

    private func scrollContainerForElement(
        _ element: XCUIElement,
        preferredContainer: XCUIElement,
        fallbackContainers: [XCUIElement]
    ) -> XCUIElement? {
        if preferredContainer.exists {
            return preferredContainer
        }
        guard element.exists else { return nil }
        let elementFrame = element.frame
        guard isUsableFrame(elementFrame) else { return nil }

        return fallbackContainers
            .filter { $0.exists && isUsableFrame($0.frame) }
            .filter { candidate in
                candidate.frame.minX <= elementFrame.midX && candidate.frame.maxX >= elementFrame.midX
            }
            .min { lhs, rhs in
                let lhsFrame = lhs.frame
                let rhsFrame = rhs.frame
                let lhsArea = lhsFrame.width * lhsFrame.height
                let rhsArea = rhsFrame.width * rhsFrame.height
                return lhsArea < rhsArea
            }
    }

    private func scrollDeltaY(
        for element: XCUIElement,
        in container: XCUIElement,
        attempt: Int
    ) -> CGFloat {
        let elementFrame = element.frame
        let containerFrame = container.frame
        guard isUsableFrame(elementFrame), isUsableFrame(containerFrame) else {
            return attempt.isMultiple(of: 2) ? 280 : -280
        }

        let distance: CGFloat
        if elementFrame.maxY > containerFrame.maxY {
            distance = elementFrame.maxY - containerFrame.maxY
        } else if elementFrame.minY < containerFrame.minY {
            distance = elementFrame.minY - containerFrame.minY
        } else {
            return attempt.isMultiple(of: 2) ? 80 : -80
        }
        let magnitude = min(max(abs(distance) + 48, 80), 520)
        return distance >= 0 ? -magnitude : magnitude
    }

    private func isElementFullyVisible(_ element: XCUIElement, in container: XCUIElement) -> Bool {
        let elementFrame = element.frame
        let containerFrame = container.frame
        guard isUsableFrame(elementFrame), isUsableFrame(containerFrame) else { return false }
        return containerFrame.contains(elementFrame)
    }

    func isUsableFrame(_ frame: CGRect) -> Bool {
        !frame.isEmpty && !frame.isNull && !frame.isInfinite
    }
}
