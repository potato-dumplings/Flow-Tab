import Foundation
import XCTest

struct FlowTabUITestSwitcherSelectedWindowTitleSnapshot: Equatable {
    let identifier: String
    let exists: Bool
    let rawValue: String?
    let selectedTitle: String?

    var diagnosticSummary: String {
        "identifier=\(identifier) "
            + "exists=\(exists) "
            + "selectedTitle=\(selectedTitle ?? "nil") "
            + "raw=\(rawValue ?? "nil")"
    }
}

enum FlowTabUITestSwitcherSelectedWindowTitleExpectation: Equatable {
    case exact(String)
    case oneOf(Set<String>)

    func isSatisfied(
        by snapshot:
            FlowTabUITestSwitcherSelectedWindowTitleSnapshot
    ) -> Bool {
        guard
            snapshot.exists,
            let selectedTitle = snapshot.selectedTitle
        else {
            return false
        }
        switch self {
        case let .exact(expectedTitle):
            return selectedTitle == expectedTitle
        case let .oneOf(expectedTitles):
            return expectedTitles.contains(selectedTitle)
        }
    }

    var diagnosticSummary: String {
        switch self {
        case let .exact(expectedTitle):
            return "exactTitle=\(expectedTitle)"
        case let .oneOf(expectedTitles):
            return "allowedTitles=\(expectedTitles.sorted())"
        }
    }
}

final class FlowTabUITestSwitcherSelectedWindowTitleObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSwitcherSelectedWindowTitleSnapshot
        >

    init(
        expectation:
            FlowTabUITestSwitcherSelectedWindowTitleExpectation,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestSwitcherSelectedWindowTitleSnapshot
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
        FlowTabUITestSwitcherSelectedWindowTitleSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSwitcherSelectedWindowTitleSnapshot
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
    func assertSwitcherSelectedWindowTitle(
        _ expectedTitle: String,
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        timeout: TimeInterval = 4,
        message: String
    ) {
        assertSwitcherSelectedWindowTitle(
            .exact(expectedTitle),
            in: app,
            diagnosticsSummary: diagnosticsSummary,
            timeout: timeout,
            message: message
        )
    }

    func assertSwitcherSelectedWindowTitle(
        oneOf expectedTitles: Set<String>,
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        timeout: TimeInterval = 4,
        message: String
    ) {
        XCTAssertFalse(
            expectedTitles.isEmpty,
            "Expected at least one allowed selected window title."
        )
        assertSwitcherSelectedWindowTitle(
            .oneOf(expectedTitles),
            in: app,
            diagnosticsSummary: diagnosticsSummary,
            timeout: timeout,
            message: message
        )
    }

    private func assertSwitcherSelectedWindowTitle(
        _ expectation:
            FlowTabUITestSwitcherSelectedWindowTitleExpectation,
        in app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        timeout: TimeInterval,
        message: String
    ) {
        let owner =
            FlowTabUITestSwitcherSelectedWindowTitleObservationOwner(
                expectation: expectation,
                readback: {
                    self.switcherSelectedWindowTitleSnapshot(
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
                """
                \(message)
                Selected window title projection did not satisfy \
                \(expectation.diagnosticSummary).
                \(owner.diagnosticSummary)

                \(switcherDebugSummary(
                    app,
                    diagnosticsSummary: diagnosticsSummary
                ))
                """
            )
            return
        }
    }

    private func switcherSelectedWindowTitleSnapshot(
        _ diagnosticsSummary: XCUIElement
    ) -> FlowTabUITestSwitcherSelectedWindowTitleSnapshot {
        let exists = diagnosticsSummary.exists
        let rawValue =
            exists
                ? elementStringValue(diagnosticsSummary)
                : nil
        let selectedTitle =
            rawValue.map {
                switcherPanelDiagnosticsValue(
                    in: $0,
                    key: "selectedWindowTitle"
                )
            }
        return FlowTabUITestSwitcherSelectedWindowTitleSnapshot(
            identifier: diagnosticsSummary.identifier,
            exists: exists,
            rawValue: rawValue,
            selectedTitle: selectedTitle
        )
    }
}
