import Foundation
import XCTest

enum FlowTabUITestSpaceFixtureHomeAppInventoryPolicy {
    static let perAppCompatibilityWatchdog: TimeInterval = 20

    static func watchdog(appCount: Int) -> TimeInterval {
        perAppCompatibilityWatchdog * TimeInterval(max(appCount, 1))
    }
}

struct FlowTabUITestSpaceFixtureHomeAppInventorySnapshot: Equatable {
    struct Row: Equatable {
        let identifier: String
        let exists: Bool
        let value: String?

        init(
            identifier: String,
            exists: Bool = true,
            value: String?
        ) {
            self.identifier = identifier
            self.exists = exists
            self.value = value
        }
    }

    let applicationState: XCUIApplication.State
    let appCountLabelBeforeRows: String?
    let totalVisibleRowCount: Int
    let visibleRows: [Row]
    let appCountLabelAfterRows: String?

    init(
        applicationState: XCUIApplication.State,
        appCountLabelBeforeRows: String?,
        totalVisibleRowCount: Int? = nil,
        visibleRows: [Row],
        appCountLabelAfterRows: String?
    ) {
        self.applicationState = applicationState
        self.appCountLabelBeforeRows = appCountLabelBeforeRows
        self.totalVisibleRowCount =
            totalVisibleRowCount
                ?? visibleRows.filter(\.exists).count
        self.visibleRows = visibleRows
        self.appCountLabelAfterRows = appCountLabelAfterRows
    }

    static func appCount(from label: String?) -> Int? {
        guard let label else { return nil }
        let numberRuns = label.split { !$0.isNumber }
        guard numberRuns.count == 1 else { return nil }
        return Int(String(numberRuns[0]))
    }

    var diagnosticSummary: String {
        let visibleSummary = visibleRows.map {
            "\($0.identifier){exists=\($0.exists ? 1 : 0),"
                + "value=\(String(reflecting: $0.value))}"
        }.joined(separator: ",")
        return "applicationState=\(String(describing: applicationState)) "
            + "countBefore=\(String(reflecting: appCountLabelBeforeRows)) "
            + "totalVisibleRowCount=\(totalVisibleRowCount) "
            + "visible=[\(visibleSummary)] "
            + "countAfter=\(String(reflecting: appCountLabelAfterRows))"
    }
}

struct FlowTabUITestSpaceFixtureHomeAppInventoryExpectation: Equatable {
    struct Row: Equatable {
        let identifier: String
        let value: String
    }

    let visibleRows: [Row]

    var isWellFormed: Bool {
        let visibleIdentifiers = visibleRows.map(\.identifier)
        return !visibleRows.isEmpty
            && visibleIdentifiers.allSatisfy { !$0.isEmpty }
            && visibleRows.allSatisfy { !$0.value.isEmpty }
            && Set(visibleIdentifiers).count == visibleIdentifiers.count
    }

    func isSatisfied(
        by snapshot: FlowTabUITestSpaceFixtureHomeAppInventorySnapshot
    ) -> Bool {
        let expectedIdentifiers = visibleRows.map(\.identifier)
        let actualIdentifiers = snapshot.visibleRows.map(\.identifier)
        let countBefore = Self.count(
            in: snapshot.appCountLabelBeforeRows
        )
        let countAfter = Self.count(
            in: snapshot.appCountLabelAfterRows
        )
        guard isWellFormed,
              snapshot.applicationState == .runningForeground,
              countBefore == snapshot.totalVisibleRowCount,
              countAfter == snapshot.totalVisibleRowCount,
              snapshot.totalVisibleRowCount >= visibleRows.count,
              actualIdentifiers.count == visibleRows.count,
              Set(actualIdentifiers).count == actualIdentifiers.count,
              Set(actualIdentifiers) == Set(expectedIdentifiers)
        else {
            return false
        }

        let rowsByIdentifier = Dictionary(
            uniqueKeysWithValues: snapshot.visibleRows.map {
                ($0.identifier, $0)
            }
        )
        return visibleRows.allSatisfy { expected in
            guard let actual = rowsByIdentifier[expected.identifier] else {
                return false
            }
            return actual.exists && actual.value == expected.value
        }
    }

    var diagnosticSummary: String {
        let visibleSummary = visibleRows.map {
            "\($0.identifier)=\($0.value)"
        }.joined(separator: ",")
        return "visible=[\(visibleSummary)] "
            + "expectedWorkflowCount=\(visibleRows.count)"
    }

    private static func count(in label: String?) -> Int? {
        FlowTabUITestSpaceFixtureHomeAppInventorySnapshot.appCount(
            from: label
        )
    }
}

private enum FlowTabUITestSpaceFixtureHomeAppInventoryPhase: String {
    case initialReadback
    case awaitingHomeNavigation
    case homeNavigationCompleted
}

private final class FlowTabUITestSpaceFixtureHomeAppInventoryState {
    var phase: FlowTabUITestSpaceFixtureHomeAppInventoryPhase =
        .initialReadback

    var acceptsEvidence: Bool {
        phase == .homeNavigationCompleted
    }
}

