import Foundation
import XCTest

struct FlowTabUITestSwitcherPreviewProjectionSnapshot: Equatable {
    let identifier: String
    let exists: Bool
    let rawValue: String?
    let previewValue: String?
    let selectedBundleIdentifier: String?
    let titles: [String]

    init(
        identifier: String,
        exists: Bool,
        rawValue: String?,
        previewValue: String?,
        selectedBundleIdentifier: String? = nil
    ) {
        self.identifier = identifier
        self.exists = exists
        self.rawValue = rawValue
        self.previewValue = previewValue
        self.selectedBundleIdentifier =
            selectedBundleIdentifier
        titles = Self.parseTitles(from: previewValue)
    }

    init(
        diagnostics:
            FlowTabUITestSwitcherDiagnosticsSnapshot
    ) {
        self.init(
            identifier: diagnostics.identifier,
            exists: diagnostics.exists,
            rawValue: diagnostics.rawValue,
            previewValue: diagnostics.values["preview"],
            selectedBundleIdentifier:
                diagnostics.values["selected"]
        )
    }

    var diagnosticSummary: String {
        "identifier=\(identifier) "
            + "exists=\(exists) "
            + "selectedBundleID="
            + "\(selectedBundleIdentifier ?? "nil") "
            + "previewBundleID="
            + "\(previewBundleIdentifier ?? "nil") "
            + "titles=\(titles.sorted()) "
            + "preview=\(previewValue ?? "nil") "
            + "raw=\(rawValue ?? "nil")"
    }

    var previewBundleIdentifier: String? {
        guard
            let previewValue,
            previewValue != "inactive",
            let separatorRange =
                previewValue.range(of: "::"),
            !previewValue[..<separatorRange.lowerBound]
                .isEmpty
        else {
            return nil
        }
        return String(
            previewValue[..<separatorRange.lowerBound]
        )
    }

    private static func parseTitles(
        from previewValue: String?
    ) -> [String] {
        guard
            let previewValue,
            previewValue != "inactive",
            let separatorRange =
                previewValue.range(of: "::")
        else {
            return []
        }
        let titleValues =
            previewValue[separatorRange.upperBound...]
        guard !titleValues.isEmpty else {
            return []
        }
        return titleValues.split(separator: "|").map(String.init)
    }
}

enum FlowTabUITestSwitcherPreviewProjectionExpectation: Equatable {
    case exactTitles(Set<String>)
    case exactTitleCount(
        titles: Set<String>,
        count: Int
    )
    case requiredRealWindows(
        standardTitles: Set<String>,
        fullscreenTitles: Set<String>
    )

    static func workflowApp(
        _ workflowApp:
            SpaceFixtureResolvedWorkflow.App,
        allowsNoisyCGSiblings: Bool
    ) -> Self {
        let expectedTitles =
            Set(workflowApp.expectedWindowTitles)
        guard allowsNoisyCGSiblings else {
            return .exactTitles(expectedTitles)
        }
        let fullscreenTitles =
            Set(workflowApp.fullscreenWindowTitles)
        return .requiredRealWindows(
            standardTitles:
                expectedTitles.subtracting(
                    fullscreenTitles
                ),
            fullscreenTitles: fullscreenTitles
        )
    }

    func isSatisfied(
        by snapshot:
            FlowTabUITestSwitcherPreviewProjectionSnapshot
    ) -> Bool {
        guard snapshot.exists else {
            return false
        }
        let observedTitles = Set(snapshot.titles)
        switch self {
        case let .exactTitles(expectedTitles):
            return observedTitles == expectedTitles
        case let .exactTitleCount(expectedTitles, expectedCount):
            return snapshot.titles.count == expectedCount
                && observedTitles == expectedTitles
        case let .requiredRealWindows(
            standardTitles,
            fullscreenTitles
        ):
            guard !fullscreenTitles.isEmpty else {
                return standardTitles.isSubset(
                    of: observedTitles
                )
            }
            return standardTitles.isSubset(of: observedTitles)
                && !observedTitles.isDisjoint(
                    with: fullscreenTitles
                )
        }
    }

