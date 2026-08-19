import Foundation
import XCTest

private enum FlowTabUITestVisibleSwitcherAppProjectionPhase: String {
    case initialReadback
    case awaitingTrigger
    case triggerCompleted
}

private final class FlowTabUITestVisibleSwitcherAppProjectionState {
    var phase: FlowTabUITestVisibleSwitcherAppProjectionPhase =
        .initialReadback

    var acceptsEvidence: Bool {
        phase == .triggerCompleted
    }
}

struct FlowTabUITestVisibleSwitcherAppProjectionSnapshot:
    Equatable
{
    let applicationState: XCUIApplication.State
    let diagnosticsIdentifier: String
    let diagnosticsExists: Bool
    let rawAppsValue: String?
    let entries: [FlowTabUITestSwitcherAppProjectionEntry]
    let visibleTargetRowIdentifiers: Set<String>

    var appProjectionSnapshot:
        FlowTabUITestSwitcherAppProjectionSnapshot
    {
        FlowTabUITestSwitcherAppProjectionSnapshot(
            applicationState: applicationState,
            identifier: diagnosticsIdentifier,
            exists: diagnosticsExists,
            rawValue: rawAppsValue,
            entries: entries
        )
    }

    var diagnosticSummary: String {
        let entrySummary = entries
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.diagnosticSummary)
            .joined(separator: " | ")
        return "applicationState=\(String(describing: applicationState)) "
            + "diagnosticsIdentifier=\(diagnosticsIdentifier) "
            + "diagnosticsExists=\(diagnosticsExists) "
            + "entries=[\(entrySummary)] "
            + "visibleTargetRows="
            + "\(visibleTargetRowIdentifiers.sorted()) "
            + "raw=\(rawAppsValue ?? "nil")"
    }
}

struct FlowTabUITestVisibleSwitcherAppProjectionExpectation {
    let diagnosticsIdentifier: String
    let appProjection:
        FlowTabUITestSwitcherAppProjectionExpectation
    let requiredRowIdentifiers: Set<String>
    let excludedRowIdentifiers: Set<String>

    func isSatisfied(
        by snapshot:
            FlowTabUITestVisibleSwitcherAppProjectionSnapshot
    ) -> Bool {
        snapshot.diagnosticsIdentifier == diagnosticsIdentifier
            && appProjection.isSatisfied(
                by: snapshot.appProjectionSnapshot
            )
            && requiredRowIdentifiers.isSubset(
                of: snapshot.visibleTargetRowIdentifiers
            )
            && snapshot.visibleTargetRowIdentifiers.isDisjoint(
                with: excludedRowIdentifiers
            )
    }

    var diagnosticSummary: String {
        "diagnosticsIdentifier=\(diagnosticsIdentifier) "
            + "appProjection={\(appProjection.diagnosticSummary)} "
            + "requiredRows=\(requiredRowIdentifiers.sorted()) "
            + "excludedRows=\(excludedRowIdentifiers.sorted())"
    }
}

