import Foundation
import XCTest

enum FlowTabUITestSwitcherDiagnosticsValueMatch: Equatable {
    case equals(String)
    case hasPrefix(String)

    func isSatisfied(by value: String) -> Bool {
        switch self {
        case let .equals(expectedValue):
            return value == expectedValue
        case let .hasPrefix(expectedPrefix):
            return value.hasPrefix(expectedPrefix)
        }
    }

    var diagnosticSummary: String {
        switch self {
        case let .equals(expectedValue):
            return "equals \(expectedValue)"
        case let .hasPrefix(expectedPrefix):
            return "hasPrefix \(expectedPrefix)"
        }
    }
}

struct FlowTabUITestSwitcherDiagnosticsExpectation: Equatable {
    let key: String
    let valueMatch:
        FlowTabUITestSwitcherDiagnosticsValueMatch
    let decodesPercentEncoding: Bool

    init(
        key: String,
        expectedValue: String,
        decodesPercentEncoding: Bool = false
    ) {
        self.key = key
        valueMatch = .equals(expectedValue)
        self.decodesPercentEncoding =
            decodesPercentEncoding
    }

    init(
        key: String,
        expectedPrefix: String,
        decodesPercentEncoding: Bool = false
    ) {
        self.key = key
        valueMatch = .hasPrefix(expectedPrefix)
        self.decodesPercentEncoding =
            decodesPercentEncoding
    }

    func observedValue(
        in snapshot: FlowTabUITestSwitcherDiagnosticsSnapshot
    ) -> String? {
        guard let value = snapshot.values[key] else {
            return nil
        }
        guard decodesPercentEncoding else {
            return value
        }
        return value.removingPercentEncoding ?? value
    }

    func isSatisfied(
        by snapshot: FlowTabUITestSwitcherDiagnosticsSnapshot
    ) -> Bool {
        observedValue(in: snapshot).map {
            valueMatch.isSatisfied(by: $0)
        } == true
    }

    var diagnosticSummary: String {
        "\(key){\(valueMatch.diagnosticSummary)}"
            + (decodesPercentEncoding ? "[percentDecoded]" : "")
    }
}

struct FlowTabUITestSwitcherDiagnosticsSnapshot: Equatable {
    let identifier: String
    let exists: Bool
    let rawValue: String?
    let values: [String: String]

    var diagnosticSummary: String {
        let valueSummary = values.keys.sorted().map {
            "\($0)=\(values[$0] ?? "")"
        }.joined(separator: ",")
        return "identifier=\(identifier) "
            + "exists=\(exists) "
            + "values=[\(valueSummary)] "
            + "raw=\(rawValue ?? "nil")"
    }
}

