import CoreGraphics
import Foundation

private enum FlowTabUITestScrollingElementVisibilityPolicy {
    static let unknownGeometryDeltaMagnitude: CGFloat = 280
    static let occludedDeltaMagnitude: CGFloat = 80
    static let visibilityPadding: CGFloat = 48
    static let minimumGeometryDeltaMagnitude: CGFloat = 80
    static let maximumGeometryDeltaMagnitude: CGFloat = 520
}

enum FlowTabUITestScrollingContainerSource: Equatable {
    case preferred
    case fallback(index: Int)
    case unavailable

    var diagnosticSummary: String {
        switch self {
        case .preferred:
            return "preferred"
        case let .fallback(index):
            return "fallback[\(index)]"
        case .unavailable:
            return "unavailable"
        }
    }
}

struct FlowTabUITestScrollingContainerCandidate<Element> {
    let source: FlowTabUITestScrollingContainerSource
    let element: Element
    let frame: CGRect
}

enum FlowTabUITestScrollingContainerSelection {
    static func select<Element>(
        elementFrame: CGRect?,
        preferred:
            FlowTabUITestScrollingContainerCandidate<Element>?,
        fallbacks: [
            FlowTabUITestScrollingContainerCandidate<Element>
        ]
    ) -> FlowTabUITestScrollingContainerCandidate<Element>? {
        if let preferred {
            return preferred
        }
        guard
            let elementFrame,
            FlowTabUITestScrollingGeometry
                .isUsableFrame(elementFrame)
        else {
            return nil
        }
        return fallbacks
            .filter {
                FlowTabUITestScrollingGeometry
                    .isUsableFrame($0.frame)
            }
            .filter {
                $0.frame.minX <= elementFrame.midX
                    && $0.frame.maxX >= elementFrame.midX
            }
            .min {
                $0.frame.width * $0.frame.height
                    < $1.frame.width * $1.frame.height
            }
    }
}

private enum FlowTabUITestScrollingGeometry {
    static func isUsableFrame(
        _ frame: CGRect
    ) -> Bool {
        !frame.isEmpty
            && !frame.isNull
            && !frame.isInfinite
    }
}

struct FlowTabUITestScrollingElementVisibilitySnapshot<Element> {
    let element: Element
    let elementExists: Bool
    let elementHittable: Bool
    let elementFrame: CGRect?
    let scrollContainerSource:
        FlowTabUITestScrollingContainerSource
    let scrollContainer: Element?
    let scrollContainerFrame: CGRect?

    var resolvedElement: Element? {
        guard elementExists, elementHittable else {
            return nil
        }
        guard scrollContainer != nil else {
            return element
        }
        return isFullyVisible == true ? element : nil
    }

    var isFullyVisible: Bool? {
        guard scrollContainer != nil else { return nil }
        guard
            let elementFrame,
            FlowTabUITestScrollingGeometry
                .isUsableFrame(elementFrame),
            let scrollContainerFrame,
            FlowTabUITestScrollingGeometry
                .isUsableFrame(scrollContainerFrame)
        else {
            return false
        }
        return scrollContainerFrame.contains(elementFrame)
    }

