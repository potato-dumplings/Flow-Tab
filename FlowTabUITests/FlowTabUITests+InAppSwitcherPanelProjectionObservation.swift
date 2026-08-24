import Foundation
import XCTest

enum FlowTabUITestInAppSwitcherPanelProjectionPolicy {
    static let readinessWatchdog: TimeInterval = 8
}

enum FlowTabUITestInAppSwitcherPanelProjectionResolution:
    Equatable
{
    case pending
    case satisfied
    case terminalMismatch
}

struct FlowTabUITestInAppSwitcherPanelProjectionExpectation:
    Equatable
{
    let bundleIdentifier: String
    let windowCount: Int
    let titleCounts: [String: Int]

    init(
        bundleIdentifier: String,
        windowCount: Int,
        expectedTitles: [String]
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.windowCount = windowCount
        titleCounts = Self.counts(for: expectedTitles)
    }

    var isWellFormed: Bool {
        !bundleIdentifier.isEmpty
            && windowCount > 0
            && titleCounts.values.reduce(0, +) == windowCount
            && titleCounts.keys.allSatisfy { !$0.isEmpty }
    }

    func isSatisfied(
        by snapshot:
            FlowTabUITestInAppSwitcherPanelProjectionSnapshot
    ) -> Bool {
        resolution(for: snapshot) == .satisfied
    }

    func resolution(
        for snapshot:
            FlowTabUITestInAppSwitcherPanelProjectionSnapshot
    ) -> FlowTabUITestInAppSwitcherPanelProjectionResolution {
        guard isWellFormed,
              snapshot.hasStableRunningApplication,
              snapshot.diagnostics.exists,
              snapshot.selectedBundleIdentifier == bundleIdentifier,
              snapshot.mode == "windowCycle(\(bundleIdentifier))",
              snapshot.previewProjection.selectedBundleIdentifier
                == bundleIdentifier,
              snapshot.previewProjection.previewBundleIdentifier
                == bundleIdentifier
        else {
            return .pending
        }
        let matchingEntries =
            snapshot.appProjection.entries.filter {
                $0.bundleIdentifier == bundleIdentifier
            }
        let hasExpectedProjection = matchingEntries.count == 1
            && matchingEntries[0].rawValue
                == "\(bundleIdentifier):\(windowCount)"
            && Self.counts(for: snapshot.previewProjection.titles)
                == titleCounts
        return hasExpectedProjection ? .satisfied : .terminalMismatch
    }

    var diagnosticSummary: String {
        "bundleID=\(bundleIdentifier) "
            + "windowCount=\(windowCount) "
            + "titleCounts=\(Self.summary(for: titleCounts))"
    }

    private static func counts(
        for titles: [String]
    ) -> [String: Int] {
        titles.reduce(into: [:]) { counts, title in
            counts[title, default: 0] += 1
        }
    }

    private static func summary(
        for counts: [String: Int]
    ) -> String {
        counts.keys.sorted().map {
            "\($0):\(counts[$0] ?? 0)"
        }.joined(separator: "|")
    }
}

struct FlowTabUITestInAppSwitcherPanelProjectionSnapshot:
    Equatable
{
    let applicationStateBefore: XCUIApplication.State
    let diagnostics: FlowTabUITestSwitcherDiagnosticsSnapshot
    let applicationStateAfter: XCUIApplication.State

    var hasStableRunningApplication: Bool {
        applicationStateBefore == applicationStateAfter
            && (applicationStateBefore == .runningForeground
                || applicationStateBefore == .runningBackground)
    }

    var appProjection: FlowTabUITestSwitcherAppProjectionReadback {
        FlowTabUITestSwitcherAppProjectionReadback(
            diagnostics: diagnostics
        )
    }

    var previewProjection:
        FlowTabUITestSwitcherPreviewProjectionSnapshot
    {
        FlowTabUITestSwitcherPreviewProjectionSnapshot(
            diagnostics: diagnostics
        )
    }

    var selectedBundleIdentifier: String? {
        diagnostics.values["selected"]
    }

    var mode: String? {
        diagnostics.values["mode"]
    }

    var diagnosticSummary: String {
        "applicationStateBefore="
            + "\(String(describing: applicationStateBefore)) "
            + "applicationStateAfter="
            + "\(String(describing: applicationStateAfter)) "
            + "stableRunning=\(hasStableRunningApplication) "
            + "appProjection{\(appProjection.diagnosticSummary)} "
            + "observedTitleCounts=\(observedTitleCountSummary) "
            + "previewProjection{"
            + "\(previewProjection.diagnosticSummary)} "
            + diagnostics.diagnosticSummary
    }

    private var observedTitleCountSummary: String {
        let counts = previewProjection.titles.reduce(
            into: [String: Int]()
        ) { counts, title in
            counts[title, default: 0] += 1
        }
        return counts.keys.sorted().map {
            "\($0):\(counts[$0] ?? 0)"
        }.joined(separator: "|")
    }
}

