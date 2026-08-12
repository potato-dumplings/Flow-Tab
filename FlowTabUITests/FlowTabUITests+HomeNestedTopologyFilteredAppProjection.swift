import Foundation
import XCTest

enum FlowTabUITestHomeNestedTopologyFilteredAppProjectionPolicy {
    static let watchdog: TimeInterval = 2
    static let visibleIdentifiers = [
        FlowTabUITests.Identifier.homeAppWeChat,
        FlowTabUITests.Identifier.homeAppTopLevelZeroWindow
    ]
    static let excludedIdentifiers = [
        FlowTabUITests.Identifier.homeAppNestedWeChatAppEx,
        FlowTabUITests.Identifier.homeAppNestedMiniProgram
    ]
}

struct FlowTabUITestHomeFilteredAppProjectionSnapshot: Equatable {
    let applicationState: XCUIApplication.State
    let appCountLabelBeforeRows: String?
    let visibleRowIdentifiers: [String]
    let excludedRows: [FlowTabUITestElementExistenceReadback]
    let appCountLabelAfterRows: String?

    static func appCount(from label: String?) -> Int? {
        guard let label else { return nil }
        let numberRuns = label.split { !$0.isNumber }
        guard numberRuns.count == 1 else { return nil }
        return Int(String(numberRuns[0]))
    }

    var diagnosticSummary: String {
        let excludedSummary = excludedRows.map {
            "\($0.identifier)=\($0.exists ? 1 : 0)"
        }.joined(separator: ",")
        return "applicationState=\(String(describing: applicationState)) "
            + "countBefore="
            + "\(String(reflecting: appCountLabelBeforeRows)) "
            + "visible=\(visibleRowIdentifiers) "
            + "excluded=[\(excludedSummary)] "
            + "countAfter="
            + "\(String(reflecting: appCountLabelAfterRows))"
    }
}

struct FlowTabUITestHomeFilteredAppProjectionExpectation: Equatable {
    let visibleIdentifiers: [String]
    let excludedIdentifiers: [String]

    var isWellFormed: Bool {
        !visibleIdentifiers.isEmpty
            && Set(visibleIdentifiers).count == visibleIdentifiers.count
            && !excludedIdentifiers.isEmpty
            && Set(excludedIdentifiers).count == excludedIdentifiers.count
            && Set(visibleIdentifiers).isDisjoint(
                with: Set(excludedIdentifiers)
            )
    }

    func isSatisfied(
        by snapshot: FlowTabUITestHomeFilteredAppProjectionSnapshot
    ) -> Bool {
        let expectedCount = visibleIdentifiers.count
        let visibleSet = Set(snapshot.visibleRowIdentifiers)
        return isWellFormed
            && snapshot.applicationState == .runningForeground
            && FlowTabUITestHomeFilteredAppProjectionSnapshot.appCount(
                from: snapshot.appCountLabelBeforeRows
            ) == expectedCount
            && FlowTabUITestHomeFilteredAppProjectionSnapshot.appCount(
                from: snapshot.appCountLabelAfterRows
            ) == expectedCount
            && snapshot.visibleRowIdentifiers.count == expectedCount
            && visibleSet.count == expectedCount
            && visibleSet == Set(visibleIdentifiers)
            && snapshot.excludedRows.map(\.identifier)
                == excludedIdentifiers
            && snapshot.excludedRows.allSatisfy { !$0.exists }
    }

    var diagnosticSummary: String {
        "visible=\(visibleIdentifiers) "
            + "expectedCount=\(visibleIdentifiers.count) "
            + "excluded=\(excludedIdentifiers)"
    }
}

private enum FlowTabUITestHomeFilteredAppProjectionPhase: String {
    case initialReadback
    case awaitingSelectedHostProjection
    case selectedHostProjectionCompleted
}

private final class FlowTabUITestHomeFilteredAppProjectionState {
    var phase: FlowTabUITestHomeFilteredAppProjectionPhase =
        .initialReadback

    var acceptsEvidence: Bool {
        phase == .selectedHostProjectionCompleted
    }
}

final class FlowTabUITestHomeFilteredAppProjectionObservationOwner {
    private let expectation:
        FlowTabUITestHomeFilteredAppProjectionExpectation
    private let state: FlowTabUITestHomeFilteredAppProjectionState
    private let deferredReadbacks:
        FlowTabUITestDeferredConditionReadbackRegistration
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestHomeFilteredAppProjectionSnapshot
        >

