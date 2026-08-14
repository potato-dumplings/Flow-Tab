import CoreGraphics
import Foundation
import XCTest

enum FlowTabUITestInAppConfirmationObservationPolicy {
    static let panelDismissalWatchdog: TimeInterval = 4
    static let exactWindowActivationWatchdog: TimeInterval = 12
}

enum FlowTabUITestInAppConfirmationBaselineIssue:
    String,
    Equatable
{
    case panelReadbackMissing
    case panelAlreadyDismissed
    case activationReadbackMissing
    case selectedWindowAlreadyActive
}

struct FlowTabUITestInAppConfirmationEvidence {
    let dismissal: FlowTabUITestConditionEvidence<
        FlowTabUITestElementExistenceSnapshot
    >
    let activation: FlowTabUITestConditionEvidence<
        FlowTabUITestWorkflowWindowActivationSnapshot
    >
}

protocol FlowTabUITestInAppConfirmationTriggerLifecycle:
    AnyObject
{
    func markTriggerStarted()
    func markTriggerCompleted()
}

private final class FlowTabUITestInAppConfirmationState {
    let expectedBundleIdentifier: String
    let expectedWindowNumber: CGWindowID

    private(set) var initialPanelExists: Bool?
    private(set) var initialActivationMatches: Bool?
    private(set) var hasObservedActivationMismatch = false
    private(set) var isTriggerCompleted = false

    init(
        expectedBundleIdentifier: String,
        expectedWindowNumber: CGWindowID
    ) {
        self.expectedBundleIdentifier = expectedBundleIdentifier
        self.expectedWindowNumber = expectedWindowNumber
    }

    func reset() {
        initialPanelExists = nil
        initialActivationMatches = nil
        hasObservedActivationMismatch = false
        isTriggerCompleted = false
    }

    func recordInitialPanelExists(_ exists: Bool?) {
        initialPanelExists = exists
    }

    func observeActivation(
        _ snapshot: FlowTabUITestWorkflowWindowActivationSnapshot
    ) {
        let matches = snapshot.matches(
            bundleIdentifier: expectedBundleIdentifier,
            windowNumber: expectedWindowNumber
        )
        if initialActivationMatches == nil {
            initialActivationMatches = matches
        }
        if !matches {
            hasObservedActivationMismatch = true
        }
    }

    func markTriggerCompleted() {
        isTriggerCompleted = true
    }

    var acceptsActivationEvidence: Bool {
        isTriggerCompleted && hasObservedActivationMismatch
    }

    var baselineIssue:
        FlowTabUITestInAppConfirmationBaselineIssue?
    {
        guard let initialPanelExists else {
            return .panelReadbackMissing
        }
        guard initialPanelExists else {
            return .panelAlreadyDismissed
        }
        guard let initialActivationMatches else {
            return .activationReadbackMissing
        }
        guard !initialActivationMatches else {
            return .selectedWindowAlreadyActive
        }
        return nil
    }

    var diagnosticSummary: String {
        let panelText = initialPanelExists.map {
            $0 ? "1" : "0"
        } ?? "unbound"
        let activationText = initialActivationMatches.map {
            $0 ? "1" : "0"
        } ?? "unbound"
        let issueText = baselineIssue?.rawValue ?? "none"
        return "initialPanelExists=\(panelText) "
            + "initialActivationMatches=\(activationText) "
            + "hasObservedActivationMismatch="
            + "\(hasObservedActivationMismatch ? 1 : 0) "
            + "triggerCompleted=\(isTriggerCompleted ? 1 : 0) "
            + "baselineIssue=\(issueText)"
    }
}

final class FlowTabUITestInAppConfirmationObservationOwner {
    private let state: FlowTabUITestInAppConfirmationState
    private let dismissalOwner:
        FlowTabUITestElementNonExistenceObservationOwner
    private let activationOwner:
        FlowTabUITestWorkflowWindowActivationObservationOwner

    init(
        expectedBundleIdentifier: String,
        expectedWindowNumber: CGWindowID,
        expectedTitle: String,
        panelElementIdentifier: String,
        panelScheduledRegistration:
            @escaping FlowTabUITestConditionObservationRegistration =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        activationObservationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        panelReadback: @escaping () -> Bool,
        activationReadback: @escaping () ->
            FlowTabUITestWorkflowWindowActivationSnapshot
    ) {
        let state = FlowTabUITestInAppConfirmationState(
            expectedBundleIdentifier: expectedBundleIdentifier,
            expectedWindowNumber: expectedWindowNumber
        )
        self.state = state
        dismissalOwner =
            FlowTabUITestElementNonExistenceObservationOwner(
                elementIdentifier: panelElementIdentifier,
                scheduledRegistration:
                    panelScheduledRegistration,
                readback: panelReadback
            )
        activationOwner =
            FlowTabUITestWorkflowWindowActivationObservationOwner(
                expectedBundleIdentifier:
                    expectedBundleIdentifier,
                expectedWindowNumber: expectedWindowNumber,
                expectedTitle: expectedTitle,
                acceptsEvidence: {
                    state.acceptsActivationEvidence
                },
                observationRegistration:
                    activationObservationRegistration,
                readback: {
                    let snapshot = activationReadback()
                    state.observeActivation(snapshot)
                    return snapshot
                }
            )
    }

