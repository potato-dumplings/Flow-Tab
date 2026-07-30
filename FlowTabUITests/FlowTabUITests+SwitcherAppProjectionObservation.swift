import Foundation
import XCTest

struct FlowTabUITestSwitcherAppProjectionEntry: Equatable {
    let rawValue: String
    let bundleIdentifier: String
    let windowCount: Int?

    init(rawValue: String) {
        self.rawValue = rawValue
        let fields = rawValue.split(
            separator: ":",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        bundleIdentifier =
            fields.first.map(String.init) ?? ""
        windowCount =
            fields.dropFirst().first.flatMap {
                Int($0)
            }
    }

    var diagnosticSummary: String {
        "raw=\(rawValue) "
            + "bundleID=\(bundleIdentifier) "
            + "windowCount=\(windowCount.map(String.init) ?? "nil")"
    }
}

struct FlowTabUITestSwitcherAppProjectionSnapshot:
    Equatable
{
    let identifier: String
    let exists: Bool
    let rawValue: String?
    let entries: [FlowTabUITestSwitcherAppProjectionEntry]

    var diagnosticSummary: String {
        let entrySummary = entries
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.diagnosticSummary)
            .joined(separator: " | ")
        return "identifier=\(identifier) "
            + "exists=\(exists) "
            + "entries=[\(entrySummary)] "
            + "raw=\(rawValue ?? "nil")"
    }
}

enum FlowTabUITestSwitcherAppProjectionExpectation:
    Equatable
{
    case exactEntry(String)
    case bundleIdentifier(String)

    func isSatisfied(
        by snapshot:
            FlowTabUITestSwitcherAppProjectionSnapshot
    ) -> Bool {
        guard snapshot.exists else {
            return false
        }
        switch self {
        case let .exactEntry(expectedEntry):
            return snapshot.entries.contains {
                $0.rawValue == expectedEntry
            }
        case let .bundleIdentifier(expectedBundleID):
            return snapshot.entries.contains {
                $0.bundleIdentifier == expectedBundleID
            }
        }
    }

    var diagnosticSummary: String {
        switch self {
        case let .exactEntry(expectedEntry):
            return "exactEntry=\(expectedEntry)"
        case let .bundleIdentifier(expectedBundleID):
            return "bundleID=\(expectedBundleID)"
        }
    }
}

final class FlowTabUITestSwitcherAppProjectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSwitcherAppProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestSwitcherAppProjectionExpectation,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestSwitcherAppProjectionSnapshot
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
        FlowTabUITestSwitcherAppProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSwitcherAppProjectionSnapshot
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
    func waitForSwitcherAppsSummary(
        _ diagnosticsSummaryElement: XCUIElement,
        toContain expectedEntry: String,
        timeout: TimeInterval
    ) -> Bool {
        waitForSwitcherAppProjection(
            diagnosticsSummaryElement,
            expectation: .exactEntry(expectedEntry),
            timeout: timeout
        )
    }

    func waitForSwitcherAppEntry(
        _ diagnosticsSummaryElement: XCUIElement,
        bundleIdentifier: String,
        timeout: TimeInterval
    ) -> Bool {
        waitForSwitcherAppProjection(
            diagnosticsSummaryElement,
            expectation:
                .bundleIdentifier(bundleIdentifier),
            timeout: timeout
        )
    }

    private func waitForSwitcherAppProjection(
        _ diagnosticsSummaryElement: XCUIElement,
        expectation:
            FlowTabUITestSwitcherAppProjectionExpectation,
        timeout: TimeInterval
    ) -> Bool {
        let owner =
            FlowTabUITestSwitcherAppProjectionObservationOwner(
                expectation: expectation,
                readback: {
                    self.switcherAppProjectionSnapshot(
                        diagnosticsSummaryElement
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        guard
            owner.waitForResolution(timeout: timeout) != nil
        else {
            XCTFail(
                "Switcher app projection watchdog expired. "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    private func switcherAppProjectionSnapshot(
        _ diagnosticsSummaryElement: XCUIElement
    ) -> FlowTabUITestSwitcherAppProjectionSnapshot {
        let exists = diagnosticsSummaryElement.exists
        let rawValue =
            exists
                ? switcherPanelDiagnosticsValue(
                    diagnosticsSummaryElement,
                    key: "apps"
                )
                : nil
        let entries =
            rawValue?.split(separator: "|").map {
                FlowTabUITestSwitcherAppProjectionEntry(
                    rawValue: String($0)
                )
            } ?? []
        return FlowTabUITestSwitcherAppProjectionSnapshot(
            identifier: diagnosticsSummaryElement.identifier,
            exists: exists,
            rawValue: rawValue,
            entries: entries
        )
    }
}
