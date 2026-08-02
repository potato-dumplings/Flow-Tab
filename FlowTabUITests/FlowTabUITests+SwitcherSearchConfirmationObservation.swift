import Foundation
import XCTest

enum FlowTabUITestSwitcherSearchConfirmationPolicy {
    static let applicationEvidenceLaunchArguments = [
        "--flowtab-ui-runtime-log-level",
        "DEBUG",
        "--flowtab-ui-enable-verbose-logs"
    ]
    static let confirmationWatchdog: TimeInterval = 4
}

enum FlowTabUITestSwitcherSearchConfirmationRequirement: String {
    case dismissalOrMarkedTextClear
    case dismissal
}

enum FlowTabUITestSwitcherSearchConfirmationOutcome: String, Equatable {
    case searchInputDismissed
    case markedTextCleared
}

enum FlowTabUITestSwitcherSearchConfirmationEvidence {
    static func markedTextClearedMarker(
        expectedQuery: String
    ) -> String {
        "markedText changed=0 active=1 inputFocused=1 "
            + "query=\(expectedQuery.debugDescription)"
    }
}

struct FlowTabUITestSwitcherSearchConfirmationSnapshot: Equatable {
    let searchInputExists: Bool
    let runtimeLog: FlowTabUITestRuntimeLogSnapshot

    func outcome(
        satisfying requirement:
            FlowTabUITestSwitcherSearchConfirmationRequirement,
        markedTextClearedMarker: String
    ) -> FlowTabUITestSwitcherSearchConfirmationOutcome? {
        if !searchInputExists {
            return .searchInputDismissed
        }
        guard requirement == .dismissalOrMarkedTextClear,
              runtimeLog.contents.contains(
                  markedTextClearedMarker
              )
        else {
            return nil
        }
        return .markedTextCleared
    }

    var diagnosticSummary: String {
        "searchInputExists=\(searchInputExists) "
            + "runtimeLog{\(runtimeLog.diagnosticSummary)}"
    }
}

final class FlowTabUITestSwitcherSearchConfirmationObservationOwner {
    private let requirement:
        FlowTabUITestSwitcherSearchConfirmationRequirement
    private let markedTextClearedMarker: String
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSwitcherSearchConfirmationSnapshot
        >

    init(
        expectedQuery: String,
        requirement:
            FlowTabUITestSwitcherSearchConfirmationRequirement,
        observationRegistration:
            FlowTabUITestConditionObservationRegistration?,
        readback: @escaping () ->
            FlowTabUITestSwitcherSearchConfirmationSnapshot
    ) {
        self.requirement = requirement
        markedTextClearedMarker =
            FlowTabUITestSwitcherSearchConfirmationEvidence
                .markedTextClearedMarker(
                    expectedQuery: expectedQuery
                )
        let markedTextClearedMarker =
            self.markedTextClearedMarker
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration:
                observationRegistration,
            readback: readback,
            isSatisfied: { snapshot in
                snapshot.outcome(
                    satisfying: requirement,
                    markedTextClearedMarker:
                        markedTextClearedMarker
                ) != nil
            },
            describe: { snapshot in
                let outcome = snapshot.outcome(
                    satisfying: requirement,
                    markedTextClearedMarker:
                        markedTextClearedMarker
                )
                return "requirement=\(requirement.rawValue) "
                    + "missingMarkedTextClearMarker="
                    + "\(!snapshot.runtimeLog.contents.contains(markedTextClearedMarker)) "
                    + "outcome=\(outcome?.rawValue ?? "nil") "
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
        FlowTabUITestSwitcherSearchConfirmationSnapshot
    >? {
        conditionOwner.waitForResolution(
            timeout: timeout
        )
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSwitcherSearchConfirmationSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var resolvedOutcome:
        FlowTabUITestSwitcherSearchConfirmationOutcome?
    {
        resolvedEvidence?.value.outcome(
            satisfying: requirement,
            markedTextClearedMarker:
                markedTextClearedMarker
        )
    }

    var diagnosticSummary: String {
        "expectedMarkedTextClearMarker="
            + "\(markedTextClearedMarker.debugDescription) "
            + conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

extension FlowTabUITests {
    @discardableResult
    func confirmSwitcherSearchSelection(
        in app: XCUIApplication,
        searchInput: XCUIElement,
        expectedQuery: String
    ) -> Bool {
        let baseline = makeRuntimeLogFileSnapshot()
        defer { baseline.cancel() }
        let readback = {
            FlowTabUITestSwitcherSearchConfirmationSnapshot(
                searchInputExists: searchInput.exists,
                runtimeLog: baseline.makeReadback()
            )
        }
        let initialOwner =
            FlowTabUITestSwitcherSearchConfirmationObservationOwner(
                expectedQuery: expectedQuery,
                requirement: .dismissalOrMarkedTextClear,
                observationRegistration:
                    baseline.observationRegistration(),
                readback: readback
            )
        initialOwner.start()
        defer { initialOwner.cancel() }

        let initialOutcome: FlowTabUITestSwitcherSearchConfirmationOutcome?
        if let resolvedOutcome = initialOwner.resolvedOutcome {
            initialOutcome = resolvedOutcome
        } else {
            app.typeText("\r")
            _ = initialOwner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherSearchConfirmationPolicy
                        .confirmationWatchdog
            )
            initialOutcome = initialOwner.resolvedOutcome
        }

        guard let initialOutcome else {
            XCTFail(
                "Switcher Search confirmation watchdog expired "
                    + "before dismissal or marked-text clearance. "
                    + initialOwner.diagnosticSummary
            )
            return false
        }
        guard initialOutcome == .markedTextCleared else {
            return true
        }

        let dismissalOwner =
            FlowTabUITestSwitcherSearchConfirmationObservationOwner(
                expectedQuery: expectedQuery,
                requirement: .dismissal,
                observationRegistration:
                    baseline.observationRegistration(),
                readback: readback
            )
        dismissalOwner.start()
        defer { dismissalOwner.cancel() }
        if dismissalOwner.resolvedOutcome == nil {
            app.typeText("\r")
            _ = dismissalOwner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherSearchConfirmationPolicy
                        .confirmationWatchdog
            )
        }
        guard dismissalOwner.resolvedOutcome
            == .searchInputDismissed
        else {
            XCTFail(
                "Switcher Search confirmation watchdog expired "
                    + "after marked-text clearance. "
                    + dismissalOwner.diagnosticSummary
            )
            return false
        }
        return true
    }
}