private final class
    FlowTabUITestInAppSwitcherPanelProjectionObservationState
{
    var initialAbsenceSatisfied = false
    var triggerCompleted = false
    var terminalMismatch = false
}

final class
    FlowTabUITestInAppSwitcherPanelProjectionObservationOwner
{
    private let state =
        FlowTabUITestInAppSwitcherPanelProjectionObservationState()
    private let deferredReadbacks:
        FlowTabUITestDeferredConditionReadbackRegistration
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestInAppSwitcherPanelProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestInAppSwitcherPanelProjectionExpectation,
        scheduledRegistration:
            @escaping FlowTabUITestConditionObservationRegistration =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestInAppSwitcherPanelProjectionSnapshot
    ) {
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration: scheduledRegistration
            )
        self.deferredReadbacks = deferredReadbacks
        conditionOwner =
            FlowTabUITestConditionObservationOwner(
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                readback: readback,
                isSatisfied: { [state] snapshot in
                    guard state.initialAbsenceSatisfied,
                          state.triggerCompleted
                    else {
                        return false
                    }
                    switch expectation.resolution(for: snapshot) {
                    case .pending:
                        return false
                    case .satisfied:
                        return true
                    case .terminalMismatch:
                        state.terminalMismatch = true
                        return true
                    }
                },
                describe: { [state] snapshot in
                    "initialAbsenceSatisfied="
                        + "\(state.initialAbsenceSatisfied) "
                        + "triggerCompleted="
                        + "\(state.triggerCompleted) "
                        + "terminalMismatch="
                        + "\(state.terminalMismatch) "
                        + "expected{"
                        + expectation.diagnosticSummary
                        + "} "
                        + snapshot.diagnosticSummary
                }
            )
    }

    func start() -> Bool {
        state.initialAbsenceSatisfied = false
        state.triggerCompleted = false
        state.terminalMismatch = false
        conditionOwner.start()
        guard
            let initialEvidence = conditionOwner.latestEvidence,
            initialEvidence.source == .initialReadback
        else {
            return false
        }
        state.initialAbsenceSatisfied =
            initialEvidence.value.hasStableRunningApplication
                && !initialEvidence.value.diagnostics.exists
        return state.initialAbsenceSatisfied
    }

    func markTriggerCompleted() {
        guard
            state.initialAbsenceSatisfied,
            !state.triggerCompleted
        else {
            return
        }
        state.triggerCompleted = true
        conditionOwner.requestReadback(source: .triggerReadback)
        if conditionOwner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestInAppSwitcherPanelProjectionSnapshot
    >? {
        let evidence = conditionOwner.waitForResolution(timeout: timeout)
        return state.terminalMismatch ? nil : evidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestInAppSwitcherPanelProjectionSnapshot
    >? {
        state.terminalMismatch ? nil : conditionOwner.resolvedEvidence
    }

    var terminalMismatchEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestInAppSwitcherPanelProjectionSnapshot
    >? {
        state.terminalMismatch ? conditionOwner.resolvedEvidence : nil
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
        deferredReadbacks.cancel()
        state.initialAbsenceSatisfied = false
        state.triggerCompleted = false
        state.terminalMismatch = false
    }

    deinit {
        cancel()
    }
}

extension FlowTabUITests {
    func performAndWaitForInAppSwitcherPanelProjection(
        for workflowApp: SpaceFixtureResolvedWorkflow.App,
        in app: XCUIApplication,
        trigger: () -> Void
    ) -> XCUIElement {
        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        let expectation =
            FlowTabUITestInAppSwitcherPanelProjectionExpectation(
                bundleIdentifier:
                    workflowApp.identity.bundleIdentifier,
                windowCount: workflowApp.windowCount,
                expectedTitles:
                    workflowApp.expectedWindowTitles
            )
        let owner =
            FlowTabUITestInAppSwitcherPanelProjectionObservationOwner(
                expectation: expectation,
                readback: {
                    let applicationStateBefore = app.state
                    let diagnostics =
                        self.switcherDiagnosticsSnapshot(
                            diagnosticsSummary,
                            keys: [
                                "apps",
                                "selected",
                                "mode",
                                "preview"
                            ]
                        )
                    return FlowTabUITestInAppSwitcherPanelProjectionSnapshot(
                        applicationStateBefore:
                            applicationStateBefore,
                        diagnostics: diagnostics,
                        applicationStateAfter: app.state
                    )
                }
            )
        guard owner.start() else {
            XCTFail(
                "In-App Switcher panel absence baseline was unavailable. "
                    + owner.diagnosticSummary
            )
            owner.cancel()
            return diagnosticsSummary
        }
        defer { owner.cancel() }

        trigger()
        owner.markTriggerCompleted()
        guard owner.waitForResolution(
            timeout:
                FlowTabUITestInAppSwitcherPanelProjectionPolicy
                    .readinessWatchdog
        ) != nil else {
            XCTFail(
                "In-App Switcher panel projection watchdog expired. "
                    + owner.diagnosticSummary
            )
            return diagnosticsSummary
        }
        return diagnosticsSummary
    }
}