final class FlowTabUITestSwitcherDiagnosticsObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSwitcherDiagnosticsSnapshot
        >

    init(
        expectations: [
            FlowTabUITestSwitcherDiagnosticsExpectation
        ],
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
        let expectedDescription = expectations.map(
            \.diagnosticSummary
        ).joined(separator: ",")
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: { snapshot in
                acceptsEvidence()
                    && snapshot.exists
                    && expectations.allSatisfy {
                        $0.isSatisfied(by: snapshot)
                    }
            },
            describe: { snapshot in
                "acceptanceEnabled=\(acceptsEvidence()) "
                    + "expected=[\(expectedDescription)] "
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
    func waitForSwitcherDiagnostics(
        _ diagnosticsSummary: XCUIElement,
        key: String,
        equals expectedValue: String,
        decodesPercentEncoding: Bool = false,
        timeout: TimeInterval
    ) -> Bool {
        waitForSwitcherDiagnostics(
            [
                FlowTabUITestSwitcherDiagnosticsExpectation(
                    key: key,
                    expectedValue: expectedValue,
                    decodesPercentEncoding:
                        decodesPercentEncoding
                )
            ],
            in: diagnosticsSummary,
            timeout: timeout
        )
    }

    func waitForSwitcherDiagnostics(
        _ diagnosticsSummary: XCUIElement,
        key: String,
        hasPrefix expectedPrefix: String,
        timeout: TimeInterval
    ) -> Bool {
        waitForSwitcherDiagnostics(
            [
                FlowTabUITestSwitcherDiagnosticsExpectation(
                    key: key,
                    expectedPrefix: expectedPrefix
                )
            ],
            in: diagnosticsSummary,
            timeout: timeout
        )
    }

    func waitForSwitcherDiagnostics(
        _ expectations: [
            FlowTabUITestSwitcherDiagnosticsExpectation
        ],
        in diagnosticsSummary: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let owner =
            FlowTabUITestSwitcherDiagnosticsObservationOwner(
                expectations: expectations,
                readback: {
                    self.switcherDiagnosticsSnapshot(
                        diagnosticsSummary,
                        keys: expectations.map(\.key)
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        guard
            owner.waitForResolution(timeout: timeout) != nil
        else {
            XCTFail(
                "Switcher diagnostics did not satisfy "
                    + "the expected projection. "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    func performAndWaitForSwitcherDiagnostics(
        _ diagnosticsSummary: XCUIElement,
        key: String,
        equals expectedValue: String,
        decodesPercentEncoding: Bool = false,
        timeout: TimeInterval,
        trigger: () -> Void
    ) -> Bool {
        performAndWaitForSwitcherDiagnostics(
            [
                FlowTabUITestSwitcherDiagnosticsExpectation(
                    key: key,
                    expectedValue: expectedValue,
                    decodesPercentEncoding:
                        decodesPercentEncoding
                )
            ],
            in: diagnosticsSummary,
            timeout: timeout,
            trigger: trigger
        )
    }

    func performAndWaitForSwitcherDiagnostics(
        _ diagnosticsSummary: XCUIElement,
        key: String,
        hasPrefix expectedPrefix: String,
        timeout: TimeInterval,
        trigger: () -> Void
    ) -> Bool {
        performAndWaitForSwitcherDiagnostics(
            [
                FlowTabUITestSwitcherDiagnosticsExpectation(
                    key: key,
                    expectedPrefix: expectedPrefix
                )
            ],
            in: diagnosticsSummary,
            timeout: timeout,
            trigger: trigger
        )
    }

    func performAndWaitForSwitcherDiagnostics(
        _ expectations: [
            FlowTabUITestSwitcherDiagnosticsExpectation
        ],
        in diagnosticsSummary: XCUIElement,
        timeout: TimeInterval,
        trigger: () -> Void
    ) -> Bool {
        var triggerCompleted = false
        let owner =
            FlowTabUITestSwitcherDiagnosticsObservationOwner(
                expectations: expectations,
                acceptsEvidence: {
                    triggerCompleted
                },
                readback: {
                    self.switcherDiagnosticsSnapshot(
                        diagnosticsSummary,
                        keys: expectations.map(\.key)
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        trigger()
        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)

        guard
            owner.waitForResolution(timeout: timeout) != nil
        else {
            XCTFail(
                "Switcher diagnostics did not satisfy "
                    + "the expected projection. "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    func assertSwitcherWindowCycle(
        in app: XCUIApplication,
        timeout: TimeInterval,
        trigger: (() -> Void)? = nil
    ) {
        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        let matched: Bool
        if let trigger {
            matched = performAndWaitForSwitcherDiagnostics(
                diagnosticsSummary,
                key: "mode",
                hasPrefix: "windowCycle",
                timeout: timeout,
                trigger: trigger
            )
        } else {
            matched = waitForSwitcherDiagnostics(
                diagnosticsSummary,
                key: "mode",
                hasPrefix: "windowCycle",
                timeout: timeout
            )
        }
        XCTAssertTrue(matched)
    }

    func switcherPanelDiagnosticsValue(
        _ diagnosticsSummaryElement: XCUIElement,
        key: String
    ) -> String {
        switcherPanelDiagnosticsValue(
            in: elementStringValue(
                diagnosticsSummaryElement
            ),
            key: key
        )
    }

    func switcherPanelDiagnosticsValue(
        in source: String,
        key: String
    ) -> String {
        let prefix = "\(key)="
        guard
            let valueStart =
                source.range(of: prefix)?.upperBound
        else {
            return ""
        }
        let remaining = source[valueStart...]
        guard
            let valueEnd = remaining.firstIndex(of: ";")
        else {
            return String(remaining)
        }
        return String(remaining[..<valueEnd])
    }

    func switcherDiagnosticsSnapshot(
        _ diagnosticsSummary: XCUIElement,
        keys: [String]
    ) -> FlowTabUITestSwitcherDiagnosticsSnapshot {
        let exists = diagnosticsSummary.exists
        let rawValue =
            exists
                ? elementStringValue(diagnosticsSummary)
                : nil
        var values: [String: String] = [:]
        if let rawValue {
            for key in Set(keys) {
                values[key] =
                    switcherPanelDiagnosticsValue(
                        in: rawValue,
                        key: key
                    )
            }
        }
        return FlowTabUITestSwitcherDiagnosticsSnapshot(
            identifier:
                exists
                    ? diagnosticsSummary.identifier
                    : "unavailable",
            exists: exists,
            rawValue: rawValue,
            values: values
        )
    }
}

extension FlowTabUITests {
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
}
