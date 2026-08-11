import Foundation
import XCTest

final class FlowTabUITestWindowSearchPresentationReadinessObservationOwner {
    let searchInputReadiness:
        FlowTabUITestSearchInputReadinessObservationOwner
    private let diagnosticsReadiness:
        FlowTabUITestElementExistenceObservationOwner

    init(
        searchInputReadiness:
            FlowTabUITestSearchInputReadinessObservationOwner,
        diagnosticsIdentifier: String,
        diagnosticsReadback: @escaping () -> Bool
    ) {
        self.searchInputReadiness = searchInputReadiness
        diagnosticsReadiness =
            FlowTabUITestElementExistenceObservationOwner(
                elementIdentifier: diagnosticsIdentifier,
                readback: diagnosticsReadback
            )
    }

    func start() {
        searchInputReadiness.start()
        diagnosticsReadiness.start()
    }

    func markSearchInputReady() {
        diagnosticsReadiness.markTriggerCompleted()
    }

    func waitForDiagnostics(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestElementExistenceSnapshot
    >? {
        diagnosticsReadiness.waitForResolution(timeout: timeout)
    }

    var diagnosticSummary: String {
        "searchInput={\(searchInputReadiness.diagnosticSummary)} "
            + "diagnostics={\(diagnosticsReadiness.diagnosticSummary)}"
    }

    func cancel() {
        diagnosticsReadiness.cancel()
        searchInputReadiness.cancel()
    }
}

extension FlowTabUITests {
    func prepareWindowSearchPresentationReadiness(
        in app: XCUIApplication
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
                diagnosticsReadback: { diagnosticsSummary.exists }
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
        return searchInput
    }
}
