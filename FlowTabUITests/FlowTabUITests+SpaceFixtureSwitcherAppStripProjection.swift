import Foundation
import XCTest

enum FlowTabUITestSpaceFixtureSwitcherAppStripProjectionPolicy {
    static let watchdog: TimeInterval = 8
}

struct FlowTabUITestSpaceFixtureSwitcherAppStripProjectionExpectation:
    Equatable
{
    struct App: Equatable {
        let bundleIdentifier: String
        let windowCount: Int
        let rowIdentifier: String

        func exactEntry(windowCount: Int) -> String {
            "\(bundleIdentifier):\(windowCount)"
        }

        func accepts(windowCount observedWindowCount: Int, isSelected: Bool) -> Bool {
            observedWindowCount == windowCount
                || (!isSelected && observedWindowCount == 0)
        }

        var diagnosticSummary: String {
            "bundleID=\(bundleIdentifier) "
                + "configuredWindowCount=\(windowCount) "
                + "row=\(rowIdentifier)"
        }
    }

    let apps: [App]

    var isWellFormed: Bool {
        !apps.isEmpty
            && apps.allSatisfy {
                !$0.bundleIdentifier.isEmpty
                    && $0.windowCount > 0
                    && !$0.rowIdentifier.isEmpty
            }
            && Set(apps.map(\.bundleIdentifier)).count == apps.count
            && Set(apps.map(\.rowIdentifier)).count == apps.count
    }

    func isSatisfied(
        by snapshot: FlowTabUITestSpaceFixtureSwitcherAppStripProjectionSnapshot
    ) -> Bool {
        guard isWellFormed,
              snapshot.applicationState == .runningForeground,
              snapshot.projectionBeforeRows == snapshot.projectionAfterRows,
              snapshot.projectionBeforeRows.exists,
              snapshot.visibleTargetRowIdentifiers
                == apps.map(\.rowIdentifier).sorted()
        else {
            return false
        }
        guard let selectedBundleIdentifier =
                snapshot.projectionBeforeRows.selectedBundleIdentifier,
              apps.contains(where: {
                  $0.bundleIdentifier == selectedBundleIdentifier
              })
        else {
            return false
        }
        let targetBundleIdentifiers = Set(apps.map(\.bundleIdentifier))
        let targetEntries =
            snapshot.projectionBeforeRows.appProjection.entries.filter {
                targetBundleIdentifiers.contains($0.bundleIdentifier)
            }
        let entriesByBundleIdentifier = Dictionary(
            grouping: targetEntries,
            by: \.bundleIdentifier
        )
        return targetEntries.count == apps.count
            && apps.allSatisfy { app in
                guard
                    let entries = entriesByBundleIdentifier[
                        app.bundleIdentifier
                    ],
                    entries.count == 1,
                    let observedWindowCount = entries[0].windowCount
                else {
                    return false
                }
                return app.accepts(
                    windowCount: observedWindowCount,
                    isSelected:
                        app.bundleIdentifier == selectedBundleIdentifier
                )
            }
    }

    var diagnosticSummary: String {
        apps.map(\.diagnosticSummary).joined(separator: ",")
    }
}

struct FlowTabUITestSpaceFixtureSwitcherAppStripProjectionReadback:
    Equatable
{
    let appProjection: FlowTabUITestSwitcherAppProjectionReadback
    let selectedBundleIdentifier: String?

    init(
        appProjection: FlowTabUITestSwitcherAppProjectionReadback,
        selectedBundleIdentifier: String?
    ) {
        self.appProjection = appProjection
        self.selectedBundleIdentifier = selectedBundleIdentifier
    }

    init(diagnostics: FlowTabUITestSwitcherDiagnosticsSnapshot) {
        appProjection = FlowTabUITestSwitcherAppProjectionReadback(
            diagnostics: diagnostics
        )
        let selected = diagnostics.values["selected"]
        selectedBundleIdentifier =
            selected.flatMap { $0.isEmpty ? nil : $0 }
    }

    var exists: Bool {
        appProjection.exists && selectedBundleIdentifier != nil
    }

    var diagnosticSummary: String {
        "selectedBundleID=\(selectedBundleIdentifier ?? "nil") "
            + appProjection.diagnosticSummary
    }
}

struct FlowTabUITestSpaceFixtureSwitcherAppStripProjectionSnapshot:
    Equatable
{
    let applicationState: XCUIApplication.State
    let projectionBeforeRows:
        FlowTabUITestSpaceFixtureSwitcherAppStripProjectionReadback
    let visibleTargetRowIdentifiers: [String]
    let projectionAfterRows:
        FlowTabUITestSpaceFixtureSwitcherAppStripProjectionReadback

    init(
        applicationState: XCUIApplication.State,
        projectionBeforeRows:
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionReadback,
        visibleTargetRowIdentifiers: [String],
        projectionAfterRows:
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionReadback
    ) {
        self.applicationState = applicationState
        self.projectionBeforeRows = projectionBeforeRows
        self.visibleTargetRowIdentifiers = Array(
            Set(visibleTargetRowIdentifiers)
        ).sorted()
        self.projectionAfterRows = projectionAfterRows
    }

    var diagnosticSummary: String {
        "applicationState=\(String(describing: applicationState)) "
            + "projectionBeforeRows{"
            + "\(projectionBeforeRows.diagnosticSummary)} "
            + "visibleTargetRows="
            + "\(visibleTargetRowIdentifiers) "
            + "projectionAfterRows{"
            + "\(projectionAfterRows.diagnosticSummary)}"
    }
}

