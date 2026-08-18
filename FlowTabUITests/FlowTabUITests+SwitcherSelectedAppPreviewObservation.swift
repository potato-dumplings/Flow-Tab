import Foundation
import XCTest

enum FlowTabUITestSwitcherSelectedAppPreviewPolicy {
    static let transitionWatchdog: TimeInterval = 12
}

struct FlowTabUITestSwitcherSelectedAppPreviewCandidate: Equatable {
    let appID: String
    let bundleIdentifier: String
    let expectedTitles: Set<String>

    var diagnosticSummary: String {
        "appID=\(appID) "
            + "bundleID=\(bundleIdentifier) "
            + "titles=\(expectedTitles.sorted())"
    }
}

struct FlowTabUITestSwitcherSelectedAppPreviewExpectation: Equatable {
    let candidates: [
        FlowTabUITestSwitcherSelectedAppPreviewCandidate
    ]

    func matchingCandidate(
        in snapshot:
            FlowTabUITestSwitcherPreviewProjectionSnapshot
    ) -> FlowTabUITestSwitcherSelectedAppPreviewCandidate? {
        guard
            snapshot.exists,
            let selectedBundleIdentifier =
                snapshot.selectedBundleIdentifier,
            snapshot.previewBundleIdentifier
                == selectedBundleIdentifier
        else {
            return nil
        }
        let observedTitles = Set(snapshot.titles)
        let matches = candidates.filter {
            $0.bundleIdentifier
                == selectedBundleIdentifier
                && $0.expectedTitles == observedTitles
                && $0.expectedTitles.count
                    == snapshot.titles.count
        }
        guard matches.count == 1 else {
            return nil
        }
        return matches[0]
    }

    func isSatisfied(
        by snapshot:
            FlowTabUITestSwitcherPreviewProjectionSnapshot
    ) -> Bool {
        matchingCandidate(in: snapshot) != nil
    }

    var diagnosticSummary: String {
        candidates
            .sorted { $0.appID < $1.appID }
            .map(\.diagnosticSummary)
            .joined(separator: " | ")
    }
}

final class FlowTabUITestSwitcherSelectedAppPreviewObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSwitcherPreviewProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestSwitcherSelectedAppPreviewExpectation,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        acceptsResolution: @escaping () -> Bool = { true },
        readback: @escaping () ->
            FlowTabUITestSwitcherPreviewProjectionSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: {
                acceptsResolution()
                    && expectation.isSatisfied(by: $0)
            },
            describe: { snapshot in
                "candidates=[\(expectation.diagnosticSummary)] "
                    + "acceptsResolution=\(acceptsResolution()) "
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
        FlowTabUITestSwitcherPreviewProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSwitcherPreviewProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }

    deinit {
        cancel()
    }
}

extension FlowTabUITests {
    func performAndWaitForSwitcherSelectedAppPreviewTransition(
        _ workflowApp: SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication,
        diagnosticsSummaryElement: XCUIElement,
        trigger: () -> Void
    ) -> FlowTabUITestSwitcherPreviewProjectionSnapshot? {
        let expectation =
            FlowTabUITestSwitcherSelectedAppPreviewExpectation(
                candidates: [
                    switcherSelectedAppPreviewCandidate(
                        for: workflowApp
                    )
                ]
            )
        var triggerDidComplete = false
        let owner =
            FlowTabUITestSwitcherSelectedAppPreviewObservationOwner(
                expectation: expectation,
                acceptsResolution: {
                    triggerDidComplete
                },
                readback: {
                    self.switcherPreviewProjectionSnapshot(
                        diagnosticsSummaryElement
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        trigger()
        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)

        guard let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSwitcherSelectedAppPreviewPolicy
                    .transitionWatchdog
        ) else {
            XCTFail(
                "Selected-app preview transition watchdog expired "
                    + "for \(workflowApp.appName). "
                    + owner.diagnosticSummary
                    + "\n\n"
                    + switcherDebugSummary(
                        app,
                        diagnosticsSummary:
                            diagnosticsSummaryElement
                    )
            )
            return nil
        }
        return evidence.value
    }

    func matchedWorkflowAppForVisibleSwitcherPreview(
        _ workflow: SpaceFixtureResolvedWorkflow,
        diagnosticsSummaryElement: XCUIElement,
        excludingAppIDs: Set<String> = []
    ) -> SpaceFixtureResolvedWorkflow.App? {
        let eligibleApps = workflow.apps.filter {
            !excludingAppIDs.contains($0.appID)
        }
        let expectation =
            FlowTabUITestSwitcherSelectedAppPreviewExpectation(
                candidates: eligibleApps.map {
                    switcherSelectedAppPreviewCandidate(
                        for: $0
                    )
                }
            )
        let owner =
            FlowTabUITestSwitcherSelectedAppPreviewObservationOwner(
                expectation: expectation,
                readback: {
                    self.switcherPreviewProjectionSnapshot(
                        diagnosticsSummaryElement
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        guard let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSwitcherSelectedAppPreviewPolicy
                    .transitionWatchdog
        ) else {
            XCTFail(
                "Selected-app preview watchdog expired. "
                    + owner.diagnosticSummary
            )
            return nil
        }
        guard let candidate = expectation.matchingCandidate(
            in: evidence.value
        ) else {
            XCTFail(
                "Selected-app preview resolved without a candidate. "
                    + owner.diagnosticSummary
            )
            return nil
        }
        return eligibleApps.first {
            $0.appID == candidate.appID
        }
    }

    private func switcherSelectedAppPreviewCandidate(
        for workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> FlowTabUITestSwitcherSelectedAppPreviewCandidate {
        FlowTabUITestSwitcherSelectedAppPreviewCandidate(
            appID: workflowApp.appID,
            bundleIdentifier:
                workflowApp.identity.bundleIdentifier,
            expectedTitles:
                Set(workflowApp.expectedWindowTitles)
        )
    }
}
