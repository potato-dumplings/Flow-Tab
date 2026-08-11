import Foundation
import XCTest

struct FlowTabUITestWindowSearchProjectionSnapshot: Equatable {
    let diagnostics: FlowTabUITestSwitcherDiagnosticsSnapshot
    let results: [SwitcherSearchWindowResultObservation]

    var diagnosticSummary: String {
        let resultSnapshot =
            FlowTabUITestSwitcherSearchResultSnapshot(
                results: results
            )
        return "diagnostics={\(diagnostics.diagnosticSummary)} "
            + "results={\(resultSnapshot.diagnosticSummary)}"
    }
}

struct FlowTabUITestWindowSearchProjectionRequirement: Equatable {
    static let committedIndexExpectations = [
        FlowTabUITestSwitcherDiagnosticsExpectation(
            key: "searchIndexReadiness",
            expectedValue: "committedGenerationValidated"
        ),
        FlowTabUITestSwitcherDiagnosticsExpectation(
            key: "searchIndexResultState",
            expectedValue: "committedGenerationResult"
        ),
        FlowTabUITestSwitcherDiagnosticsExpectation(
            key: "searchIndexDegraded",
            expectedValue: "0"
        ),
        FlowTabUITestSwitcherDiagnosticsExpectation(
            key: "searchIndexCoversCurrentGeneration",
            expectedValue: "1"
        ),
        FlowTabUITestSwitcherDiagnosticsExpectation(
            key: "searchFreshnessBarrierRequested",
            expectedValue: "0"
        )
    ]

    static let diagnosticsKeys =
        ["searchResults"]
            + committedIndexExpectations.map(\.key)

    let resultSetExpectation:
        FlowTabUITestSwitcherSearchResultExpectation

    init(
        appID: String,
        expectedTitles: Set<String>,
        expectedCount: Int?
    ) {
        resultSetExpectation = .appWindowSet(
            appID: appID,
            expectedTitles: expectedTitles,
            expectedCount: expectedCount
        )
    }

    func isSatisfied(
        by snapshot: FlowTabUITestWindowSearchProjectionSnapshot
    ) -> Bool {
        snapshot.diagnostics.exists
            && Self.committedIndexExpectations.allSatisfy {
                $0.isSatisfied(by: snapshot.diagnostics)
            }
            && resultSetExpectation.isSatisfied(
                by: FlowTabUITestSwitcherSearchResultSnapshot(
                    results: snapshot.results
                )
            )
    }

    var diagnosticSummary: String {
        let committedIndex = Self.committedIndexExpectations
            .map(\.diagnosticSummary)
            .joined(separator: ",")
        return "resultSet={\(resultSetExpectation.diagnosticSummary)} "
            + "committedIndex=[\(committedIndex)]"
    }
}

final class FlowTabUITestWindowSearchProjectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestWindowSearchProjectionSnapshot
        >

    init(
        requirement:
            FlowTabUITestWindowSearchProjectionRequirement,
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
            FlowTabUITestWindowSearchProjectionSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: {
                acceptsEvidence()
                    && requirement.isSatisfied(by: $0)
            },
            describe: { snapshot in
                "acceptanceEnabled=\(acceptsEvidence()) "
                    + "expected={\(requirement.diagnosticSummary)} "
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
        FlowTabUITestWindowSearchProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestWindowSearchProjectionSnapshot
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
    func windowSearchProjectionSnapshot(
        _ diagnosticsSummary: XCUIElement
    ) -> FlowTabUITestWindowSearchProjectionSnapshot {
        let diagnostics = switcherDiagnosticsSnapshot(
            diagnosticsSummary,
            keys:
                FlowTabUITestWindowSearchProjectionRequirement
                    .diagnosticsKeys
        )
        let results = searchWindowResultObservations(
            inDiagnosticsProjection:
                diagnostics.values["searchResults"] ?? ""
        )
        return FlowTabUITestWindowSearchProjectionSnapshot(
            diagnostics: diagnostics,
            results: results
        )
    }
}
