import Foundation
import XCTest

private enum FlowTabUITestSwitcherSelectedAppPreviewPolicy {
    static let watchdog: TimeInterval = 12
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
                snapshot.selectedBundleIdentifier
        else {
            return nil
        }
        let observedTitles = Set(snapshot.titles)
        let matches = candidates.filter {
            $0.bundleIdentifier
                == selectedBundleIdentifier
                && $0.expectedTitles == observedTitles
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
        readback: @escaping () ->
            FlowTabUITestSwitcherPreviewProjectionSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: expectation.isSatisfied(by:),
            describe: { snapshot in
                "candidates=[\(expectation.diagnosticSummary)] "
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
}

extension FlowTabUITests {
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
                    FlowTabUITestSwitcherSelectedAppPreviewCandidate(
                        appID: $0.appID,
                        bundleIdentifier:
                            $0.identity.bundleIdentifier,
                        expectedTitles:
                            Set($0.expectedWindowTitles)
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
                    .watchdog
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
}