    init(
        expectation: FlowTabUITestHomeFilteredAppProjectionExpectation,
        scheduledRegistration:
            @escaping FlowTabUITestConditionObservationRegistration =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestHomeFilteredAppProjectionSnapshot
    ) {
        let state = FlowTabUITestHomeFilteredAppProjectionState()
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
            isSatisfied: {
                state.acceptsEvidence
                    && expectation.isSatisfied(by: $0)
            },
            describe: { snapshot in
                "acceptanceEnabled=\(state.acceptsEvidence) "
                    + snapshot.diagnosticSummary
            }
        )
    }

    func start() {
        state.phase = .initialReadback
        conditionOwner.start()
        state.phase = .awaitingSelectedHostProjection
    }

    func markSelectedHostProjectionCompleted() {
        guard conditionOwner.resolvedEvidence == nil else { return }
        state.phase = .selectedHostProjectionCompleted
        conditionOwner.requestReadback(source: .triggerReadback)
        if conditionOwner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestHomeFilteredAppProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestHomeFilteredAppProjectionSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestHomeFilteredAppProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        "phase=\(state.phase.rawValue) "
            + "expected{\(expectation.diagnosticSummary)} "
            + conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    @discardableResult
    func assertHomeAndLogsNestedTopologyFilteredAppsAfterSelectingHost(
        _ hostRow: XCUIElement,
        in app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let expectation =
            FlowTabUITestHomeFilteredAppProjectionExpectation(
                visibleIdentifiers:
                    FlowTabUITestHomeNestedTopologyFilteredAppProjectionPolicy
                        .visibleIdentifiers,
                excludedIdentifiers:
                    FlowTabUITestHomeNestedTopologyFilteredAppProjectionPolicy
                        .excludedIdentifiers
            )
        let appCount = element(
            in: app,
            identifier: Identifier.homeAppCount
        )
        let visibleRows = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "flowtab.home.app."
            )
        )
        let excludedRows = expectation.excludedIdentifiers.map {
            FlowTabUITestHomeAppRowProjectionElement(
                identifier: $0,
                element: element(in: app, identifier: $0)
            )
        }
        let observation =
            FlowTabUITestHomeFilteredAppProjectionObservationOwner(
                expectation: expectation,
                readback: {
                    let applicationState = app.state
                    guard applicationState == .runningForeground else {
                        return .init(
                            applicationState: applicationState,
                            appCountLabelBeforeRows: nil,
                            visibleRowIdentifiers: [],
                            excludedRows: excludedRows.map {
                                .init(
                                    identifier: $0.identifier,
                                    exists: false
                                )
                            },
                            appCountLabelAfterRows: nil
                        )
                    }
                    let countBefore = appCount.exists
                        ? appCount.label
                        : nil
                    let identifiers = visibleRows
                        .allElementsBoundByIndex
                        .map(\.identifier)
                    let excludedReadback = excludedRows.map {
                        FlowTabUITestElementExistenceReadback(
                            identifier: $0.identifier,
                            exists: $0.element.exists
                        )
                    }
                    let countAfter = appCount.exists
                        ? appCount.label
                        : nil
                    return .init(
                        applicationState: applicationState,
                        appCountLabelBeforeRows: countBefore,
                        visibleRowIdentifiers: identifiers,
                        excludedRows: excludedReadback,
                        appCountLabelAfterRows: countAfter
                    )
                }
            )
        observation.start()
        defer { observation.cancel() }

        guard observation.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "Home nested-topology filtered-App initial readback "
                    + "was unavailable. target=\(targetDescription) "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return false
        }
        guard assertHomeAndLogsNestedTopologyWindowsAfterSelectingHost(
            hostRow,
            in: app,
            targetDescription: targetDescription,
            file: file,
            line: line
        ) else {
            return false
        }

        observation.markSelectedHostProjectionCompleted()
        guard observation.waitForResolution(
            timeout:
                FlowTabUITestHomeNestedTopologyFilteredAppProjectionPolicy
                    .watchdog
        ) != nil else {
            XCTFail(
                "Home nested-topology filtered-App projection watchdog "
                    + "expired. target=\(targetDescription) "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return false
        }
        return true
    }
}
