import Foundation
import XCTest

struct FlowTabUITestSwitcherSelectionState: Equatable {
    static let diagnosticsKeys = ["selected", "mode"]

    let selectedBundleIdentifier: String
    let mode: String

    init(
        selectedBundleIdentifier: String,
        mode: String
    ) {
        self.selectedBundleIdentifier =
            selectedBundleIdentifier
        self.mode = mode
    }

    init?(
        snapshot: FlowTabUITestSwitcherDiagnosticsSnapshot
    ) {
        guard
            snapshot.exists,
            let selectedBundleIdentifier =
                snapshot.values["selected"],
            !selectedBundleIdentifier.isEmpty,
            let mode = snapshot.values["mode"],
            !mode.isEmpty
        else {
            return nil
        }
        self.selectedBundleIdentifier =
            selectedBundleIdentifier
        self.mode = mode
    }

    var hasSupportedMode: Bool {
        mode == "appCycle"
            || mode.hasPrefix("windowCycle(")
    }

    var diagnosticSummary: String {
        "selected=\(selectedBundleIdentifier) mode=\(mode)"
    }
}

enum FlowTabUITestSwitcherSelectionTransition: Equatable {
    case enterWindowCycle(
        from: FlowTabUITestSwitcherSelectionState
    )
    case exitWindowCycle(
        from: FlowTabUITestSwitcherSelectionState
    )
    case advanceApplication(
        from: FlowTabUITestSwitcherSelectionState
    )

    func isSatisfied(
        by snapshot: FlowTabUITestSwitcherDiagnosticsSnapshot
    ) -> Bool {
        guard
            let observedState =
                FlowTabUITestSwitcherSelectionState(
                    snapshot: snapshot
                )
        else {
            return false
        }

        switch self {
        case let .enterWindowCycle(baseline):
            return baseline.mode == "appCycle"
                && observedState.selectedBundleIdentifier
                    == baseline.selectedBundleIdentifier
                && observedState.mode
                    == "windowCycle("
                        + baseline.selectedBundleIdentifier
                        + ")"
        case let .exitWindowCycle(baseline):
            return baseline.mode.hasPrefix("windowCycle(")
                && observedState.selectedBundleIdentifier
                    == baseline.selectedBundleIdentifier
                && observedState.mode == "appCycle"
        case let .advanceApplication(baseline):
            return baseline.mode == "appCycle"
                && observedState != baseline
                && observedState.hasSupportedMode
        }
    }

    var diagnosticSummary: String {
        switch self {
        case let .enterWindowCycle(baseline):
            return "enterWindowCycle from{"
                + baseline.diagnosticSummary
                + "}"
        case let .exitWindowCycle(baseline):
            return "exitWindowCycle from{"
                + baseline.diagnosticSummary
                + "}"
        case let .advanceApplication(baseline):
            return "advanceApplication from{"
                + baseline.diagnosticSummary
                + "}"
        }
    }
}

