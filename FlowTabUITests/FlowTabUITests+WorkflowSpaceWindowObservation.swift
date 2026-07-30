import AppKit
import Foundation
import XCTest

struct FlowTabUITestWorkflowSpaceWindowSnapshot: Equatable {
    let frontmostBundleIdentifier: String?
    let topmostCGWindow: WorkflowCGWindowObservation?

    func matchingWindow(
        bundleIdentifier: String,
        title: String
    ) -> WorkflowCGWindowObservation? {
        guard frontmostBundleIdentifier == bundleIdentifier,
              let topmostCGWindow,
              topmostCGWindow.matchesWorkflowSpaceWindow(
                title: title
              )
        else {
            return nil
        }
        return topmostCGWindow
    }

    var diagnosticSummary: String {
        let windowSummary = topmostCGWindow.map {
            "\($0.number):\($0.title ?? "nil")@"
                + "\(String(describing: $0.frame))"
        } ?? "nil"
        return "frontmostBundle="
            + "\(frontmostBundleIdentifier ?? "nil") "
            + "topmostCGWindow=\(windowSummary)"
    }
}

final class FlowTabUITestWorkflowSpaceWindowObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestWorkflowSpaceWindowSnapshot
        >

    init(
        expectedBundleIdentifier: String,
        expectedTitle: String,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestWorkflowSpaceWindowSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: { snapshot in
                snapshot.matchingWindow(
                    bundleIdentifier: expectedBundleIdentifier,
                    title: expectedTitle
                ) != nil
            },
            describe: { snapshot in
                "expectedBundle=\(expectedBundleIdentifier) "
                    + "expectedTitle=\(expectedTitle) "
                    + snapshot.diagnosticSummary
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestWorkflowSpaceWindowSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestWorkflowSpaceWindowSnapshot
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
    func makeWorkflowSpaceWindowObservationOwner(
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> FlowTabUITestWorkflowSpaceWindowObservationOwner {
        let bundleIdentifier =
            workflowApp.identity.bundleIdentifier
        return FlowTabUITestWorkflowSpaceWindowObservationOwner(
            expectedBundleIdentifier: bundleIdentifier,
            expectedTitle: title,
            observationRegistration:
                FlowTabUITestWorkflowWindowActivationObservation
                    .registration(
                        bundleIdentifier: bundleIdentifier
                    ),
            readback: {
                self.workflowSpaceWindowSnapshot(
                    app: workflowApp
                )
            }
        )
    }

    func workflowSpaceWindowSnapshot(
        app workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> FlowTabUITestWorkflowSpaceWindowSnapshot {
        let bundleIdentifier =
            workflowApp.identity.bundleIdentifier
        return FlowTabUITestWorkflowSpaceWindowSnapshot(
            frontmostBundleIdentifier:
                NSWorkspace.shared.frontmostApplication?
                    .bundleIdentifier,
            topmostCGWindow:
                topmostOnScreenCGWindow(
                    forBundleIdentifier: bundleIdentifier
                )
        )
    }
}
