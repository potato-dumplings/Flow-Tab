import Foundation
import XCTest

enum FlowTabUITestLogsProjectionPolicy {
    static let seededRowIdentifierPrefix =
        "flowtab.logs.line.seeded."
    static let tabNavigationWatchdog: TimeInterval = 5
    static let exactProjectionWatchdog: TimeInterval = 8
}

struct FlowTabUITestLogsProjectionSnapshot: Equatable {
    let tabContentExists: Bool
    let linesContainerExists: Bool
    let rowIdentifiers: [String]
    let selectedLevel: String?

    init(
        tabContentExists: Bool,
        linesContainerExists: Bool,
        rowIdentifiers: [String],
        selectedLevel: String? = nil
    ) {
        self.tabContentExists = tabContentExists
        self.linesContainerExists = linesContainerExists
        self.rowIdentifiers = rowIdentifiers
        self.selectedLevel = selectedLevel
    }

    var identifierCounts: [String: Int] {
        rowIdentifiers.reduce(into: [:]) {
            counts,
            identifier in
            counts[identifier, default: 0] += 1
        }
    }

    var diagnosticSummary: String {
        "tabContentExists=\(tabContentExists) "
            + "linesContainerExists=\(linesContainerExists) "
            + "selectedLevel=\(selectedLevel ?? "nil") "
            + "rowCount=\(rowIdentifiers.count) "
            + "identifierCounts="
            + "\(logsIdentifierCountSummary(identifierCounts))"
    }
}

struct FlowTabUITestLogsProjectionExpectation: Equatable {
    let rowCount: Int
    let identifierCounts: [String: Int]
    let prohibitedIdentifiers: Set<String>
    let selectedLevel: String?

    init(
        visibleIdentifiers: [String],
        hiddenIdentifiers: [String],
        selectedLevel: String? = nil
    ) {
        rowCount = visibleIdentifiers.count
        identifierCounts = visibleIdentifiers.reduce(into: [:]) {
            counts,
            identifier in
            counts[identifier, default: 0] += 1
        }
        prohibitedIdentifiers = Set(hiddenIdentifiers)
        self.selectedLevel = selectedLevel
    }

    func isSatisfied(
        by snapshot: FlowTabUITestLogsProjectionSnapshot
    ) -> Bool {
        snapshot.tabContentExists
            && snapshot.linesContainerExists
            && snapshot.rowIdentifiers.count == rowCount
            && snapshot.identifierCounts == identifierCounts
            && Set(snapshot.identifierCounts.keys)
                .isDisjoint(with: prohibitedIdentifiers)
            && (selectedLevel == nil
                || snapshot.selectedLevel == selectedLevel)
    }

    var diagnosticSummary: String {
        "rowCount=\(rowCount) "
            + "identifierCounts="
            + "\(logsIdentifierCountSummary(identifierCounts)) "
            + "prohibitedIdentifiers="
            + "\(prohibitedIdentifiers.sorted()) "
            + "selectedLevel=\(selectedLevel ?? "any")"
    }
}

private func logsIdentifierCountSummary(
    _ counts: [String: Int]
) -> String {
    counts.keys.sorted().map { identifier in
        "\(identifier)=\(counts[identifier, default: 0])"
    }
    .joined(separator: ",")
}

final class FlowTabUITestLogsProjectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestLogsProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestLogsProjectionExpectation,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        acceptsResolution: @escaping () -> Bool = {
            true
        },
        readback: @escaping () ->
            FlowTabUITestLogsProjectionSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: {
                acceptsResolution()
                    && expectation.isSatisfied(by: $0)
            },
            describe: { snapshot in
                "acceptsResolution=\(acceptsResolution()) "
                    + "expected{\(expectation.diagnosticSummary)} "
                    + "observed{\(snapshot.diagnosticSummary)}"
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestLogsProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestLogsProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestLogsProjectionSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func requestReadback(
        source: FlowTabUITestConditionObservationSource
    ) {
        conditionOwner.requestReadback(source: source)
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    func assertLogVisibility(
        at logLevel: String,
        visibleIdentifiers: [String],
        hiddenIdentifiers: [String]
    ) {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-seed-logs",
                "4",
                "--flowtab-ui-runtime-log-level",
                logLevel,
                "-showPermissionReminder",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(app)
        defer {
            if app.state == .runningForeground
                || app.state == .runningBackground
            {
                app.terminate()
            }
        }

        let expectation =
            FlowTabUITestLogsProjectionExpectation(
                visibleIdentifiers: visibleIdentifiers,
                hiddenIdentifiers: hiddenIdentifiers
            )
        let logsTabContent = element(
            in: app,
            identifier: Identifier.logsTabContent
        )
        let logsLines = element(
            in: app,
            identifier: Identifier.logsLines
        )
        let seededRows = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    FlowTabUITestLogsProjectionPolicy
                        .seededRowIdentifierPrefix
                )
            )
        var triggerDidComplete = false
        let owner =
            FlowTabUITestLogsProjectionObservationOwner(
                expectation: expectation,
                acceptsResolution: {
                    triggerDidComplete
                },
                readback: {
                    let identifiers = seededRows
                        .allElementsBoundByIndex
                        .map(\.identifier)
                    return FlowTabUITestLogsProjectionSnapshot(
                        tabContentExists:
                            logsTabContent.exists,
                        linesContainerExists:
                            logsLines.exists,
                        rowIdentifiers: identifiers
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        let didOpenLogs = tapFirstHittable(
            in: app.buttons.matching(
                identifier: Identifier.logsTabButton
            ),
            timeout:
                FlowTabUITestLogsProjectionPolicy
                    .tabNavigationWatchdog
        )
        triggerDidComplete = true
        guard didOpenLogs else {
            XCTFail(
                "Failed to open logs tab at level \(logLevel)"
            )
            return
        }

        guard
            owner.waitForResolution(
                timeout:
                    FlowTabUITestLogsProjectionPolicy
                        .exactProjectionWatchdog
            ) != nil
        else {
            XCTFail(
                "Logs projection watchdog expired at level "
                    + "\(logLevel). \(owner.diagnosticSummary)"
            )
            return
        }
    }

    func assertLogVisibilityTransition(
        in app: XCUIApplication,
        targetDescription: String,
        initialSelectedLevel: String,
        initialVisibleIdentifiers: [String],
        selectedLevel: String,
        visibleIdentifiers: [String],
        hiddenIdentifiers: [String],
        trigger: () -> Void
    ) {
        let initialExpectation =
            FlowTabUITestLogsProjectionExpectation(
                visibleIdentifiers: initialVisibleIdentifiers,
                hiddenIdentifiers: [],
                selectedLevel: initialSelectedLevel
            )
        let targetExpectation =
            FlowTabUITestLogsProjectionExpectation(
                visibleIdentifiers: visibleIdentifiers,
                hiddenIdentifiers: hiddenIdentifiers,
                selectedLevel: selectedLevel
            )
        let logsTabContent = element(
            in: app,
            identifier: Identifier.logsTabContent
        )
        let logsLines = element(
            in: app,
            identifier: Identifier.logsLines
        )
        let logsLevel = element(
            in: app,
            identifier: Identifier.logsLevel
        )
        let seededRows = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    FlowTabUITestLogsProjectionPolicy
                        .seededRowIdentifierPrefix
                )
            )
        let readback: () ->
            FlowTabUITestLogsProjectionSnapshot = {
                let levelExists = logsLevel.exists
                return FlowTabUITestLogsProjectionSnapshot(
                    tabContentExists:
                        logsTabContent.exists,
                    linesContainerExists:
                        logsLines.exists,
                    rowIdentifiers: seededRows
                        .allElementsBoundByIndex
                        .map(\.identifier),
                    selectedLevel: levelExists
                        ? self.elementStringValue(logsLevel)
                        : nil
                )
            }
        let baselineOwner =
            FlowTabUITestLogsProjectionObservationOwner(
                expectation: initialExpectation,
                readback: readback
            )
        baselineOwner.start()
        guard
            baselineOwner.waitForResolution(
                timeout:
                    FlowTabUITestLogsProjectionPolicy
                        .exactProjectionWatchdog
            ) != nil
        else {
            XCTFail(
                "Logs projection baseline watchdog expired. "
                    + "target=\(targetDescription) "
                    + baselineOwner.diagnosticSummary
            )
            baselineOwner.cancel()
            return
        }
        baselineOwner.cancel()

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
        let owner =
            FlowTabUITestLogsProjectionObservationOwner(
                expectation: targetExpectation,
                observationRegistration: {
                    readback in
                    deferredReadbacks.register(readback)
                },
                acceptsResolution: {
                    triggerDidComplete
                },
                readback: readback
            )
        owner.start()
        defer {
            owner.cancel()
            deferredReadbacks.cancel()
        }

        guard let initialEvidence = owner.latestEvidence,
              initialEvidence.source == .initialReadback,
              initialExpectation.isSatisfied(
                by: initialEvidence.value
              )
        else {
            XCTFail(
                "Logs projection initial baseline was incomplete. "
                    + "target=\(targetDescription) "
                    + "expected{\(initialExpectation.diagnosticSummary)} "
                    + owner.diagnosticSummary
            )
            return
        }
        XCTAssertNil(owner.resolvedEvidence)

        trigger()
        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        if owner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }

        XCTAssertNotNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestLogsProjectionPolicy
                        .exactProjectionWatchdog
            ),
            "Logs projection transition watchdog expired. "
                + "target=\(targetDescription) "
                + owner.diagnosticSummary
        )
    }
}
