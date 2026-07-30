import CoreGraphics
import Foundation
import XCTest

struct FlowTabUITestWorkflowSpaceWindowCollectionSnapshot: Equatable {
    let observations: [WorkflowCGWindowObservation]

    func matchingWindow(
        title: String
    ) -> WorkflowCGWindowObservation? {
        observations.first {
            $0.matchesWorkflowSpaceWindow(title: title)
        }
    }

    var diagnosticSummary: String {
        let descriptions = observations.map {
            "\($0.number):\($0.title ?? "nil")@"
                + "\(String(describing: $0.frame))"
        }
        return "onScreenCGWindows=["
            + descriptions.joined(separator: ";")
            + "]"
    }
}

final class FlowTabUITestWorkflowSpaceWindowCollectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestWorkflowSpaceWindowCollectionSnapshot
        >

    init(
        expectedTitle: String,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestWorkflowSpaceWindowCollectionSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: { snapshot in
                snapshot.matchingWindow(
                    title: expectedTitle
                ) != nil
            },
            describe: { snapshot in
                "expectedTitle=\(expectedTitle) "
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
        FlowTabUITestWorkflowSpaceWindowCollectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestWorkflowSpaceWindowCollectionSnapshot
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
    func makeWorkflowSpaceWindowCollectionObservationOwner(
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> FlowTabUITestWorkflowSpaceWindowCollectionObservationOwner {
        let bundleIdentifier =
            workflowApp.identity.bundleIdentifier
        return FlowTabUITestWorkflowSpaceWindowCollectionObservationOwner(
            expectedTitle: title,
            observationRegistration:
                FlowTabUITestWorkflowWindowActivationObservation
                    .registration(
                        bundleIdentifier: bundleIdentifier
                    ),
            readback: {
                FlowTabUITestWorkflowSpaceWindowCollectionSnapshot(
                    observations:
                        self.workflowCGWindowObservations(
                            bundleIdentifier:
                                bundleIdentifier,
                            options: [
                                .optionOnScreenOnly,
                                .excludeDesktopElements
                            ]
                        )
                )
            }
        )
    }
}