    func nextScrollDeltaY(
        stepIndex: Int
    ) -> CGFloat? {
        guard scrollContainer != nil else { return nil }
        guard
            let elementFrame,
            FlowTabUITestScrollingGeometry
                .isUsableFrame(elementFrame),
            let scrollContainerFrame,
            FlowTabUITestScrollingGeometry
                .isUsableFrame(scrollContainerFrame)
        else {
            return Self.alternatingDeltaY(
                magnitude:
                    FlowTabUITestScrollingElementVisibilityPolicy
                        .unknownGeometryDeltaMagnitude,
                stepIndex: stepIndex
            )
        }

        let distance: CGFloat
        if elementFrame.maxY > scrollContainerFrame.maxY {
            distance =
                elementFrame.maxY
                - scrollContainerFrame.maxY
        } else if elementFrame.minY
            < scrollContainerFrame.minY
        {
            distance =
                elementFrame.minY
                - scrollContainerFrame.minY
        } else {
            return Self.alternatingDeltaY(
                magnitude:
                    FlowTabUITestScrollingElementVisibilityPolicy
                        .occludedDeltaMagnitude,
                stepIndex: stepIndex
            )
        }

        let magnitude = min(
            max(
                abs(distance)
                    + FlowTabUITestScrollingElementVisibilityPolicy
                        .visibilityPadding,
                FlowTabUITestScrollingElementVisibilityPolicy
                    .minimumGeometryDeltaMagnitude
            ),
            FlowTabUITestScrollingElementVisibilityPolicy
                .maximumGeometryDeltaMagnitude
        )
        return distance >= 0 ? -magnitude : magnitude
    }

    var diagnosticSummary: String {
        "elementExists=\(elementExists) "
            + "elementHittable=\(elementHittable) "
            + "elementFrame="
            + "\(String(describing: elementFrame)) "
            + "scrollContainerSource="
            + "\(scrollContainerSource.diagnosticSummary) "
            + "scrollContainerFrame="
            + "\(String(describing: scrollContainerFrame)) "
            + "isFullyVisible="
            + "\(String(describing: isFullyVisible))"
    }

    private static func alternatingDeltaY(
        magnitude: CGFloat,
        stepIndex: Int
    ) -> CGFloat {
        stepIndex.isMultiple(of: 2)
            ? magnitude
            : -magnitude
    }
}

private final class FlowTabUITestScrollingElementVisibilityState<
    Element
> {
    var latestSnapshot:
        FlowTabUITestScrollingElementVisibilitySnapshot<Element>?
    var scrollStepCount = 0
    var lastScrollDeltaY: CGFloat?
}

final class FlowTabUITestScrollingElementVisibilityObservationOwner<
    Element
> {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestScrollingElementVisibilitySnapshot<Element>
        >

    init(
        oneShotRegistration:
            FlowTabUITestOneShotReadbackRegistration? = nil,
        readback: @escaping () ->
            FlowTabUITestScrollingElementVisibilitySnapshot<Element>,
        scroll: @escaping (Element, CGFloat) -> Void
    ) {
        let state =
            FlowTabUITestScrollingElementVisibilityState<Element>()
        let registerOneShot =
            oneShotRegistration
            ?? FlowTabUITestConditionReadbackScheduler
                .mainRunLoopOneShotRegistration(
                    cadence:
                        FlowTabUITestConditionObservationPolicy
                            .xcuiReadbackCadence
                )
        let observationRegistration =
            FlowTabUITestConditionReadbackScheduler
                .serialRegistration(
                    oneShotRegistration: registerOneShot,
                    afterReadback: {
                        guard
                            let snapshot = state.latestSnapshot,
                            snapshot.resolvedElement == nil,
                            let container =
                                snapshot.scrollContainer,
                            let deltaY =
                                snapshot.nextScrollDeltaY(
                                    stepIndex:
                                        state.scrollStepCount
                                )
                        else {
                            return
                        }
                        state.scrollStepCount += 1
                        state.lastScrollDeltaY = deltaY
                        scroll(container, deltaY)
                    }
                )
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration:
                observationRegistration,
            readback: {
                let snapshot = readback()
                state.latestSnapshot = snapshot
                return snapshot
            },
            isSatisfied: {
                $0.resolvedElement != nil
            },
            describe: { snapshot in
                snapshot.diagnosticSummary
                    + " scrollStepCount="
                    + "\(state.scrollStepCount) "
                    + "lastScrollDeltaY="
                    + "\(String(describing: state.lastScrollDeltaY))"
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestScrollingElementVisibilitySnapshot<Element>
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestScrollingElementVisibilitySnapshot<Element>
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}
