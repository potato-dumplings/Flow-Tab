import CoreGraphics
import Foundation
import XCTest

private enum FlowTabUITestScrollingHittableElementPolicy {
    static let unknownGeometryDeltaY: CGFloat = -420
    static let offscreenDeltaMagnitude: CGFloat = 420
    static let occludedDeltaMagnitude: CGFloat = 240
}

struct FlowTabUITestScrollingHittableElementSnapshot<Element> {
    let candidateCount: Int
    let observedExistingIndices: [Int]
    let firstExistingIndex: Int?
    let firstExistingFrame: CGRect?
    let firstHittableIndex: Int?
    let firstHittableElement: Element?
    let scrollContainerExists: Bool
    let scrollContainerFrame: CGRect?

    var nextScrollDeltaY: CGFloat? {
        guard scrollContainerExists else { return nil }
        guard let firstExistingFrame else {
            return FlowTabUITestScrollingHittableElementPolicy
                .unknownGeometryDeltaY
        }
        guard
            Self.isUsableFrame(firstExistingFrame),
            let scrollContainerFrame,
            Self.isUsableFrame(scrollContainerFrame)
        else {
            return FlowTabUITestScrollingHittableElementPolicy
                .unknownGeometryDeltaY
        }
        if firstExistingFrame.maxY
            > scrollContainerFrame.maxY
        {
            return -FlowTabUITestScrollingHittableElementPolicy
                .offscreenDeltaMagnitude
        }
        if firstExistingFrame.minY
            < scrollContainerFrame.minY
        {
            return FlowTabUITestScrollingHittableElementPolicy
                .offscreenDeltaMagnitude
        }
        return
            firstExistingFrame.midY
                >= scrollContainerFrame.midY
            ? -FlowTabUITestScrollingHittableElementPolicy
                .occludedDeltaMagnitude
            : FlowTabUITestScrollingHittableElementPolicy
                .occludedDeltaMagnitude
    }

    var diagnosticSummary: String {
        "candidateCount=\(candidateCount) "
            + "observedExistingIndices="
            + "\(observedExistingIndices) "
            + "firstExistingIndex="
            + "\(firstExistingIndex.map(String.init) ?? "nil") "
            + "firstExistingFrame="
            + "\(String(describing: firstExistingFrame)) "
            + "firstHittableIndex="
            + "\(firstHittableIndex.map(String.init) ?? "nil") "
            + "scrollContainerExists="
            + "\(scrollContainerExists) "
            + "scrollContainerFrame="
            + "\(String(describing: scrollContainerFrame))"
    }

    private static func isUsableFrame(
        _ frame: CGRect
    ) -> Bool {
        !frame.isEmpty
            && !frame.isNull
            && !frame.isInfinite
    }
}

private final class FlowTabUITestScrollingHittableElementObservationState<
    Element
> {
    var latestSnapshot:
        FlowTabUITestScrollingHittableElementSnapshot<Element>?
    var scrollStepCount = 0
    var lastScrollDeltaY: CGFloat?
}

final class FlowTabUITestScrollingHittableElementObservationOwner<
    Element
> {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestScrollingHittableElementSnapshot<Element>
        >

    init(
        oneShotRegistration:
            FlowTabUITestOneShotReadbackRegistration? = nil,
        readback: @escaping () ->
            FlowTabUITestScrollingHittableElementSnapshot<Element>,
        scroll: @escaping (CGFloat) -> Void
    ) {
        let state =
            FlowTabUITestScrollingHittableElementObservationState<
                Element
            >()
        let registerOneShot =
            oneShotRegistration
            ?? FlowTabUITestConditionReadbackScheduler
                .mainRunLoopOneShotRegistration(
                    cadence:
                        FlowTabUITestConditionObservationPolicy
                            .xcuiReadbackCadence
                )
        let observationRegistration:
            FlowTabUITestConditionObservationRegistration =
                FlowTabUITestConditionReadbackScheduler
                    .serialRegistration(
                        oneShotRegistration: registerOneShot,
                        afterReadback: {
                            if
                                let snapshot =
                                    state.latestSnapshot,
                                snapshot.firstHittableElement
                                    == nil,
                                let deltaY =
                                    snapshot.nextScrollDeltaY
                            {
                                state.scrollStepCount += 1
                                state.lastScrollDeltaY = deltaY
                                scroll(deltaY)
                            }
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
                $0.firstHittableElement != nil
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
        FlowTabUITestScrollingHittableElementSnapshot<Element>
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestScrollingHittableElementSnapshot<Element>
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
