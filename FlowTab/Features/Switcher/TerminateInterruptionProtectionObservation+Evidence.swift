import Foundation

extension TerminateInterruptionProtectionObservationOwner {
    func makeEvidence(
        source: TerminateInterruptionProtectionEvidenceSource,
        active: ActiveObservation
    ) -> TerminateInterruptionProtectionEvidence {
        TerminateInterruptionProtectionEvidence(
            source: source,
            observationGeneration: active.generation,
            presentationGeneration: active.presentationGeneration,
            target: active.target,
            baseline: active.baseline,
            matchingTerminationObserved:
                active.matchingTerminationObserved,
            protectedSystemInterruptionObserved:
                active.protectedSystemInterruptionObserved,
            snapshot: active.readback()
        )
    }

    func terminationConditionSatisfied(
        _ evidence: TerminateInterruptionProtectionEvidence
    ) -> Bool {
        guard evidence.snapshot.projectionState.confirmsTargetRemoval else {
            return false
        }
        let projectionAdvanced =
            evidence.snapshot.projectionGeneration
                > evidence.baseline.projectionGeneration
        let projectionRemovalObserved =
            projectionAdvanced
                || evidence.baseline.projectionContainsAppID == true
        return evidence.matchingTerminationObserved
            || (
                evidence.snapshot.processState == .terminated
                    && projectionRemovalObserved
            )
    }

    func presentationConditionSatisfied(
        _ evidence: TerminateInterruptionProtectionEvidence
    ) -> Bool {
        let presentationEvidence =
            evidence.source == .activeSpaceTransitionReadback
                || evidence.source == .panelVisibilityReadback
        let presentationStable =
            !evidence.snapshot.activeSpaceTransitionPending
                && evidence.snapshot.panelVisibility.userVisible
                && evidence.snapshot.panelVisibility.appActive
        let protectedInterruptionConsumed =
            evidence.protectedSystemInterruptionObserved
        return presentationStable
            && (presentationEvidence || protectedInterruptionConsumed)
    }
}
