import Foundation
import XCTest

enum FlowTabUITestSwitcherAppProjectionPolicy {
    static let postLaunchWatchdog: TimeInterval = 10
    static let runtimeOrderWatchdog: TimeInterval = 5
    static let standardFixtureProjectionWatchdog: TimeInterval = 8
    static let edgeInputsInitialProjectionWatchdog: TimeInterval = 10
    static let quitShortcutRemovalWatchdog: TimeInterval = 8
    static let quitShortcutInitialProjectionWatchdog: TimeInterval = 12
    static let openWindowMutationInitialProjectionWatchdog: TimeInterval = 12
    static let selectedWindowMutationInitialProjectionWatchdog: TimeInterval = 12
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

struct FlowTabUITestSwitcherAppProjectionReadback:
    Equatable
{
    let identifier: String
    let exists: Bool
    let rawValue: String?
    let entries: [FlowTabUITestSwitcherAppProjectionEntry]

    init(
        diagnostics:
            FlowTabUITestSwitcherDiagnosticsSnapshot
    ) {
        identifier = diagnostics.identifier
        exists = diagnostics.exists
        rawValue = diagnostics.values["apps"]
        entries = rawValue?.split(separator: "|").map {
            FlowTabUITestSwitcherAppProjectionEntry(
                rawValue: String($0)
            )
        } ?? []
    }

    init(
        snapshot:
            FlowTabUITestSwitcherAppProjectionSnapshot
    ) {
        identifier = snapshot.identifier
        exists = snapshot.exists
        rawValue = snapshot.rawValue
        entries = snapshot.entries
    }

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
    case bundleIdentifiers(required: Set<String>, excluded: Set<String>)
    case orderedBundleIdentifiers([String])

    func isSatisfied(
        by snapshot:
            FlowTabUITestSwitcherAppProjectionSnapshot
    ) -> Bool {
        guard snapshot.applicationState == .runningForeground else {
            return false
        }
        return isSatisfied(
            by: FlowTabUITestSwitcherAppProjectionReadback(
                snapshot: snapshot
            )
        )
    }

    func isSatisfied(
        by readback:
            FlowTabUITestSwitcherAppProjectionReadback
    ) -> Bool {
        guard readback.exists else { return false }
        switch self {
        case let .exactEntry(expectedEntry):
            return readback.entries.contains {
                $0.rawValue == expectedEntry
            }
        case let .bundleIdentifier(expectedBundleID):
            return readback.entries.contains {
                $0.bundleIdentifier == expectedBundleID
            }
        case let .bundleIdentifiers(required, excluded):
            let observed = Set(readback.entries.map(\.bundleIdentifier))
            return required.isSubset(of: observed)
                && observed.isDisjoint(with: excluded)
        case let .orderedBundleIdentifiers(expectedBundleIDs):
            return readback.entries.map(\.bundleIdentifier)
                == expectedBundleIDs
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
        case let .orderedBundleIdentifiers(expectedBundleIDs):
            return "orderedBundleIDs=\(expectedBundleIDs)"
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

private final class FlowTabUITestSwitcherAppRemovalState {
    var initialEvidenceSatisfied = false
    var triggerCompleted = false
}

final class FlowTabUITestSwitcherAppRemovalObservationOwner {
    private let bundleIdentifier: String
    private let expectedInitialEntry: String
    private let state: FlowTabUITestSwitcherAppRemovalState
    private let deferredReadbacks:
        FlowTabUITestDeferredConditionReadbackRegistration
    private let projection:
        FlowTabUITestSwitcherAppProjectionObservationOwner
    private let rowRepresentationCount: () -> Int
    private let rowExists: () -> Bool

    init(
        bundleIdentifier: String,
        expectedInitialWindowCount: Int,
        scheduledRegistration:
            @escaping FlowTabUITestConditionObservationRegistration =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        projectionReadback: @escaping () ->
            FlowTabUITestSwitcherAppProjectionSnapshot,
        rowRepresentationCount: @escaping () -> Int,
        rowExists: @escaping () -> Bool
    ) {
        let state = FlowTabUITestSwitcherAppRemovalState()
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration: scheduledRegistration
            )
        self.bundleIdentifier = bundleIdentifier
        expectedInitialEntry =
            "\(bundleIdentifier):\(expectedInitialWindowCount)"
        self.state = state
        self.deferredReadbacks = deferredReadbacks
        self.rowRepresentationCount = rowRepresentationCount
        self.rowExists = rowExists
        projection =
            FlowTabUITestSwitcherAppProjectionObservationOwner(
                expectation:
                    .bundleIdentifiers(
                        required: [],
                        excluded: [bundleIdentifier]
                    ),
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                acceptsResolution: {
                    state.initialEvidenceSatisfied
                        && state.triggerCompleted
                        && !rowExists()
                },
                readback: projectionReadback
            )
    }

    func start() -> Bool {
        state.initialEvidenceSatisfied = false
        state.triggerCompleted = false
        projection.start()
        guard
            let initialEvidence = projection.latestEvidence,
            initialEvidence.source == .initialReadback
        else {
            return false
        }
        let initialProjectionMatches =
            FlowTabUITestSwitcherAppProjectionExpectation
                .exactEntry(expectedInitialEntry)
                .isSatisfied(by: initialEvidence.value)
        state.initialEvidenceSatisfied =
            initialProjectionMatches && rowExists()
        return state.initialEvidenceSatisfied
    }

    func markTriggerCompleted() {
        guard
            state.initialEvidenceSatisfied,
            !state.triggerCompleted
        else {
            return
        }
        state.triggerCompleted = true
        projection.requestReadback(source: .triggerReadback)
        if projection.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestSwitcherAppProjectionSnapshot
    >? {
        projection.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSwitcherAppProjectionSnapshot
    >? {
        projection.resolvedEvidence
    }

    var diagnosticSummary: String {
        "bundleID=\(bundleIdentifier) "
            + "expectedInitialEntry=\(expectedInitialEntry) "
            + "initialEvidenceSatisfied="
            + "\(state.initialEvidenceSatisfied) "
            + "triggerCompleted=\(state.triggerCompleted) "
            + "finalRepresentationCount="
            + "\(rowRepresentationCount()) "
            + "finalExists=\(rowExists()) "
            + projection.diagnosticSummary
    }

    func cancel() {
        projection.cancel()
        deferredReadbacks.cancel()
        state.initialEvidenceSatisfied = false
        state.triggerCompleted = false
    }

    deinit {
        cancel()
    }
}

extension FlowTabUITests {
    func switcherAppRowIdentifier(_ bundleIdentifier: String) -> String {
        Identifier.switcherAppPrefix
            + bundleIdentifier.flowTabUITestAccessibilityIdentifierComponent
    }

    func assertCurrentSwitcherAppProjection(
        in app: XCUIApplication,
        exactEntry: String,
        timeout: TimeInterval
    ) -> Bool {
        let expectedEntry =
            FlowTabUITestSwitcherAppProjectionEntry(
                rawValue: exactEntry
            )
        guard
            !expectedEntry.bundleIdentifier.isEmpty,
            expectedEntry.windowCount != nil
        else {
            XCTFail(
                "Switcher App projection target was invalid. "
                    + expectedEntry.diagnosticSummary
            )
            return false
        }

        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        let rowIdentifier = switcherAppRowIdentifier(
            expectedEntry.bundleIdentifier
        )
        let rowRepresentations = app.descendants(matching: .any)
            .matching(identifier: rowIdentifier)
        let row = rowRepresentations.firstMatch
        let owner =
            FlowTabUITestSwitcherAppProjectionObservationOwner(
                expectation: .exactEntry(exactEntry),
                acceptsResolution: {
                    row.exists
                },
                readback: {
                    self.switcherAppProjectionSnapshot(
                        in: app,
                        diagnosticsSummaryElement:
                            diagnosticsSummary
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        guard owner.waitForResolution(timeout: timeout) != nil
        else {
            XCTFail(
                "Current Switcher App projection watchdog expired. "
                    + "rowIdentifier=\(rowIdentifier) "
                    + "finalRepresentationCount=\(rowRepresentations.count) "
                    + "finalExists=\(row.exists) "
                    + owner.diagnosticSummary
            )
            return false
        }

        guard row.exists else {
            XCTFail(
                "Current Switcher App row disagreed with the projection. "
                    + "identifier=\(rowIdentifier) "
                    + "representationCount=\(rowRepresentations.count) "
                    + "finalExists=\(row.exists) "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }

    func startSwitcherAppRemovalObservation(
        in app: XCUIApplication,
        bundleIdentifier: String,
        expectedInitialWindowCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> FlowTabUITestSwitcherAppRemovalObservationOwner? {
        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        let rowIdentifier = switcherAppRowIdentifier(
            bundleIdentifier
        )
        let rowRepresentations = {
            app.descendants(matching: .any)
                .matching(identifier: rowIdentifier)
        }
        let owner =
            FlowTabUITestSwitcherAppRemovalObservationOwner(
                bundleIdentifier: bundleIdentifier,
                expectedInitialWindowCount:
                    expectedInitialWindowCount,
                projectionReadback: {
                    self.switcherAppProjectionSnapshot(
                        in: app,
                        diagnosticsSummaryElement:
                            diagnosticsSummary
                    )
                },
                rowRepresentationCount: {
                    rowRepresentations().count
                },
                rowExists: {
                    rowRepresentations().firstMatch.exists
                }
            )
        guard owner.start() else {
            XCTFail(
                "Switcher App removal baseline was unavailable. "
                    + owner.diagnosticSummary,
                file: file,
                line: line
            )
            owner.cancel()
            return nil
        }
        return owner
    }

    func assertSwitcherAppRemoved(
        _ observation:
            FlowTabUITestSwitcherAppRemovalObservationOwner,
        timeout: TimeInterval,
        description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard observation.waitForResolution(timeout: timeout) != nil
        else {
            XCTFail(
                "\(description) watchdog expired. "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return
        }
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

    func performAndWaitForSwitcherAppProjection(
        _ diagnosticsSummaryElement: XCUIElement,
        expectation:
            FlowTabUITestSwitcherAppProjectionExpectation,
        timeout: TimeInterval,
        trigger: () -> Void
    ) -> Bool {
        var triggerCompleted = false
        let owner = FlowTabUITestSwitcherAppProjectionObservationOwner(
            expectation: expectation,
            acceptsResolution: { triggerCompleted },
            readback: {
                self.switcherAppProjectionSnapshot(
                    diagnosticsSummaryElement
                )
            }
        )
        owner.start()
        defer { owner.cancel() }

        trigger()
        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)

        guard owner.waitForResolution(timeout: timeout) != nil else {
            XCTFail(
                "Switcher app projection watchdog expired. "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
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
            identifier: Identifier.switcherSummary,
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