final class FlowTabUITestSwitcherSelectionTransitionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSwitcherDiagnosticsSnapshot
        >

    init(
        transition:
            FlowTabUITestSwitcherSelectionTransition,
        previewExpectation:
            FlowTabUITestSwitcherPreviewProjectionExpectation?
                = nil,
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
            FlowTabUITestSwitcherDiagnosticsSnapshot
    ) {
        conditionOwner =
            FlowTabUITestConditionObservationOwner(
                observationRegistration:
                    observationRegistration,
                readback: readback,
                isSatisfied: { snapshot in
                    let previewProjection =
                        FlowTabUITestSwitcherPreviewProjectionSnapshot(
                            diagnostics: snapshot
                        )
                    let previewSatisfied: Bool
                    if let previewExpectation {
                        previewSatisfied =
                            previewProjection
                                .previewBundleIdentifier != nil
                            && previewProjection
                                .previewBundleIdentifier
                                == previewProjection
                                    .selectedBundleIdentifier
                            && previewExpectation.isSatisfied(
                                by: previewProjection
                            )
                    } else {
                        previewSatisfied = true
                    }
                    return acceptsEvidence()
                        && transition.isSatisfied(
                            by: snapshot
                        )
                        && previewSatisfied
                },
                describe: { snapshot in
                    let previewProjection =
                        FlowTabUITestSwitcherPreviewProjectionSnapshot(
                            diagnostics: snapshot
                        )
                    let previewDescription =
                        previewExpectation.map {
                            "expectedPreview=["
                                + $0.diagnosticSummary
                                + "] observedPreview=["
                                + previewProjection
                                    .diagnosticSummary
                                + "] "
                        } ?? "expectedPreview=none "
                    return "acceptanceEnabled="
                        + "\(acceptsEvidence()) "
                        + "expected=["
                        + transition.diagnosticSummary
                        + "] "
                        + previewDescription
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
        FlowTabUITestSwitcherDiagnosticsSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSwitcherDiagnosticsSnapshot
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
    private enum SwitcherWorkflowSelectionPolicy {
        static let keyboardTransitionWatchdog:
            TimeInterval = 3
    }

    func selectSwitcherWorkflowAppDirectly(
        _ workflowApp: SpaceFixtureResolvedWorkflow.App,
        diagnosticsSummary: XCUIElement,
        timeout: TimeInterval = 1.5
    ) -> Bool {
        do {
            try FlowTabUITestSwitcherCommandPayload.write(
                workflowApp.identity.bundleIdentifier
            )
        } catch {
            return false
        }

        let expectedBundleIdentifier =
            workflowApp.identity.bundleIdentifier
        var triggerCompleted = false
        let owner =
            FlowTabUITestSwitcherDiagnosticsObservationOwner(
                expectations: [
                    FlowTabUITestSwitcherDiagnosticsExpectation(
                        key: "selected",
                        expectedValue:
                            expectedBundleIdentifier
                    )
                ],
                acceptsEvidence: {
                    triggerCompleted
                },
                readback: {
                    self.switcherDiagnosticsSnapshot(
                        diagnosticsSummary,
                        keys: ["selected"]
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        postFlowTabUITestSwitcherCommand(
            .selectApp,
            traceLabel:
                "selectWorkflowApp.direct."
                + workflowApp.appID
        )
        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)

        if owner.waitForResolution(timeout: timeout) != nil {
            return true
        }
        logFlowTabUITestTrace(
            "[selectWorkflowApp.direct.fallback] "
                + "target=\(expectedBundleIdentifier) "
                + owner.diagnosticSummary
        )
        return false
    }

    func selectSwitcherWorkflowApp(
        _ workflowApp: SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        maxMoves: Int = 40
    ) {
        if selectSwitcherWorkflowAppDirectly(
            workflowApp,
            diagnosticsSummary: diagnosticsSummary
        ) {
            return
        }

        let targetBundleIdentifier =
            workflowApp.identity.bundleIdentifier
        for attempt in 0..<maxMoves {
            let baselineSnapshot =
                switcherDiagnosticsSnapshot(
                    diagnosticsSummary,
                    keys:
                        FlowTabUITestSwitcherSelectionState
                            .diagnosticsKeys
                )
            guard
                let baseline =
                    FlowTabUITestSwitcherSelectionState(
                        snapshot: baselineSnapshot
                    )
            else {
                XCTFail(
                    "Switcher selection lacks an exact "
                        + "selected/mode baseline. "
                        + baselineSnapshot.diagnosticSummary
                )
                return
            }
            logFlowTabUITestTrace(
                "[selectWorkflowApp.\(attempt + 1)] "
                    + "target=\(targetBundleIdentifier) "
                    + baseline.diagnosticSummary
            )
            if baseline.selectedBundleIdentifier
                == targetBundleIdentifier {
                return
            }

            let transition:
                FlowTabUITestSwitcherSelectionTransition
            if baseline.mode.hasPrefix("windowCycle(") {
                transition =
                    .exitWindowCycle(from: baseline)
            } else if baseline.mode == "appCycle" {
                transition =
                    .advanceApplication(from: baseline)
            } else {
                XCTFail(
                    "Switcher selection observed an "
                        + "unsupported mode. "
                        + baselineSnapshot.diagnosticSummary
                )
                return
            }

            guard
                performSwitcherWorkflowSelectionTransition(
                    transition,
                    attempt: attempt,
                    targetBundleIdentifier:
                        targetBundleIdentifier,
                    in: app,
                    diagnosticsSummary:
                        diagnosticsSummary
                )
            else {
                return
            }
        }

        XCTFail(
            """
            Failed to select switcher workflow app \(workflowApp.appName).

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
    }

    private func performSwitcherWorkflowSelectionTransition(
        _ transition:
            FlowTabUITestSwitcherSelectionTransition,
        attempt: Int,
        targetBundleIdentifier: String,
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement
    ) -> Bool {
        var triggerCompleted = false
        let owner =
            FlowTabUITestSwitcherSelectionTransitionObservationOwner(
                transition: transition,
                acceptsEvidence: {
                    triggerCompleted
                },
                readback: {
                    self.switcherDiagnosticsSnapshot(
                        diagnosticsSummary,
                        keys:
                            FlowTabUITestSwitcherSelectionState
                                .diagnosticsKeys
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        switch transition {
        case .enterWindowCycle:
            app.typeKey(
                .downArrow,
                modifierFlags: []
            )
        case .exitWindowCycle:
            app.typeKey(
                .upArrow,
                modifierFlags: []
            )
        case .advanceApplication:
            app.typeKey(
                .rightArrow,
                modifierFlags: []
            )
        }
        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)

        guard
            owner.waitForResolution(
                timeout:
                    SwitcherWorkflowSelectionPolicy
                        .keyboardTransitionWatchdog
            ) != nil
        else {
            XCTFail(
                "Switcher keyboard selection transition "
                    + "watchdog expired at attempt "
                    + "\(attempt + 1), "
                    + "target=\(targetBundleIdentifier). "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }
}