final class FlowTabUITestVisibleSwitcherAppProjectionObservationOwner {
    private let state:
        FlowTabUITestVisibleSwitcherAppProjectionState
    private let deferredReadbacks:
        FlowTabUITestDeferredConditionReadbackRegistration
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestVisibleSwitcherAppProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestVisibleSwitcherAppProjectionExpectation,
        scheduledRegistration:
            @escaping FlowTabUITestConditionObservationRegistration =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestVisibleSwitcherAppProjectionSnapshot
    ) {
        let state =
            FlowTabUITestVisibleSwitcherAppProjectionState()
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration: scheduledRegistration
            )
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
                "expected{\(expectation.diagnosticSummary)} "
                    + snapshot.diagnosticSummary
            }
        )
    }

    func start() {
        state.phase = .initialReadback
        conditionOwner.start()
        state.phase = .awaitingTrigger
    }

    func markTriggerCompleted() {
        guard conditionOwner.resolvedEvidence == nil else {
            return
        }
        state.phase = .triggerCompleted
        conditionOwner.requestReadback(source: .triggerReadback)
        if conditionOwner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }
    }

    func waitForResolution(
        watchdog: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestVisibleSwitcherAppProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: watchdog)
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestVisibleSwitcherAppProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestVisibleSwitcherAppProjectionSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var diagnosticSummary: String {
        "phase=\(state.phase.rawValue) "
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
    func performAndWaitForVisibleSwitcherAppProjection(
        in app: XCUIApplication,
        requiredBundleIdentifiers: Set<String>,
        excludedBundleIdentifiers: Set<String>,
        appProjectionExpectation:
            FlowTabUITestSwitcherAppProjectionExpectation? = nil,
        targetDescription: String,
        watchdog: TimeInterval =
            FlowTabUITestSwitcherAppProjectionPolicy
                .postLaunchWatchdog,
        file: StaticString = #filePath,
        line: UInt = #line,
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
                    + "excluded=\(excludedBundleIdentifiers.sorted())",
                file: file,
                line: line
            )
            return false
        }

        let requiredRowIdentifiers = Set(
            requiredBundleIdentifiers.map(
                switcherAppRowIdentifier
            )
        )
        let excludedRowIdentifiers = Set(
            excludedBundleIdentifiers.map(
                switcherAppRowIdentifier
            )
        )
        let targetRowIdentifiers =
            requiredRowIdentifiers.union(excludedRowIdentifiers)
        let observedIdentifiers = targetRowIdentifiers.union([
            Identifier.switcherSummary
        ])
        let observedElements = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier IN %@",
                    observedIdentifiers.sorted()
                )
            )
        let expectation =
            FlowTabUITestVisibleSwitcherAppProjectionExpectation(
                diagnosticsIdentifier: Identifier.switcherSummary,
                appProjection:
                    appProjectionExpectation
                    ?? .bundleIdentifiers(
                        required: requiredBundleIdentifiers,
                        excluded: excludedBundleIdentifiers
                    ),
                requiredRowIdentifiers: requiredRowIdentifiers,
                excludedRowIdentifiers: excludedRowIdentifiers
            )
        let owner =
            FlowTabUITestVisibleSwitcherAppProjectionObservationOwner(
                expectation: expectation,
                readback: {
                    self.visibleSwitcherAppProjectionSnapshot(
                        in: app,
                        observedElements: observedElements,
                        targetRowIdentifiers:
                            targetRowIdentifiers
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        guard owner.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "Visible Switcher App projection initial readback "
                    + "was unavailable. target=\(targetDescription) "
                    + owner.diagnosticSummary,
                file: file,
                line: line
            )
            return false
        }

        trigger()
        owner.markTriggerCompleted()
        guard owner.waitForResolution(watchdog: watchdog) != nil
        else {
            XCTFail(
                "Visible Switcher App projection watchdog expired. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary,
                file: file,
                line: line
            )
            return false
        }
        return true
    }

    private func visibleSwitcherAppProjectionSnapshot(
        in app: XCUIApplication,
        observedElements: XCUIElementQuery,
        targetRowIdentifiers: Set<String>
    ) -> FlowTabUITestVisibleSwitcherAppProjectionSnapshot {
        let applicationState = app.state
        guard applicationState == .runningForeground else {
            return FlowTabUITestVisibleSwitcherAppProjectionSnapshot(
                applicationState: applicationState,
                diagnosticsIdentifier: Identifier.switcherSummary,
                diagnosticsExists: false,
                rawAppsValue: nil,
                entries: [],
                visibleTargetRowIdentifiers: []
            )
        }

        let elements = observedElements.allElementsBoundByIndex
        let diagnosticsSummary = elements.first {
            $0.identifier == Identifier.switcherSummary
        }
        let rawAppsValue = diagnosticsSummary.map {
            switcherPanelDiagnosticsValue($0, key: "apps")
        }
        let entries = rawAppsValue?.split(separator: "|").map {
            FlowTabUITestSwitcherAppProjectionEntry(
                rawValue: String($0)
            )
        } ?? []
        let visibleTargetRowIdentifiers = Set(
            elements.map(\.identifier)
        ).intersection(targetRowIdentifiers)
        return FlowTabUITestVisibleSwitcherAppProjectionSnapshot(
            applicationState: applicationState,
            diagnosticsIdentifier:
                diagnosticsSummary?.identifier
                ?? Identifier.switcherSummary,
            diagnosticsExists: diagnosticsSummary != nil,
            rawAppsValue: rawAppsValue,
            entries: entries,
            visibleTargetRowIdentifiers:
                visibleTargetRowIdentifiers
        )
    }
}