    var diagnosticSummary: String {
        switch self {
        case let .exactTitles(expectedTitles):
            return "exactTitles=\(expectedTitles.sorted())"
        case let .exactTitleCount(expectedTitles, expectedCount):
            return "exactTitleCount=\(expectedCount) "
                + "exactTitles=\(expectedTitles.sorted())"
        case let .requiredRealWindows(
            standardTitles,
            fullscreenTitles
        ):
            return "requiredStandardTitles="
                + "\(standardTitles.sorted()) "
                + "requiredAnyFullscreenTitle="
                + "\(fullscreenTitles.sorted())"
        }
    }
}

final class FlowTabUITestSwitcherPreviewProjectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSwitcherPreviewProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestSwitcherPreviewProjectionExpectation,
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
                "expected{\(expectation.diagnosticSummary)} "
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
    func switcherPreviewTitles(
        from diagnosticsSummary: XCUIElement
    ) -> [String] {
        switcherPreviewProjectionSnapshot(
            diagnosticsSummary
        ).titles
    }

    func assertSwitcherPreviewShowsOnlyExpectedTitles(
        _ expectedTitles: [String],
        in diagnosticsSummary: XCUIElement,
        timeout: TimeInterval
    ) {
        _ = waitForSwitcherPreviewTitles(
            diagnosticsSummary,
            toEqual: Set(expectedTitles),
            timeout: timeout
        )
    }

    func waitForSwitcherPreviewTitles(
        _ diagnosticsSummary: XCUIElement,
        toEqual expectedTitles: Set<String>,
        timeout: TimeInterval
    ) -> Bool {
        waitForSwitcherPreviewProjection(
            .exactTitles(expectedTitles),
            in: diagnosticsSummary,
            timeout: timeout
        )
    }

    func waitForSwitcherPreviewTitles(
        _ diagnosticsSummary: XCUIElement,
        toExactlyMatch expectedTitles: [String],
        timeout: TimeInterval
    ) -> Bool {
        waitForSwitcherPreviewProjection(
            .exactTitleCount(
                titles: Set(expectedTitles),
                count: expectedTitles.count
            ),
            in: diagnosticsSummary,
            timeout: timeout
        )
    }

    func waitForNoisyFullscreenWorkflowPreviewTitles(
        _ diagnosticsSummary: XCUIElement,
        for workflowApp:
            SpaceFixtureResolvedWorkflow.App,
        timeout: TimeInterval
    ) -> Bool {
        return waitForSwitcherPreviewProjection(
            .workflowApp(
                workflowApp,
                allowsNoisyCGSiblings: true
            ),
            in: diagnosticsSummary,
            timeout: timeout
        )
    }

    private func waitForSwitcherPreviewProjection(
        _ expectation:
            FlowTabUITestSwitcherPreviewProjectionExpectation,
        in diagnosticsSummary: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let owner =
            FlowTabUITestSwitcherPreviewProjectionObservationOwner(
                expectation: expectation,
                readback: {
                    self.switcherPreviewProjectionSnapshot(
                        diagnosticsSummary
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        guard
            owner.waitForResolution(timeout: timeout) != nil
        else {
            XCTFail(
                "Switcher preview projection watchdog expired. "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    func switcherPreviewProjectionSnapshot(
        _ diagnosticsSummary: XCUIElement
    ) -> FlowTabUITestSwitcherPreviewProjectionSnapshot {
        let exists = diagnosticsSummary.exists
        let rawValue =
            exists
                ? elementStringValue(diagnosticsSummary)
                : nil
        let previewValue =
            rawValue.map {
                switcherPanelDiagnosticsValue(
                    in: $0,
                    key: "preview"
                )
            }
        let selectedBundleIdentifier =
            rawValue.map {
                switcherPanelDiagnosticsValue(
                    in: $0,
                    key: "selected"
                )
            }
        return FlowTabUITestSwitcherPreviewProjectionSnapshot(
            identifier: diagnosticsSummary.identifier,
            exists: exists,
            rawValue: rawValue,
            previewValue: previewValue,
            selectedBundleIdentifier:
                selectedBundleIdentifier
        )
    }
}
