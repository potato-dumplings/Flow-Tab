import CoreGraphics
import Foundation
import XCTest

extension FlowTabUITests {
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
