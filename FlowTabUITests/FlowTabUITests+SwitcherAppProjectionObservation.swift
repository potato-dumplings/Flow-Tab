import Foundation
import XCTest

enum FlowTabUITestSwitcherAppProjectionPolicy {
    static let postLaunchWatchdog: TimeInterval = 10
}

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
    let applicationState: XCUIApplication.State
    let identifier: String
    let exists: Bool
    let rawValue: String?
    let entries: [FlowTabUITestSwitcherAppProjectionEntry]

    var diagnosticSummary: String {
        let entrySummary = entries
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.diagnosticSummary)
            .joined(separator: " | ")
        return "applicationState=\(String(describing: applicationState)) "
            + "identifier=\(identifier) "
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
    case bundleIdentifiers(required: Set<String>, excluded: Set<String>)

    func isSatisfied(
        by snapshot:
            FlowTabUITestSwitcherAppProjectionSnapshot
    ) -> Bool {
        guard
            snapshot.applicationState == .runningForeground,
            snapshot.exists
        else {
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
        case let .bundleIdentifiers(required, excluded):
            let observed = Set(snapshot.entries.map(\.bundleIdentifier))
            return required.isSubset(of: observed)
                && observed.isDisjoint(with: excluded)
        }
    }

    var diagnosticSummary: String {
        switch self {
        case let .exactEntry(expectedEntry):
            return "exactEntry=\(expectedEntry)"
        case let .bundleIdentifier(expectedBundleID):
            return "bundleID=\(expectedBundleID)"
        case let .bundleIdentifiers(required, excluded):
            return "requiredBundleIDs=\(required.sorted()) "
                + "excludedBundleIDs=\(excluded.sorted())"
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
        acceptsResolution: @escaping () -> Bool = { true },
        readback: @escaping () ->
            FlowTabUITestSwitcherAppProjectionSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: {
                acceptsResolution()
                    && expectation.isSatisfied(by: $0)
            },
            describe: { snapshot in
                "expected{\(expectation.diagnosticSummary)} "
                    + "acceptsResolution=\(acceptsResolution()) "
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

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSwitcherAppProjectionSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func requestReadback(source: FlowTabUITestConditionObservationSource) {
        conditionOwner.requestReadback(source: source)
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    func assertInitialSwitcherAppProjectionAfterLaunch(
        in app: XCUIApplication,
        requiredBundleIdentifiers: Set<String>,
        excludedBundleIdentifiers: Set<String>,
        targetDescription: String,
        trigger: () -> Void
    ) -> Bool {
        guard
            !requiredBundleIdentifiers.isEmpty,
            requiredBundleIdentifiers.isDisjoint(
                with: excludedBundleIdentifiers
            )
        else {
            XCTFail(
                "Switcher App projection target identity was invalid. "
                    + "target=\(targetDescription) "
                    + "required=\(requiredBundleIdentifiers.sorted()) "
                    + "excluded=\(excludedBundleIdentifiers.sorted())"
            )
            return false
        }

        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration:
                    FlowTabUITestConditionReadbackScheduler
                        .mainRunLoopRegistration(
                            cadence:
                                FlowTabUITestConditionObservationPolicy
                                    .xcuiReadbackCadence
                        )
            )
        var triggerDidComplete = false
        let owner = FlowTabUITestSwitcherAppProjectionObservationOwner(
            expectation: .bundleIdentifiers(
                required: requiredBundleIdentifiers,
                excluded: excludedBundleIdentifiers
            ),
            observationRegistration: { callback in
                deferredReadbacks.register(callback)
            },
            acceptsResolution: { triggerDidComplete },
            readback: {
                self.switcherAppProjectionSnapshot(
                    in: app,
                    diagnosticsSummaryElement: diagnosticsSummary
                )
            }
        )
        owner.start()
        defer {
            owner.cancel()
            deferredReadbacks.cancel()
        }

        guard owner.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "Switcher App projection initial readback was unavailable. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }

        trigger()
        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        if owner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }
        guard owner.waitForResolution(
            timeout: FlowTabUITestSwitcherAppProjectionPolicy
                .postLaunchWatchdog
        ) != nil else {
            XCTFail(
                "Switcher App projection watchdog expired. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return false
        }

        let requiredRowIdentifiers = Set(
            requiredBundleIdentifiers.map(switcherAppRowIdentifier)
        )
        let excludedRowIdentifiers = Set(
            excludedBundleIdentifiers.map(switcherAppRowIdentifier)
        )
        let targetRowIdentifiers =
            requiredRowIdentifiers.union(excludedRowIdentifiers)
        let visibleTargetRowIdentifiers = Set(
            app.descendants(matching: .any)
                .matching(
                    NSPredicate(
                        format: "identifier IN %@",
                        targetRowIdentifiers.sorted()
                    )
                )
                .allElementsBoundByIndex
                .map(\.identifier)
        )
        guard
            requiredRowIdentifiers.isSubset(
                of: visibleTargetRowIdentifiers
            ),
            visibleTargetRowIdentifiers.isDisjoint(
                with: excludedRowIdentifiers
            )
        else {
            XCTFail(
                "Switcher App rows disagreed with the committed projection. "
                    + "target=\(targetDescription) "
                    + "requiredRows=\(requiredRowIdentifiers.sorted()) "
                    + "excludedRows=\(excludedRowIdentifiers.sorted()) "
                    + "visibleTargetRows=\(visibleTargetRowIdentifiers.sorted()) "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    func switcherAppRowIdentifier(_ bundleIdentifier: String) -> String {
        Identifier.switcherAppPrefix
            + bundleIdentifier.flowTabUITestAccessibilityIdentifierComponent
    }

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
            applicationState: .runningForeground,
            identifier: diagnosticsSummaryElement.identifier,
            exists: exists,
            rawValue: rawValue,
            entries: entries
        )
    }

    private func switcherAppProjectionSnapshot(
        in app: XCUIApplication,
        diagnosticsSummaryElement: XCUIElement
    ) -> FlowTabUITestSwitcherAppProjectionSnapshot {
        let applicationState = app.state
        guard applicationState == .runningForeground else {
            return FlowTabUITestSwitcherAppProjectionSnapshot(
                applicationState: applicationState,
                identifier: Identifier.switcherSummary,
                exists: false,
                rawValue: nil,
                entries: []
            )
        }
        let snapshot = switcherAppProjectionSnapshot(
            diagnosticsSummaryElement
        )
        return FlowTabUITestSwitcherAppProjectionSnapshot(
            applicationState: applicationState,
            identifier: snapshot.identifier,
            exists: snapshot.exists,
            rawValue: snapshot.rawValue,
            entries: snapshot.entries
        )
    }
}
