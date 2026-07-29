import Foundation

struct SpaceFixtureWorkflowReadinessExpectation:
    Equatable
{
    let identity: SpaceFixtureWorkflowReadinessIdentity
    let windowPlanIndices: [Int]
    let fullscreenWindowPlanIndices: [Int]
    let desktopAnchorWindowPlanIndex: Int?
    let requiresApplicationAXSuppression: Bool
    let windowTitles: [String]

    init(
        identity: SpaceFixtureWorkflowReadinessIdentity,
        windowPlanIndices: [Int],
        fullscreenWindowPlanIndices: [Int],
        desktopAnchorWindowPlanIndex: Int?,
        requiresApplicationAXSuppression: Bool,
        windowTitles: [String]
    ) {
        precondition(!identity.bundleIdentifier.isEmpty)
        precondition(identity.processIdentifier > 0)
        precondition(!windowPlanIndices.isEmpty)
        precondition(
            windowPlanIndices
                == Array(Set(windowPlanIndices)).sorted()
        )
        precondition(
            fullscreenWindowPlanIndices
                == Array(
                    Set(fullscreenWindowPlanIndices)
                ).sorted()
        )
        precondition(
            fullscreenWindowPlanIndices.allSatisfy(
                windowPlanIndices.contains
            )
        )
        precondition(
            desktopAnchorWindowPlanIndex.map(
                windowPlanIndices.contains
            ) ?? true
        )
        precondition(
            windowTitles.count
                == windowPlanIndices.count
        )
        self.identity = identity
        self.windowPlanIndices = windowPlanIndices
        self.fullscreenWindowPlanIndices =
            fullscreenWindowPlanIndices
        self.desktopAnchorWindowPlanIndex =
            desktopAnchorWindowPlanIndex
        self.requiresApplicationAXSuppression =
            requiresApplicationAXSuppression
        self.windowTitles = windowTitles
    }
}

@MainActor
final class SpaceFixtureWorkflowReadinessOwner {
    typealias EvidencePublisher =
        @MainActor (
            SpaceFixtureWorkflowReadinessEvidence
        ) -> Void
    typealias ReadyHandler =
        @MainActor (
            SpaceFixtureWorkflowReadinessEvidence
        ) -> Void

    private struct ActiveObservation {
        let observationGeneration: Int
        let expectation:
            SpaceFixtureWorkflowReadinessExpectation
        let onReady: ReadyHandler
        var observedWindowPlanIndices: [Int] = []
        var completedFullscreenWindowPlanIndices:
            [Int] = []
        var desktopPresentationResolved = false
        var applicationAXExposureResolved = false
    }

    private let evidencePublisher: EvidencePublisher
    private var active: ActiveObservation?

    private(set) var observationGeneration = 0
    private(set) var transitionGeneration: UInt64 = 0
    private(set) var lastEvidence:
        SpaceFixtureWorkflowReadinessEvidence?

    init(
        evidencePublisher:
            @escaping EvidencePublisher
    ) {
        self.evidencePublisher = evidencePublisher
    }

    var isObserving: Bool {
        active != nil
    }

    @discardableResult
    func start(
        expectation:
            SpaceFixtureWorkflowReadinessExpectation,
        onReady: @escaping ReadyHandler
    ) -> Int {
        cancel(invalidate: false)
        observationGeneration += 1
        lastEvidence = nil
        let generation = observationGeneration
        active = ActiveObservation(
            observationGeneration: generation,
            expectation: expectation,
            onReady: onReady,
            desktopPresentationResolved:
                expectation
                    .desktopAnchorWindowPlanIndex == nil,
            applicationAXExposureResolved:
                !expectation
                    .requiresApplicationAXSuppression
        )
        publish(
            stage: .configured,
            observationGeneration: generation
        )
        return generation
    }

    func windowTopologyDidResolve(
        planIndices: [Int],
        observationGeneration: Int
    ) {
        guard var current = matchingActive(
            observationGeneration
        ) else {
            return
        }
        let normalized = Array(Set(planIndices)).sorted()
        if Set(planIndices).count == planIndices.count,
           normalized
            == current.expectation.windowPlanIndices
        {
            current.observedWindowPlanIndices =
                normalized
            active = current
        }
        publishAndFinishIfReady(
            stage: .windowTopology,
            observationGeneration: observationGeneration
        )
    }

    func fullscreenTopologyDidResolve(
        _ completion:
            SpaceFixtureFullscreenTransitionCompletion,
        observationGeneration: Int
    ) {
        guard var current = matchingActive(
            observationGeneration
        ) else {
            return
        }
        let normalized = Array(
            Set(completion.windowPlanIndices)
        ).sorted()
        if Set(completion.windowPlanIndices).count
                == completion.windowPlanIndices.count,
           current.observedWindowPlanIndices
                == current.expectation
                    .windowPlanIndices,
           normalized
                == current.expectation
                    .fullscreenWindowPlanIndices
        {
            current.completedFullscreenWindowPlanIndices =
                normalized
            active = current
        }
        publishAndFinishIfReady(
            stage: .fullscreenTopology,
            observationGeneration: observationGeneration
        )
    }

