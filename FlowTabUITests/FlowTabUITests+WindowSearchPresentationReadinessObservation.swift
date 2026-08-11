import Foundation
import XCTest

private final class FlowTabUITestWindowSearchPresentationReadinessState {
    var acceptsCommittedProjection = false
}

final class FlowTabUITestWindowSearchPresentationReadinessObservationOwner {
    let searchInputReadiness:
        FlowTabUITestSearchInputReadinessObservationOwner
    private let state:
        FlowTabUITestWindowSearchPresentationReadinessState
    private let diagnosticsReadiness:
        FlowTabUITestElementExistenceObservationOwner
    private let committedProjectionReadiness:
        FlowTabUITestWindowSearchProjectionObservationOwner
    private let committedProjectionReadbacks:
        FlowTabUITestDeferredConditionReadbackRegistration

    init(
        searchInputReadiness:
            FlowTabUITestSearchInputReadinessObservationOwner,
        diagnosticsIdentifier: String,
        diagnosticsReadback: @escaping () -> Bool,
        committedProjectionRequirement:
            FlowTabUITestWindowSearchProjectionRequirement,
        committedProjectionReadback: @escaping () ->
            FlowTabUITestWindowSearchProjectionSnapshot
    ) {
        let state =
            FlowTabUITestWindowSearchPresentationReadinessState()
        let committedProjectionReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration:
                    FlowTabUITestConditionReadbackScheduler
                        .mainRunLoopRegistration(
                            cadence:
                                FlowTabUITestConditionObservationPolicy
                                    .xcuiReadbackCadence
                        )
            )
        self.state = state
        self.committedProjectionReadbacks =
            committedProjectionReadbacks
        self.searchInputReadiness = searchInputReadiness
        diagnosticsReadiness =
            FlowTabUITestElementExistenceObservationOwner(
                elementIdentifier: diagnosticsIdentifier,
                readback: diagnosticsReadback
            )
        committedProjectionReadiness =
            FlowTabUITestWindowSearchProjectionObservationOwner(
                requirement: committedProjectionRequirement,
                acceptsEvidence: {
                    state.acceptsCommittedProjection
                },
                observationRegistration: { callback in
                    committedProjectionReadbacks.register(
                        callback
                    )
                },
                readback: committedProjectionReadback
            )
    }

    func start() {
        state.acceptsCommittedProjection = false
        searchInputReadiness.start()
        diagnosticsReadiness.start()
        committedProjectionReadiness.start()
    }

    func markSearchInputReady() {
        state.acceptsCommittedProjection = true
        diagnosticsReadiness.markTriggerCompleted()
        committedProjectionReadiness.requestReadback(
            source: .triggerReadback
        )
        if committedProjectionReadiness.resolvedEvidence == nil {
            committedProjectionReadbacks.activate()
        }
    }

    func waitForDiagnostics(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestElementExistenceSnapshot
    >? {
        diagnosticsReadiness.waitForResolution(timeout: timeout)
    }

    func waitForCommittedProjection(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestWindowSearchProjectionSnapshot
    >? {
        committedProjectionReadiness.waitForResolution(
            timeout: timeout
        )
    }

    var diagnosticSummary: String {
        "searchInput={\(searchInputReadiness.diagnosticSummary)} "
            + "diagnostics={\(diagnosticsReadiness.diagnosticSummary)} "
            + "committedProjection={"
            + committedProjectionReadiness.diagnosticSummary
            + "}"
    }

    func cancel() {
        committedProjectionReadiness.cancel()
        committedProjectionReadbacks.cancel()
        diagnosticsReadiness.cancel()
        searchInputReadiness.cancel()
    }
}

extension FlowTabUITests {
    func prepareWindowSearchPresentationReadiness(
        in app: XCUIApplication,
        workflowApp: SpaceFixtureResolvedWorkflow.App,
        allowsNoisyCGSiblings: Bool
    ) -> FlowTabUITestWindowSearchPresentationReadinessObservationOwner {
        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        let owner =
            FlowTabUITestWindowSearchPresentationReadinessObservationOwner(
                searchInputReadiness:
                    FlowTabUITestSearchInputReadinessObservationOwner(
                        baseline: makeRuntimeLogFileSnapshot()
                    ),
                diagnosticsIdentifier: Identifier.switcherSummary,
                diagnosticsReadback: { diagnosticsSummary.exists },
                committedProjectionRequirement:
                    FlowTabUITestWindowSearchProjectionRequirement(
                        appID:
                            workflowApp.identity.bundleIdentifier,
                        expectedTitles:
                            Set(workflowApp.expectedWindowTitles),
                        expectedCount:
                            allowsNoisyCGSiblings
                                ? nil
                                : workflowApp.windowCount
                    ),
                committedProjectionReadback: {
                    self.windowSearchProjectionSnapshot(
                        diagnosticsSummary
                    )
                }
            )
        owner.start()
        addTeardownBlock {
            owner.cancel()
        }
        return owner
    }

    func requireWindowSearchPresentation(
        in app: XCUIApplication,
        observedBy owner:
            FlowTabUITestWindowSearchPresentationReadinessObservationOwner
    ) -> XCUIElement {
        defer { owner.cancel() }
        let searchInput = requireInitialFlowTabSearchInput(
            in: app,
            observedBy: owner.searchInputReadiness
        )
        owner.markSearchInputReady()

        guard
            owner.waitForDiagnostics(
                timeout:
                    FlowTabUITestRuntimeTruthWatchdogPolicy
                        .windowSearchDiagnosticsPublication
            ) != nil
        else {
            XCTFail(
                "Window Search diagnostics publication watchdog expired. "
                    + owner.diagnosticSummary
            )
            return searchInput
        }

        guard
            owner.waitForCommittedProjection(
                timeout:
                    FlowTabUITestRuntimeTruthWatchdogPolicy
                        .windowSearchCommittedProjectionPublication
            ) != nil
        else {
            XCTFail(
                "Window Search committed projection watchdog expired. "
                    + owner.diagnosticSummary
            )
            return searchInput
        }
        return searchInput
    }
}
