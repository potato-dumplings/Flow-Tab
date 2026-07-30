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

private final class FlowTabUITestScrollingHittableElementReadbackSchedule {
    private let oneShotRegistration:
        FlowTabUITestOneShotReadbackRegistration
    private let readback:
        (FlowTabUITestConditionObservationSource) -> Void
    private let scrollIfNeeded: () -> Void

    private var scheduledCancellation:
        FlowTabUITestObservationCancellation?
    private var isCancelled = false

    init(
        oneShotRegistration:
            @escaping FlowTabUITestOneShotReadbackRegistration,
        readback: @escaping (
            FlowTabUITestConditionObservationSource
        ) -> Void,
        scrollIfNeeded: @escaping () -> Void
    ) {
        self.oneShotRegistration = oneShotRegistration
        self.readback = readback
        self.scrollIfNeeded = scrollIfNeeded
    }

    func start() {
        scheduleNextReadback()
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        scheduledCancellation?.cancel()
        scheduledCancellation = nil
    }

    deinit {
        cancel()
    }

    private func scheduleNextReadback() {
        guard !isCancelled,
              scheduledCancellation == nil
        else {
            return
        }
        scheduledCancellation = oneShotRegistration {
            [weak self] in
            self?.fire()
        }
    }

    private func fire() {
        guard !isCancelled else { return }
        scheduledCancellation = nil
        readback(.scheduledReadback)
        guard !isCancelled else { return }
        scrollIfNeeded()
        guard !isCancelled else { return }
        // XCUI scrolling pumps the RunLoop. Registering after it returns
        // prevents a subsequent scroll step from reentering this one.
        scheduleNextReadback()
    }
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
            ?? Self.mainRunLoopOneShotRegistration
        let observationRegistration:
            FlowTabUITestConditionObservationRegistration = {
                scheduledReadback in
                let schedule =
                    FlowTabUITestScrollingHittableElementReadbackSchedule(
                        oneShotRegistration: registerOneShot,
                        readback: scheduledReadback,
                        scrollIfNeeded: {
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
                schedule.start()
                return FlowTabUITestObservationCancellation {
                    schedule.cancel()
                }
            }
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

    private static func mainRunLoopOneShotRegistration(
        _ readback: @escaping () -> Void
    ) -> FlowTabUITestObservationCancellation {
        let timer = Timer(
            timeInterval:
                FlowTabUITestConditionObservationPolicy
                    .xcuiReadbackCadence,
            repeats: false
        ) { _ in
            readback()
        }
        RunLoop.main.add(timer, forMode: .common)
        return FlowTabUITestObservationCancellation {
            timer.invalidate()
        }
    }
}