final class FlowTabUITestSpaceFixtureHomeAppInventoryObservationOwner {
    private let expectation:
        FlowTabUITestSpaceFixtureHomeAppInventoryExpectation
    private let state: FlowTabUITestSpaceFixtureHomeAppInventoryState
    private let deferredReadbacks:
        FlowTabUITestDeferredConditionReadbackRegistration
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSpaceFixtureHomeAppInventorySnapshot
        >

    init(
        expectation:
            FlowTabUITestSpaceFixtureHomeAppInventoryExpectation,
        scheduledRegistration:
            @escaping FlowTabUITestConditionObservationRegistration =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestSpaceFixtureHomeAppInventorySnapshot
    ) {
        let state = FlowTabUITestSpaceFixtureHomeAppInventoryState()
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
                    + snapshot.diagnosticSummary
            }
        )
    }

    func start() {
        state.phase = .initialReadback
        conditionOwner.start()
        state.phase = .awaitingHomeNavigation
    }

    func markHomeNavigationCompleted() {
        guard state.phase != .homeNavigationCompleted,
              conditionOwner.resolvedEvidence == nil
        else {
            return
        }
        state.phase = .homeNavigationCompleted
        conditionOwner.requestReadback(source: .triggerReadback)
        if conditionOwner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestSpaceFixtureHomeAppInventorySnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSpaceFixtureHomeAppInventorySnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSpaceFixtureHomeAppInventorySnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        "expected{\(expectation.diagnosticSummary)} "
            + conditionOwner.diagnosticSummary
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
    func waitForSpaceFixtureHomeAppInventoryAfterNavigation(
        _ workflow: SpaceFixtureResolvedWorkflow,
        in app: XCUIApplication
    ) -> FlowTabUITestSpaceFixtureHomeAppInventorySnapshot? {
        let visibleApps = workflow.apps
        let expectation =
            FlowTabUITestSpaceFixtureHomeAppInventoryExpectation(
                visibleRows: visibleApps.map {
                    .init(
                        identifier:
                            $0.identity.homeAppAccessibilityIdentifier,
                        value: "\($0.windowCount)w"
                    )
                }
            )
        guard expectation.isWellFormed else {
            XCTFail(
                "Space Fixture Home App inventory expectation is invalid. "
                    + expectation.diagnosticSummary
            )
            return nil
        }

        let appCount = element(
            in: app,
            identifier: Identifier.homeAppCount
        )
        let allHomeRows = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "flowtab.home.app."
            )
        )
        let expectedRows = expectation.visibleRows.map {
            FlowTabUITestHomeAppRowProjectionElement(
                identifier: $0.identifier,
                element: element(in: app, identifier: $0.identifier)
            )
        }
        let observation =
            FlowTabUITestSpaceFixtureHomeAppInventoryObservationOwner(
                expectation: expectation,
                readback: {
                    let applicationState = app.state
                    guard applicationState == .runningForeground else {
                        return .init(
                            applicationState: applicationState,
                            appCountLabelBeforeRows: nil,
                            totalVisibleRowCount: 0,
                            visibleRows: expectedRows.map {
                                .init(
                                    identifier: $0.identifier,
                                    exists: false,
                                    value: nil
                                )
                            },
                            appCountLabelAfterRows: nil
                        )
                    }
                    let countBefore = appCount.exists
                        ? appCount.label
                        : nil
                    let totalVisibleRowCount = allHomeRows.count
                    let visibleRows = expectedRows.map {
                        let exists = $0.element.exists
                        return FlowTabUITestSpaceFixtureHomeAppInventorySnapshot.Row(
                            identifier: $0.identifier,
                            exists: exists,
                            value: exists
                                ? self.elementStringValue($0.element)
                                : nil
                        )
                    }
                    let countAfter = appCount.exists
                        ? appCount.label
                        : nil
                    return .init(
                        applicationState: applicationState,
                        appCountLabelBeforeRows: countBefore,
                        totalVisibleRowCount: totalVisibleRowCount,
                        visibleRows: visibleRows,
                        appCountLabelAfterRows: countAfter
                    )
                }
            )
        observation.start()
        defer { observation.cancel() }

        guard observation.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "Space Fixture Home App inventory initial readback was "
                    + "unavailable. "
                    + observation.diagnosticSummary
            )
            return nil
        }

        let homeTabButtons = app.buttons.matching(
            identifier: Identifier.homeTabButton
        )
        guard tapFirstHittable(
            in: homeTabButtons,
            timeout:
                FlowTabUITestSpaceFixtureHomeProjectionPolicy
                    .homeTabNavigationWatchdog
        ) else {
            XCTFail(
                "Space Fixture Home App inventory navigation watchdog "
                    + "expired. finalCandidateCount="
                    + "\(homeTabButtons.count) "
                    + observation.diagnosticSummary
            )
            return nil
        }

        observation.markHomeNavigationCompleted()
        guard let evidence = observation.waitForResolution(
            timeout:
                FlowTabUITestSpaceFixtureHomeAppInventoryPolicy.watchdog(
                    appCount: workflow.apps.count
                )
        ) else {
            XCTFail(
                "Space Fixture Home App inventory watchdog expired. "
                    + observation.diagnosticSummary
            )
            return nil
        }
        return evidence.value
    }
}