    func desktopPresentationDidResolve(
        _ evidence: SpaceFixtureDesktopPresentationEvidence,
        observationGeneration: Int
    ) {
        guard var current = matchingActive(
            observationGeneration
        ) else {
            return
        }
        if current.observedWindowPlanIndices
                == current.expectation
                    .windowPlanIndices,
           current.completedFullscreenWindowPlanIndices
                == current.expectation
                    .fullscreenWindowPlanIndices,
           evidence.snapshot.windowPlanIndex
                == current.expectation
                    .desktopAnchorWindowPlanIndex,
           evidence.snapshot.isPresented
        {
            current.desktopPresentationResolved = true
            active = current
        }
        publishAndFinishIfReady(
            stage: .desktopPresentation,
            observationGeneration: observationGeneration
        )
    }

    func applicationAXExposureDidResolve(
        _ exposure: SpaceFixtureApplicationAXExposure,
        observationGeneration: Int
    ) {
        guard var current = matchingActive(
            observationGeneration
        ) else {
            return
        }
        if current.observedWindowPlanIndices
                == current.expectation
                    .windowPlanIndices,
           current.completedFullscreenWindowPlanIndices
                == current.expectation
                    .fullscreenWindowPlanIndices,
           current.desktopPresentationResolved,
           current.expectation
                .requiresApplicationAXSuppression,
           exposure.isSuppressed
        {
            current.applicationAXExposureResolved =
                true
            active = current
        }
        publishAndFinishIfReady(
            stage: .applicationAXExposure,
            observationGeneration: observationGeneration
        )
    }

    func cancel(invalidate: Bool = true) {
        let hadActiveObservation = active != nil
        active = nil
        if invalidate && hadActiveObservation {
            observationGeneration += 1
        }
    }

    private func publishAndFinishIfReady(
        stage: SpaceFixtureWorkflowReadinessStage,
        observationGeneration: Int
    ) {
        guard matchingActive(
            observationGeneration
        ) != nil else {
            return
        }
        publish(
            stage: stage,
            observationGeneration: observationGeneration
        )
        guard currentSnapshot(
            for: observationGeneration
        )?.isReady == true,
        let completed = matchingActive(
            observationGeneration
        )
        else {
            return
        }
        let readyEvidence = makeEvidence(
            stage: .ready,
            current: completed
        )
        lastEvidence = readyEvidence
        active = nil
        evidencePublisher(readyEvidence)
        completed.onReady(readyEvidence)
    }

    private func publish(
        stage: SpaceFixtureWorkflowReadinessStage,
        observationGeneration: Int
    ) {
        guard let current = matchingActive(
            observationGeneration
        ) else {
            return
        }
        let evidence = makeEvidence(
            stage: stage,
            current: current
        )
        lastEvidence = evidence
        evidencePublisher(evidence)
    }

    private func makeEvidence(
        stage: SpaceFixtureWorkflowReadinessStage,
        current: ActiveObservation
    ) -> SpaceFixtureWorkflowReadinessEvidence {
        transitionGeneration &+= 1
        return SpaceFixtureWorkflowReadinessEvidence(
            observationGeneration:
                current.observationGeneration,
            transitionGeneration: transitionGeneration,
            stage: stage,
            identity:
                current.expectation.identity,
            snapshot: snapshot(for: current)
        )
    }

    private func currentSnapshot(
        for observationGeneration: Int
    ) -> SpaceFixtureWorkflowReadinessSnapshot? {
        matchingActive(observationGeneration)
            .map(snapshot(for:))
    }

    private func snapshot(
        for current: ActiveObservation
    ) -> SpaceFixtureWorkflowReadinessSnapshot {
        SpaceFixtureWorkflowReadinessSnapshot(
            expectedWindowPlanIndices:
                current.expectation.windowPlanIndices,
            observedWindowPlanIndices:
                current.observedWindowPlanIndices,
            expectedFullscreenWindowPlanIndices:
                current.expectation
                    .fullscreenWindowPlanIndices,
            completedFullscreenWindowPlanIndices:
                current
                    .completedFullscreenWindowPlanIndices,
            desktopAnchorWindowPlanIndex:
                current.expectation
                    .desktopAnchorWindowPlanIndex,
            desktopPresentationResolved:
                current.desktopPresentationResolved,
            applicationAXSuppressionRequired:
                current.expectation
                    .requiresApplicationAXSuppression,
            applicationAXExposureResolved:
                current.applicationAXExposureResolved,
            windowTitles:
                current.expectation.windowTitles
        )
    }

    private func matchingActive(
        _ observationGeneration: Int
    ) -> ActiveObservation? {
        guard let active,
              active.observationGeneration
                == observationGeneration
        else {
            return nil
        }
        return active
    }
}