final class
    FlowTabUITestSpaceFixtureSwitcherAppStripProjectionObservationOwner
{
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionSnapshot
        >

    init(
        expectation:
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionExpectation,
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
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionSnapshot
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

    func requestReadback(source: FlowTabUITestConditionObservationSource) {
        conditionOwner.requestReadback(source: source)
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestSpaceFixtureSwitcherAppStripProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSpaceFixtureSwitcherAppStripProjectionSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSpaceFixtureSwitcherAppStripProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }

    deinit {
        cancel()
    }
}

extension FlowTabUITests {
    @discardableResult
    func waitForSpaceFixtureSwitcherAppStripProjection(
        _ workflow: SpaceFixtureResolvedWorkflow,
        in app: XCUIApplication,
        timeout: TimeInterval =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionPolicy.watchdog,
        trigger: (() -> Void)? = nil
    ) -> FlowTabUITestSpaceFixtureSwitcherAppStripProjectionSnapshot? {
        let expectedApps = workflow.apps.map {
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionExpectation.App(
                bundleIdentifier: $0.identity.bundleIdentifier,
                windowCount: $0.windowCount,
                rowIdentifier: $0.identity.switcherAppAccessibilityIdentifier
            )
        }
        let expectation =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionExpectation(
                apps: expectedApps
            )
        guard expectation.isWellFormed else {
            XCTFail(
                "Space Fixture Switcher App strip expectation is invalid. "
                    + expectation.diagnosticSummary
            )
            return nil
        }

        let diagnosticsSummary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        let targetRowIdentifiers = Set(expectedApps.map(\.rowIdentifier))
        var triggerCompleted = trigger == nil
        let owner =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionObservationOwner(
                expectation: expectation,
                acceptsResolution: { triggerCompleted },
                readback: {
                    let applicationState = app.state
                    guard applicationState == .runningForeground else {
                        let unavailableProjection =
                            FlowTabUITestSwitcherAppProjectionReadback(
                                snapshot:
                                    FlowTabUITestSwitcherAppProjectionSnapshot(
                                        applicationState: applicationState,
                                        identifier: Identifier.switcherSummary,
                                        exists: false,
                                        rawValue: nil,
                                        entries: []
                                    )
                            )
                        let unavailable =
                            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionReadback(
                                appProjection: unavailableProjection,
                                selectedBundleIdentifier: nil
                            )
                        return .init(
                            applicationState: applicationState,
                            projectionBeforeRows: unavailable,
                            visibleTargetRowIdentifiers: [],
                            projectionAfterRows: unavailable
                        )
                    }
                    let projectionBeforeRows =
                        self.switcherAppStripProjectionReadback(
                            diagnosticsSummary
                        )
                    let visibleTargetRows =
                        app.descendants(matching: .any)
                            .matching(
                                NSPredicate(
                                    format: "identifier IN %@",
                                    targetRowIdentifiers.sorted()
                                )
                            )
                            .allElementsBoundByIndex
                            .map(\.identifier)
                    return .init(
                        applicationState: applicationState,
                        projectionBeforeRows: projectionBeforeRows,
                        visibleTargetRowIdentifiers: visibleTargetRows,
                        projectionAfterRows:
                            self.switcherAppStripProjectionReadback(
                                diagnosticsSummary
                            )
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        guard owner.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "Space Fixture Switcher App strip initial readback was "
                    + "unavailable. \(owner.diagnosticSummary)"
            )
            return nil
        }
        if let initialEvidence = owner.resolvedEvidence {
            return initialEvidence.value
        }

        if let trigger {
            trigger()
            triggerCompleted = true
            owner.requestReadback(source: .triggerReadback)
        }
        guard let evidence = owner.waitForResolution(timeout: timeout) else {
            XCTFail(
                "Space Fixture Switcher App strip watchdog expired. "
                    + owner.diagnosticSummary
            )
            return nil
        }
        return evidence.value
    }

    func switcherAppStripProjectionReadback(
        _ diagnosticsSummaryElement: XCUIElement
    ) -> FlowTabUITestSpaceFixtureSwitcherAppStripProjectionReadback {
        FlowTabUITestSpaceFixtureSwitcherAppStripProjectionReadback(
            diagnostics:
                switcherDiagnosticsSnapshot(
                    diagnosticsSummaryElement,
                    keys: ["apps", "selected"]
                )
        )
    }
}