    func start() {
        state.reset()
        activationOwner.start()
        dismissalOwner.start()
        state.recordInitialPanelExists(
            dismissalOwner.latestEvidence?.value.exists
        )
    }

    func markTriggerCompleted() {
        guard !state.isTriggerCompleted else { return }
        state.markTriggerCompleted()
        dismissalOwner.markTriggerCompleted()
        activationOwner.requestReadback(
            source: .triggerReadback
        )
    }

    func waitForResolution(
        panelDismissalTimeout: TimeInterval,
        exactWindowActivationTimeout: TimeInterval
    ) -> FlowTabUITestInAppConfirmationEvidence? {
        let dismissal = dismissalOwner.waitForResolution(
            timeout: panelDismissalTimeout
        )
        let activation = activationOwner.waitForResolution(
            timeout: exactWindowActivationTimeout
        )
        guard
            state.baselineIssue == nil,
            let dismissal,
            let activation
        else {
            return nil
        }
        return FlowTabUITestInAppConfirmationEvidence(
            dismissal: dismissal,
            activation: activation
        )
    }

    var baselineIssue:
        FlowTabUITestInAppConfirmationBaselineIssue?
    {
        state.baselineIssue
    }

    var resolvedEvidence:
        FlowTabUITestInAppConfirmationEvidence?
    {
        guard
            state.baselineIssue == nil,
            let dismissal = dismissalOwner.resolvedEvidence,
            let activation = activationOwner.resolvedEvidence
        else {
            return nil
        }
        return FlowTabUITestInAppConfirmationEvidence(
            dismissal: dismissal,
            activation: activation
        )
    }

    var diagnosticSummary: String {
        state.diagnosticSummary
            + " dismissal{\(dismissalOwner.diagnosticSummary)}"
            + " activation{\(activationOwner.diagnosticSummary)}"
    }

    func cancel() {
        dismissalOwner.cancel()
        activationOwner.cancel()
    }

    deinit {
        cancel()
    }
}

extension FlowTabUITests {
    @discardableResult
    func confirmInAppSelectionAndWaitForEvidence(
        windowNumber: CGWindowID,
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App,
        diagnosticsSummary: XCUIElement,
        traceLabel: String,
        additionalTriggerLifecycle:
            FlowTabUITestInAppConfirmationTriggerLifecycle? = nil
    ) -> FlowTabUITestInAppConfirmationEvidence? {
        let bundleIdentifier =
            workflowApp.identity.bundleIdentifier
        let owner =
            FlowTabUITestInAppConfirmationObservationOwner(
                expectedBundleIdentifier: bundleIdentifier,
                expectedWindowNumber: windowNumber,
                expectedTitle: title,
                panelElementIdentifier:
                    diagnosticsSummary.identifier,
                activationObservationRegistration:
                    FlowTabUITestWorkflowWindowActivationObservation
                        .registration(
                            bundleIdentifier: bundleIdentifier
                        ),
                panelReadback: {
                    diagnosticsSummary.exists
                },
                activationReadback: {
                    self.workflowWindowActivationSnapshot(
                        title: title,
                        app: workflowApp
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        guard owner.baselineIssue == nil else {
            XCTFail(
                "In-App confirmation baseline rejected for "
                    + "\(traceLabel). \(owner.diagnosticSummary)"
            )
            return nil
        }

        additionalTriggerLifecycle?.markTriggerStarted()
        postFlowTabUITestSwitcherCommandAndWaitForDelivery(
            .confirm,
            traceLabel: traceLabel
        )
        owner.markTriggerCompleted()
        additionalTriggerLifecycle?.markTriggerCompleted()

        guard
            let evidence = owner.waitForResolution(
                panelDismissalTimeout:
                    FlowTabUITestInAppConfirmationObservationPolicy
                        .panelDismissalWatchdog,
                exactWindowActivationTimeout:
                    FlowTabUITestInAppConfirmationObservationPolicy
                        .exactWindowActivationWatchdog
            )
        else {
            XCTFail(
                "In-App confirmation evidence watchdog expired "
                    + "for \(traceLabel). "
                    + owner.diagnosticSummary
            )
            return nil
        }

        XCTAssertFalse(
            evidence.dismissal.value.exists,
            "In-App confirmation must dismiss the exact "
                + "diagnostics panel for \(traceLabel)."
        )
        XCTAssertTrue(
            evidence.activation.value.matches(
                bundleIdentifier: bundleIdentifier,
                windowNumber: windowNumber
            ),
            "In-App confirmation must activate the exact "
                + "selected window for \(traceLabel)."
        )
        return evidence
    }
}
