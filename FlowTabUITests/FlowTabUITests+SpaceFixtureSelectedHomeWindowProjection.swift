import Foundation
import XCTest

enum FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionPolicy {
    static let appSelectionTriggerWatchdog: TimeInterval = 8
    static let perVisibleTitleProjectionWatchdog: TimeInterval = 12
    static let excludedTitleProjectionWatchdog: TimeInterval = 12

    static func watchdog(visibleTitleCount: Int) -> TimeInterval {
        let exactProjectionGroupCount = max(visibleTitleCount, 1)
        return appSelectionTriggerWatchdog
            + perVisibleTitleProjectionWatchdog
                * TimeInterval(exactProjectionGroupCount)
            + excludedTitleProjectionWatchdog
    }
}

struct FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionSnapshot:
    Equatable
{
    struct Row: Equatable {
        let identifier: String
        let label: String
        let value: String

        func belongs(to appID: String) -> Bool {
            value.split(whereSeparator: \.isWhitespace).contains {
                $0 == appID
            }
        }

        var diagnosticSummary: String {
            "\(identifier){label=\(label),value=\(value)}"
        }
    }

    let applicationState: XCUIApplication.State
    let windowCountLabelBeforeRows: String?
    let rows: [Row]
    let windowCountLabelAfterRows: String?

    static func count(from label: String?) -> Int? {
        guard let label else { return nil }
        let numberRuns = label.split { !$0.isNumber }
        guard numberRuns.count == 1 else { return nil }
        return Int(String(numberRuns[0]))
    }

    var diagnosticSummary: String {
        let rowSummary = rows
            .map(\.diagnosticSummary)
            .joined(separator: ",")
        return "applicationState=\(String(describing: applicationState)) "
            + "countBefore=\(String(reflecting: windowCountLabelBeforeRows)) "
            + "rows=[\(rowSummary)] "
            + "countAfter=\(String(reflecting: windowCountLabelAfterRows))"
    }
}

struct FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionExpectation:
    Equatable
{
    let selectedBundleIdentifier: String
    let expectedRowCount: Int
    let visibleTitles: [String]
    let excludedTitles: [String]

    var isWellFormed: Bool {
        let allTitles = visibleTitles + excludedTitles
        return !selectedBundleIdentifier.isEmpty
            && expectedRowCount > 0
            && expectedRowCount >= visibleTitles.count
            && !allTitles.isEmpty
            && allTitles.allSatisfy { !$0.isEmpty }
            && Set(allTitles).count == allTitles.count
    }

    func isSatisfied(
        by snapshot:
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionSnapshot
    ) -> Bool {
        let countBefore =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionSnapshot
                .count(from: snapshot.windowCountLabelBeforeRows)
        let countAfter =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionSnapshot
                .count(from: snapshot.windowCountLabelAfterRows)
        let identifiers = snapshot.rows.map(\.identifier)
        let labels = snapshot.rows.map(\.label)
        guard isWellFormed,
              snapshot.applicationState == .runningForeground,
              countBefore == expectedRowCount,
              countAfter == expectedRowCount,
              snapshot.rows.count == expectedRowCount,
              identifiers.allSatisfy({ !$0.isEmpty }),
              Set(identifiers).count == identifiers.count,
              visibleTitles.allSatisfy({ labels.contains($0) }),
              excludedTitles.allSatisfy({ !labels.contains($0) })
        else {
            return false
        }
        return snapshot.rows.allSatisfy {
            $0.belongs(to: selectedBundleIdentifier)
        }
    }

    var diagnosticSummary: String {
        "selectedBundleIdentifier=\(selectedBundleIdentifier) "
            + "expectedRowCount=\(expectedRowCount) "
            + "visibleTitles=\(visibleTitles) "
            + "excludedTitles=\(excludedTitles)"
    }
}

private enum FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionPhase:
    String
{
    case initialReadback
    case awaitingSelectionTrigger
    case selectionTriggerCompleted
}

private final class
    FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionState
{
    var phase:
        FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionPhase =
            .initialReadback

    var acceptsEvidence: Bool {
        phase != .awaitingSelectionTrigger
    }
}

