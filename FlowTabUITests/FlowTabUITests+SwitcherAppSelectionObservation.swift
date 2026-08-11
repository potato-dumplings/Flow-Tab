import Foundation
import XCTest

struct FlowTabUITestSwitcherAppSelectionSnapshot: Equatable {
    let runtimeLog: FlowTabUITestRuntimeLogSnapshot
    let diagnostics: FlowTabUITestSwitcherDiagnosticsSnapshot

    var diagnosticSummary: String {
        "runtimeLog={\(runtimeLog.diagnosticSummary)} "
            + "diagnostics={\(diagnostics.diagnosticSummary)}"
    }
}

struct FlowTabUITestSwitcherAppSelectionExpectation:
    Equatable
{
    let bundleIdentifier: String

    var appliedLogSuffix: String {
        "select app command applied appID="
            + bundleIdentifier
    }

    func isSatisfied(
        by snapshot:
            FlowTabUITestSwitcherAppSelectionSnapshot
    ) -> Bool {
        hasAppliedLogMarker(in: snapshot.runtimeLog)
            && selectedAppExpectation.isSatisfied(
                by: snapshot.diagnostics
            )
    }

    func diagnosticSummary(
        for snapshot:
            FlowTabUITestSwitcherAppSelectionSnapshot
    ) -> String {
        "appliedMarkerPresent="
            + "\(hasAppliedLogMarker(in: snapshot.runtimeLog)) "
            + "expectedAppliedSuffix=\(appliedLogSuffix) "
            + snapshot.diagnosticSummary
    }

    private var selectedAppExpectation:
        FlowTabUITestSwitcherDiagnosticsExpectation
    {
        FlowTabUITestSwitcherDiagnosticsExpectation(
            key: "selected",
            expectedValue: bundleIdentifier
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

final class FlowTabUITestSwitcherAppSelectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSwitcherAppSelectionSnapshot
        >

    init(
        bundleIdentifier: String,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestSwitcherAppSelectionSnapshot
    ) {
        let expectation =
            FlowTabUITestSwitcherAppSelectionExpectation(
                bundleIdentifier: bundleIdentifier
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
        FlowTabUITestSwitcherAppSelectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSwitcherAppSelectionSnapshot
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
    func performAndWaitForSwitcherAppSelection(
        in app: XCUIApplication,
        bundleIdentifier: String,
        timeout: TimeInterval,
        trigger: () throws -> Void
    ) rethrows -> Bool {
        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        let logBaseline = makeRuntimeLogFileSnapshot()
        let owner =
            FlowTabUITestSwitcherAppSelectionObservationOwner(
                bundleIdentifier: bundleIdentifier,
                observationRegistration:
                    logBaseline.observationRegistration(),
                readback: {
                    FlowTabUITestSwitcherAppSelectionSnapshot(
                        runtimeLog:
                            logBaseline.makeReadback(),
                        diagnostics:
                            self.switcherDiagnosticsSnapshot(
                                diagnosticsSummary,
                                keys: ["selected"]
                            )
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        try trigger()

        guard owner.waitForResolution(timeout: timeout) != nil else {
            XCTFail(
                "Switcher app-selection evidence watchdog expired. "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }
}
