import AppKit
import Foundation
import XCTest

enum FlowTabUITestInAppWorkflowWindowObservationPolicy {
    static let initialTopologyReadinessWatchdog: TimeInterval = 12
    static let currentTopologyReadinessWatchdog: TimeInterval = 4
    static let fixtureReactivationWatchdog: TimeInterval = 12
}

enum FlowTabUITestWorkflowSpaceWindowScope: Equatable {
    case frontmost(bundleIdentifier: String)
    case activeSpace

    func accepts(
        frontmostBundleIdentifier: String?
    ) -> Bool {
        switch self {
        case let .frontmost(bundleIdentifier):
            return frontmostBundleIdentifier
                == bundleIdentifier
        case .activeSpace:
            return true
        }
    }

    var diagnosticSummary: String {
        switch self {
        case let .frontmost(bundleIdentifier):
            return "scope=frontmost "
                + "expectedBundle=\(bundleIdentifier)"
        case .activeSpace:
            return "scope=activeSpace"
        }
    }
}

struct FlowTabUITestWorkflowSpaceWindowSnapshot: Equatable {
    let frontmostBundleIdentifier: String?
    let topmostCGWindow: WorkflowCGWindowObservation?

    func matchingWindow(
        scope: FlowTabUITestWorkflowSpaceWindowScope,
        title: String
    ) -> WorkflowCGWindowObservation? {
        guard scope.accepts(
                frontmostBundleIdentifier:
                    frontmostBundleIdentifier
              ),
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
        scope: FlowTabUITestWorkflowSpaceWindowScope,
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
                    scope: scope,
                    title: expectedTitle
                ) != nil
            },
            describe: { snapshot in
                "\(scope.diagnosticSummary) "
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
        return makeWorkflowSpaceWindowObservationOwner(
            scope: .frontmost(
                bundleIdentifier: bundleIdentifier
            ),
            title: title,
            app: workflowApp
        )
    }

    func makeActiveSpaceWorkflowWindowObservationOwner(
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> FlowTabUITestWorkflowSpaceWindowObservationOwner {
        makeWorkflowSpaceWindowObservationOwner(
            scope: .activeSpace,
            title: title,
            app: workflowApp
        )
    }

    private func makeWorkflowSpaceWindowObservationOwner(
        scope: FlowTabUITestWorkflowSpaceWindowScope,
        title: String,
        app workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> FlowTabUITestWorkflowSpaceWindowObservationOwner {
        let bundleIdentifier =
            workflowApp.identity.bundleIdentifier
        return FlowTabUITestWorkflowSpaceWindowObservationOwner(
            scope: scope,
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
