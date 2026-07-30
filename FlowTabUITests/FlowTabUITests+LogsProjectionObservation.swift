import Foundation
import XCTest

private enum FlowTabUITestLogsProjectionPolicy {
    static let seededRowIdentifierPrefix =
        "flowtab.logs.line.seeded."
}

struct FlowTabUITestLogsProjectionSnapshot: Equatable {
    let tabContentExists: Bool
    let linesContainerExists: Bool
    let rowIdentifiers: [String]

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
            + "rowCount=\(rowIdentifiers.count) "
            + "identifierCounts="
            + "\(logsIdentifierCountSummary(identifierCounts))"
    }
}

struct FlowTabUITestLogsProjectionExpectation: Equatable {
    let rowCount: Int
    let identifierCounts: [String: Int]
    let prohibitedIdentifiers: Set<String>

    init(
        visibleIdentifiers: [String],
        hiddenIdentifiers: [String]
    ) {
        rowCount = visibleIdentifiers.count
        identifierCounts = visibleIdentifiers.reduce(into: [:]) {
            counts,
            identifier in
            counts[identifier, default: 0] += 1
        }
        prohibitedIdentifiers = Set(hiddenIdentifiers)
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
    }

    var diagnosticSummary: String {
        "rowCount=\(rowCount) "
            + "identifierCounts="
            + "\(logsIdentifierCountSummary(identifierCounts)) "
            + "prohibitedIdentifiers="
            + "\(prohibitedIdentifiers.sorted())"
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

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
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
            timeout: 5
        )
        triggerDidComplete = true
        guard didOpenLogs else {
            XCTFail(
                "Failed to open logs tab at level \(logLevel)"
            )
            return
        }

        guard owner.waitForResolution(timeout: 8) != nil else {
            XCTFail(
                "Logs projection watchdog expired at level "
                    + "\(logLevel). \(owner.diagnosticSummary)"
            )
            return
        }
    }
}
