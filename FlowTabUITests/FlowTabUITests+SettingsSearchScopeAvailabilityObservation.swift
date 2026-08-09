import Foundation
import XCTest

enum SettingsSearchScopeAvailabilityUITestPolicy {
    static let projectionWatchdog: TimeInterval = 6
}

struct SettingsSearchScopeAvailabilitySnapshot: Equatable {
    static let accessibilityRequiredSummaryLabels: Set<String> = [
        "窗口搜索需要辅助功能权限；授权后可选择窗口范围。",
        "Window search requires Accessibility permission. Enable it to choose Window.",
    ]

    let scopeControlExists: Bool
    let scopeControlValue: String
    let scopeControlEnabled: Bool
    let summaryExists: Bool
    let summaryText: String
    let windowOptionExists: Bool

    var isAppOnlyProjection: Bool {
        scopeControlExists
            && scopeControlValue == "app"
            && scopeControlEnabled == false
            && summaryExists
            && Self.accessibilityRequiredSummaryLabels.contains(
                summaryText
            )
            && windowOptionExists == false
    }

    var diagnosticSummary: String {
        "isAppOnlyProjection=\(isAppOnlyProjection) "
            + "scopeControlExists=\(scopeControlExists) "
            + "scopeControlValue="
            + "\(String(reflecting: scopeControlValue)) "
            + "scopeControlEnabled=\(scopeControlEnabled) "
            + "summaryExists=\(summaryExists) "
            + "summaryText=\(String(reflecting: summaryText)) "
            + "windowOptionExists=\(windowOptionExists)"
    }
}

final class SettingsSearchScopeAvailabilityObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            SettingsSearchScopeAvailabilitySnapshot
        >

    init(
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            SettingsSearchScopeAvailabilitySnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: \.isAppOnlyProjection,
            describe: \.diagnosticSummary
        )
    }

    func start() {
        conditionOwner.start()
    }

    func requestReadback(
        source: FlowTabUITestConditionObservationSource
    ) {
        conditionOwner.requestReadback(source: source)
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        SettingsSearchScopeAvailabilitySnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        SettingsSearchScopeAvailabilitySnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        SettingsSearchScopeAvailabilitySnapshot
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
    func assertSettingsSearchWindowScopeUnavailable(
        in app: XCUIApplication,
        trigger: () -> Void
    ) {
        let observation =
            makeSettingsSearchScopeAvailabilityObservation(
                in: app
            )
        observation.start()
        defer { observation.cancel() }

        trigger()
        observation.requestReadback(source: .triggerReadback)

        XCTAssertNotNil(
            observation.waitForResolution(
                timeout:
                    SettingsSearchScopeAvailabilityUITestPolicy
                        .projectionWatchdog
            ),
            "Settings Search app-only scope projection watchdog expired. "
                + observation.diagnosticSummary
        )
    }

    private func makeSettingsSearchScopeAvailabilityObservation(
        in app: XCUIApplication
    ) -> SettingsSearchScopeAvailabilityObservationOwner {
        let scopeControl = element(
            in: app,
            identifier: Identifier.settingsSearchDefaultScope
        )
        let summary = element(
            in: app,
            identifier: Identifier.settingsSearchSummary
        )
        let windowOption = app.descendants(matching: .any)
            .matching(
                identifier:
                    "\(Identifier.settingsSearchDefaultScope)"
                    + ".option.window"
            )
            .firstMatch

        return SettingsSearchScopeAvailabilityObservationOwner(
            readback: {
                let scopeControlExists = scopeControl.exists
                let summaryExists = summary.exists
                return SettingsSearchScopeAvailabilitySnapshot(
                    scopeControlExists: scopeControlExists,
                    scopeControlValue: scopeControlExists
                        ? self.elementStringValue(scopeControl)
                        : "",
                    scopeControlEnabled: scopeControlExists
                        && scopeControl.isEnabled,
                    summaryExists: summaryExists,
                    summaryText: summaryExists
                        ? self.elementStringValue(summary)
                        : "",
                    windowOptionExists: windowOption.exists
                )
            }
        )
    }
}
