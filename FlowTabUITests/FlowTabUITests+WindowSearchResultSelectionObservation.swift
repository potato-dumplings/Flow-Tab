import Foundation
import XCTest

struct FlowTabUITestWindowSearchResultSelectionSnapshot: Equatable {
    let runtimeLog: FlowTabUITestRuntimeLogSnapshot
    let diagnostics: FlowTabUITestSwitcherDiagnosticsSnapshot

    var diagnosticSummary: String {
        "runtimeLog={\(runtimeLog.diagnosticSummary)} "
            + "diagnostics={\(diagnostics.diagnosticSummary)}"
    }
}

struct FlowTabUITestWindowSearchResultSelectionExpectation:
    Equatable
{
    let resultID: String

    var appliedLogSuffix: String {
        "select search result command applied resultID="
            + resultID
    }

    func isSatisfied(
        by snapshot:
            FlowTabUITestWindowSearchResultSelectionSnapshot
    ) -> Bool {
        hasAppliedLogMarker(in: snapshot.runtimeLog)
            && selectedResultExpectation.isSatisfied(
                by: snapshot.diagnostics
            )
    }

    func diagnosticSummary(
        for snapshot:
            FlowTabUITestWindowSearchResultSelectionSnapshot
    ) -> String {
        "appliedMarkerPresent="
            + "\(hasAppliedLogMarker(in: snapshot.runtimeLog)) "
            + "expectedAppliedSuffix=\(appliedLogSuffix) "
            + snapshot.diagnosticSummary
    }

    private var selectedResultExpectation:
        FlowTabUITestSwitcherDiagnosticsExpectation
    {
        FlowTabUITestSwitcherDiagnosticsExpectation(
            key: "searchSelectedResult",
            expectedValue: resultID,
            decodesPercentEncoding: true
        )
    }

    private func hasAppliedLogMarker(
        in snapshot: FlowTabUITestRuntimeLogSnapshot
    ) -> Bool {
        snapshot.contents
            .split(whereSeparator: \.isNewline)
            .contains {
                $0.hasSuffix(appliedLogSuffix)
            }
    }
}

final class FlowTabUITestWindowSearchResultSelectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestWindowSearchResultSelectionSnapshot
        >

    init(
        resultID: String,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestWindowSearchResultSelectionSnapshot
    ) {
        let expectation =
            FlowTabUITestWindowSearchResultSelectionExpectation(
                resultID: resultID
            )
        conditionOwner =
            FlowTabUITestConditionObservationOwner(
                observationRegistration:
                    observationRegistration,
                readback: readback,
                isSatisfied: expectation.isSatisfied(by:),
                describe: expectation.diagnosticSummary(for:)
            )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestWindowSearchResultSelectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestWindowSearchResultSelectionSnapshot
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

extension FlowTabUITests {
    func performAndWaitForWindowSearchResultSelection(
        in app: XCUIApplication,
        resultID: String,
        timeout: TimeInterval,
        trigger: () throws -> Void
    ) rethrows -> Bool {
        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        let logBaseline = makeRuntimeLogFileSnapshot()
        let owner =
            FlowTabUITestWindowSearchResultSelectionObservationOwner(
                resultID: resultID,
                observationRegistration:
                    logBaseline.observationRegistration(),
                readback: {
                    FlowTabUITestWindowSearchResultSelectionSnapshot(
                        runtimeLog:
                            logBaseline.makeReadback(),
                        diagnostics:
                            self.switcherDiagnosticsSnapshot(
                                diagnosticsSummary,
                                keys: [
                                    "searchSelectedResult"
                                ]
                            )
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        try trigger()

        guard
            owner.waitForResolution(timeout: timeout) != nil
        else {
            XCTFail(
                "Window Search result-selection evidence "
                    + "watchdog expired. "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }
}
