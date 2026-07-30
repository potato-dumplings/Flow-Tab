import Foundation
import XCTest

private enum FlowTabUITestSwitcherWindowSelectionTransitionPolicy {
    static let watchdog: TimeInterval = 4
}

struct FlowTabUITestSwitcherWindowSelectionTransitionSnapshot:
    Equatable
{
    let diagnostics: FlowTabUITestSwitcherDiagnosticsSnapshot

    var modeValue: String? {
        nonemptyValue(for: "mode")
    }

    var selectedWindowID: String? {
        guard
            let value = nonemptyValue(for: "selectedWindow"),
            value != "none"
        else {
            return nil
        }
        return value
    }

    var selectedWindowTitle: String? {
        nonemptyValue(for: "selectedWindowTitle")
    }

    var selectedWindowOwnerPID: UInt32? {
        selectedCGWindowIdentity?.ownerPID
    }

    var selectedWindowNumber: UInt32? {
        selectedCGWindowIdentity?.windowNumber
    }

    var hasCompleteWindowCycleSelection: Bool {
        diagnostics.exists
            && modeValue?.hasPrefix("windowCycle") == true
            && selectedWindowID != nil
            && selectedWindowTitle != nil
            && selectedWindowNumber != nil
    }

    var diagnosticSummary: String {
        "mode=\(modeValue ?? "nil") "
            + "selectedWindowID=\(selectedWindowID ?? "nil") "
            + "selectedWindowTitle="
            + "\(selectedWindowTitle ?? "nil") "
            + "selectedWindowOwnerPID="
            + "\(selectedWindowOwnerPID.map(String.init) ?? "nil") "
            + "selectedWindowNumber="
            + "\(selectedWindowNumber.map(String.init) ?? "nil") "
            + "complete=\(hasCompleteWindowCycleSelection) "
            + "diagnostics{\(diagnostics.diagnosticSummary)}"
    }

    private func nonemptyValue(for key: String) -> String? {
        guard
            let value = diagnostics.values[key],
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private var selectedCGWindowIdentity: (
        ownerPID: UInt32,
        windowNumber: UInt32
    )? {
        guard let selectedWindowID else {
            return nil
        }
        let components = selectedWindowID.split(
            separator: ":",
            omittingEmptySubsequences: false
        )
        guard
            components.count == 3,
            components[0] == "cg",
            let ownerPID = UInt32(components[1]),
            ownerPID > 0,
            let windowNumber = UInt32(components[2]),
            windowNumber > 0
        else {
            return nil
        }
        return (ownerPID, windowNumber)
    }
}

final class
    FlowTabUITestSwitcherWindowSelectionTransitionObservationOwner
{
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSwitcherWindowSelectionTransitionSnapshot
        >

    init(
        baselineWindowNumber: UInt32,
        acceptsEvidence: @escaping () -> Bool = {
            true
        },
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestSwitcherWindowSelectionTransitionSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: { snapshot in
                acceptsEvidence()
                    && snapshot.hasCompleteWindowCycleSelection
                    && snapshot.selectedWindowNumber
                        != baselineWindowNumber
            },
            describe: { snapshot in
                "acceptanceEnabled=\(acceptsEvidence()) "
                    + "baselineWindowNumber="
                    + "\(baselineWindowNumber) "
                    + snapshot.diagnosticSummary
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func requestReadback(
        source: FlowTabUITestConditionObservationSource
    ) {
        conditionOwner.requestReadback(source: source)
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestSwitcherWindowSelectionTransitionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSwitcherWindowSelectionTransitionSnapshot
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
    func performAndWaitForSwitcherWindowSelectionTransition(
        from baselineSelection: RuntimeTruthWindowSelection,
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        traceLabel: String,
        trigger: () -> Void
    ) throws -> RuntimeTruthWindowSelection {
        var triggerCompleted = false
        let owner =
            FlowTabUITestSwitcherWindowSelectionTransitionObservationOwner(
                baselineWindowNumber:
                    baselineSelection.windowNumber,
                acceptsEvidence: {
                    triggerCompleted
                },
                readback: {
                    FlowTabUITestSwitcherWindowSelectionTransitionSnapshot(
                        diagnostics:
                            self.switcherDiagnosticsSnapshot(
                                diagnosticsSummary,
                                keys: [
                                    "mode",
                                    "selectedWindow",
                                    "selectedWindowTitle",
                                ]
                            )
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        trigger()
        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)

        let evidence = try XCTUnwrap(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherWindowSelectionTransitionPolicy
                        .watchdog
            ),
            """
            Switcher window-selection transition watchdog expired for \
            \(traceLabel). \(owner.diagnosticSummary)

            \(switcherDebugSummary(
                app,
                diagnosticsSummary: diagnosticsSummary
            ))
            """
        )
        let selectedWindowID = try XCTUnwrap(
            evidence.value.selectedWindowID,
            "Resolved selection evidence did not expose a window ID."
        )
        let selectedWindowTitle = try XCTUnwrap(
            evidence.value.selectedWindowTitle,
            "Resolved selection evidence did not expose a window title."
        )
        logFlowTabUITestTrace(
            "[\(traceLabel)] resolved "
                + "generation=\(evidence.generation) "
                + "source=\(evidence.source.rawValue) "
                + "selected=\(selectedWindowTitle) "
                + "windowID=\(selectedWindowID)"
        )
        return try runtimeTruthWindowSelection(
            title: selectedWindowTitle,
            windowID: selectedWindowID
        )
    }
}
