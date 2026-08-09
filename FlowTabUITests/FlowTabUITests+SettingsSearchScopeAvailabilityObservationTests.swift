import Foundation
import XCTest

private enum SettingsSearchScopeAvailabilityObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSettingsSearchScopeAvailabilityPolicyUsesNamedProjectionWatchdog() {
        XCTAssertEqual(
            SettingsSearchScopeAvailabilityUITestPolicy
                .projectionWatchdog,
            6
        )
    }

    func testSettingsSearchScopeAvailabilityRequiresCompleteAppOnlyProjection() {
        XCTAssertTrue(
            settingsSearchScopeAvailabilitySnapshot(
                summaryText:
                    "Window search requires Accessibility permission. Enable it to choose Window."
            ).isAppOnlyProjection
        )
        XCTAssertTrue(
            settingsSearchScopeAvailabilitySnapshot(
                summaryText:
                    "窗口搜索需要辅助功能权限；授权后可选择窗口范围。"
            ).isAppOnlyProjection
        )

        XCTAssertFalse(
            settingsSearchScopeAvailabilitySnapshot(
                scopeControlExists: false
            ).isAppOnlyProjection
        )
        XCTAssertFalse(
            settingsSearchScopeAvailabilitySnapshot(
                scopeControlValue: "window"
            ).isAppOnlyProjection
        )
        XCTAssertFalse(
            settingsSearchScopeAvailabilitySnapshot(
                scopeControlEnabled: true
            ).isAppOnlyProjection
        )
        XCTAssertFalse(
            settingsSearchScopeAvailabilitySnapshot(
                summaryExists: false
            ).isAppOnlyProjection
        )
        XCTAssertFalse(
            settingsSearchScopeAvailabilitySnapshot(
                summaryText: "Search is enabled."
            ).isAppOnlyProjection
        )
        XCTAssertFalse(
            settingsSearchScopeAvailabilitySnapshot(
                windowOptionExists: true
            ).isAppOnlyProjection
        )
    }

    func testSettingsSearchScopeAvailabilityAcceptsInitialExactProjection() {
        let owner = SettingsSearchScopeAvailabilityObservationOwner(
            observationRegistration: nil,
            readback: {
                self.settingsSearchScopeAvailabilitySnapshot()
            }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
    }

    func testSettingsSearchScopeAvailabilityUsesLaterExactEvidenceAndCancels() {
        var snapshot = settingsSearchScopeAvailabilitySnapshot(
            scopeControlExists: false,
            summaryExists: false
        )
        var readback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner = SettingsSearchScopeAvailabilityObservationOwner(
            observationRegistration: { callback in
                readback = callback
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: { snapshot }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.latestEvidence?.source,
            .initialReadback
        )
        XCTAssertNil(owner.resolvedEvidence)

        for _ in 0..<20 {
            snapshot = self.settingsSearchScopeAvailabilitySnapshot(
                scopeControlEnabled: true,
                summaryExists: false
            )
            readback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = settingsSearchScopeAvailabilitySnapshot()
        readback?(.triggerReadback)
        readback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSettingsSearchScopeAvailabilityRejectsStaleGenerationsUnderPressure() {
        for _ in
            0..<SettingsSearchScopeAvailabilityObservationTestPolicy
                .pressureIterations
        {
            var snapshot = settingsSearchScopeAvailabilitySnapshot(
                scopeControlExists: false,
                summaryExists: false
            )
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner = SettingsSearchScopeAvailabilityObservationOwner(
                observationRegistration: { callback in
                    callbacks.append(callback)
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
            owner.start()
            let staleReadback = callbacks[0]
            owner.cancel()
            owner.start()

            snapshot = settingsSearchScopeAvailabilitySnapshot()
            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            callbacks[1](.scheduledReadback)
            callbacks[1](.triggerReadback)
            XCTAssertEqual(owner.resolvedEvidence?.generation, 2)
            owner.cancel()
        }
    }

    func testSettingsSearchScopeAvailabilityWatchdogReportsFinalEvidence() {
        let owner = SettingsSearchScopeAvailabilityObservationOwner(
            observationRegistration: nil,
            readback: {
                self.settingsSearchScopeAvailabilitySnapshot(
                    scopeControlEnabled: true,
                    summaryText: "Search is enabled."
                )
            }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    SettingsSearchScopeAvailabilityObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "scopeControlEnabled=true"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "summaryText=\"Search is enabled.\""
            )
        )
    }

    private func settingsSearchScopeAvailabilitySnapshot(
        scopeControlExists: Bool = true,
        scopeControlValue: String = "app",
        scopeControlEnabled: Bool = false,
        summaryExists: Bool = true,
        summaryText: String =
            "Window search requires Accessibility permission. Enable it to choose Window.",
        windowOptionExists: Bool = false
    ) -> SettingsSearchScopeAvailabilitySnapshot {
        SettingsSearchScopeAvailabilitySnapshot(
            scopeControlExists: scopeControlExists,
            scopeControlValue: scopeControlValue,
            scopeControlEnabled: scopeControlEnabled,
            summaryExists: summaryExists,
            summaryText: summaryText,
            windowOptionExists: windowOptionExists
        )
    }
}