final class
    FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionObservationOwner
{
    private let expectation:
        FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionExpectation
    private let state:
        FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionState
    private let deferredReadbacks:
        FlowTabUITestDeferredConditionReadbackRegistration
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionExpectation,
        scheduledRegistration:
            @escaping FlowTabUITestConditionObservationRegistration =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionSnapshot
    ) {
        let state =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionState()
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration: scheduledRegistration
            )
        self.expectation = expectation
        self.state = state
        self.deferredReadbacks = deferredReadbacks
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: { callback in
                deferredReadbacks.register(callback)
            },
            readback: readback,
            isSatisfied: { snapshot in
                state.acceptsEvidence
                    && expectation.isSatisfied(by: snapshot)
            },
            describe: { snapshot in
                "phase=\(state.phase.rawValue) "
                    + "expected{\(expectation.diagnosticSummary)} "
                    + snapshot.diagnosticSummary
            }
        )
    }

    func start() {
        state.phase = .initialReadback
        conditionOwner.start()
        if conditionOwner.resolvedEvidence == nil {
            state.phase = .awaitingSelectionTrigger
        }
    }

    func markSelectionTriggerCompleted() {
        guard conditionOwner.resolvedEvidence == nil,
              state.phase != .selectionTriggerCompleted
        else {
            return
        }
        state.phase = .selectionTriggerCompleted
        conditionOwner.requestReadback(source: .triggerReadback)
        if conditionOwner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
        deferredReadbacks.cancel()
    }

    deinit {
        cancel()
    }
}

extension FlowTabUITests {
    @discardableResult
    func selectSpaceFixtureHomeAppAndWaitForExactWindowProjection(
        _ workflowApp: SpaceFixtureResolvedWorkflow.App,
        in workflow: SpaceFixtureResolvedWorkflow,
        app: XCUIApplication
    ) -> FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionSnapshot? {
        let expectation =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionExpectation(
                selectedBundleIdentifier:
                    workflowApp.identity.bundleIdentifier,
                expectedRowCount: workflowApp.windowCount,
                visibleTitles: workflowApp.expectedHomeWindowTitles,
                excludedTitles:
                    workflow.otherExpectedHomeWindowTitles(
                        excluding: workflowApp.appID
                    )
            )
        guard expectation.isWellFormed else {
            XCTFail(
                "Space Fixture selected Home window projection expectation "
                    + "is invalid. \(expectation.diagnosticSummary)"
            )
            return nil
        }

        let windowCount = element(
            in: app,
            identifier: Identifier.homeWindowCount
        )
        let observation =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionObservationOwner(
                expectation: expectation,
                readback: {
                    let applicationState = app.state
                    guard applicationState == .runningForeground else {
                        return .init(
                            applicationState: applicationState,
                            windowCountLabelBeforeRows: nil,
                            rows: [],
                            windowCountLabelAfterRows: nil
                        )
                    }
                    let countBefore = windowCount.exists
                        ? windowCount.label
                        : nil
                    let rows = self.homeWindowRows(in: app).map {
                        FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionSnapshot.Row(
                            identifier: $0.identifier,
                            label: $0.label,
                            value: self.elementStringValue($0)
                        )
                    }
                    let countAfter = windowCount.exists
                        ? windowCount.label
                        : nil
                    return .init(
                        applicationState: applicationState,
                        windowCountLabelBeforeRows: countBefore,
                        rows: rows,
                        windowCountLabelAfterRows: countAfter
                    )
                }
            )
        observation.start()
        defer { observation.cancel() }

        guard observation.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "Space Fixture selected Home window projection initial "
                    + "readback was unavailable. "
                    + observation.diagnosticSummary
            )
            return nil
        }
        if let initialEvidence = observation.resolvedEvidence {
            return initialEvidence.value
        }

        let watchdog =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionPolicy
                .watchdog(
                    visibleTitleCount:
                        workflowApp.expectedHomeWindowTitles.count
                )
        let budget = FlowTabUITestHomeAppSelectionWatchdogBudget(
            timeout: watchdog
        )
        let homeRow = app.buttons
            .matching(
                identifier:
                    workflowApp.identity.homeAppAccessibilityIdentifier
            )
            .firstMatch
        let appList = app.scrollViews
            .matching(identifier: Identifier.homeAppList)
            .firstMatch
        guard tapElementAfterScrollingIntoView(
            homeRow,
            in: appList,
            fallbackScrollContainers:
                app.scrollViews.allElementsBoundByIndex,
            timeout: min(
                FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionPolicy
                    .appSelectionTriggerWatchdog,
                budget.remaining
            )
        ) else {
            XCTFail(
                "Space Fixture Home App selection trigger watchdog expired. "
                    + observation.diagnosticSummary
            )
            return nil
        }

        observation.markSelectionTriggerCompleted()
        guard let evidence = observation.waitForResolution(
            timeout: budget.remaining
        ) else {
            XCTFail(
                "Space Fixture selected Home window projection watchdog "
                    + "expired. "
                    + observation.diagnosticSummary
            )
            return nil
        }
        return evidence.value
    }
}
