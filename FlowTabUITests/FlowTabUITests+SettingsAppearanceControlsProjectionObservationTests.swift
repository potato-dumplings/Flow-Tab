import Foundation
import XCTest

private enum
    FlowTabUITestSettingsAppearanceControlsProjectionObservationTestPolicy
{
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSettingsAppearanceControlsProjectionPolicyUsesNamedWatchdog() {
        let watchdog =
            FlowTabUITestSettingsAppearanceControlsProjectionPolicy
                .projectionWatchdog
        XCTAssertEqual(watchdog, 20)
        XCTAssertTrue(watchdog.isFinite)
        XCTAssertGreaterThan(watchdog, 0)
    }

    func testSettingsAppearanceControlsProjectionRequiresCompleteSnapshot() {
        XCTAssertTrue(
            settingsAppearanceControlsProjectionSnapshot()
                .isExactProjection
        )
        XCTAssertFalse(
            settingsAppearanceControlsProjectionSnapshot(
                appState: .runningBackground
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsAppearanceControlsProjectionSnapshot(
                settingsContentExists: false
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsAppearanceControlsProjectionSnapshot(
                shortcutExists: false,
                shortcutIsOn: nil
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsAppearanceControlsProjectionSnapshot(
                shortcutIsOn: nil
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsAppearanceControlsProjectionSnapshot(
                currentAppExists: false,
                currentAppIsOn: nil
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsAppearanceControlsProjectionSnapshot(
                currentAppIsOn: true
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsAppearanceControlsProjectionSnapshot(
                currentAppTitleExists: false
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsAppearanceControlsProjectionSnapshot(
                currentAppDescriptionExists: false
            ).isExactProjection
        )
    }

    func testSettingsAppearanceControlsProjectionAcceptsInitialExactEvidence() {
        let owner =
            FlowTabUITestSettingsAppearanceControlsProjectionObservationOwner(
                observationRegistration: nil,
                readback: {
                    self.settingsAppearanceControlsProjectionSnapshot()
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
    }

    func testSettingsAppearanceControlsProjectionRequiresPostTriggerEvidence() {
        var acceptsEvidence = false
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsAppearanceControlsProjectionObservationOwner(
                acceptsEvidence: { acceptsEvidence },
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    self.settingsAppearanceControlsProjectionSnapshot()
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.latestEvidence?.source,
            .initialReadback
        )
        XCTAssertNil(owner.resolvedEvidence)

        acceptsEvidence = true
        owner.requestReadback(source: .triggerReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSettingsAppearanceControlsProjectionUsesLaterEvidenceAndCancels() {
        var snapshot =
            settingsAppearanceControlsProjectionSnapshot(
                settingsContentExists: false,
                shortcutExists: false,
                shortcutIsOn: nil,
                currentAppExists: false,
                currentAppIsOn: nil,
                currentAppTitleExists: false,
                currentAppDescriptionExists: false
            )
        var readback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsAppearanceControlsProjectionObservationOwner(
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

        for _ in 0..<20 {
            snapshot =
                settingsAppearanceControlsProjectionSnapshot(
                    currentAppIsOn: true,
                    currentAppDescriptionExists: false
                )
            readback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = settingsAppearanceControlsProjectionSnapshot()
        readback?(.scheduledReadback)
        readback?(.triggerReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSettingsAppearanceControlsProjectionRejectsStaleGenerationsUnderPressure() {
        for _ in
            0..<FlowTabUITestSettingsAppearanceControlsProjectionObservationTestPolicy
                .pressureIterations
        {
            var snapshot =
                settingsAppearanceControlsProjectionSnapshot(
                    settingsContentExists: false,
                    currentAppTitleExists: false
                )
            var readbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner =
                FlowTabUITestSettingsAppearanceControlsProjectionObservationOwner(
                    observationRegistration: { callback in
                        readbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: { snapshot }
                )
            owner.start()
            let staleReadback = readbacks[0]
            owner.cancel()
            owner.start()

            snapshot = settingsAppearanceControlsProjectionSnapshot()
            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            readbacks[1](.scheduledReadback)
            readbacks[1](.triggerReadback)
            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                2
            )
            owner.cancel()
        }
    }

    func testSettingsAppearanceControlsProjectionWatchdogReportsFinalEvidence() {
        let owner =
            FlowTabUITestSettingsAppearanceControlsProjectionObservationOwner(
                observationRegistration: nil,
                readback: {
                    self.settingsAppearanceControlsProjectionSnapshot(
                        currentAppIsOn: true,
                        currentAppDescriptionExists: false
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsAppearanceControlsProjectionObservationTestPolicy
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
                "currentAppToggleIsOn=Optional(true)"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "currentAppDescriptionExists=false"
            )
        )
    }

    private func settingsAppearanceControlsProjectionSnapshot(
        appState: XCUIApplication.State = .runningForeground,
        settingsContentExists: Bool = true,
        shortcutExists: Bool = true,
        shortcutHittable: Bool = true,
        shortcutIsOn: Bool? = true,
        shortcutValue: String? = "1",
        currentAppExists: Bool = true,
        currentAppHittable: Bool = true,
        currentAppIsOn: Bool? = false,
        currentAppValue: String? = "0",
        currentAppTitleExists: Bool = true,
        currentAppTitleValue: String? = "像普通应用一样显示",
        currentAppDescriptionExists: Bool = true,
        currentAppDescriptionValue: String? =
            "关闭后，当前应用将仅作为菜单栏辅助应用运行。"
    ) -> FlowTabUITestSettingsAppearanceControlsProjectionSnapshot {
        FlowTabUITestSettingsAppearanceControlsProjectionSnapshot(
            appState: appState,
            settingsContentExists: settingsContentExists,
            shortcutHintToggleExists: shortcutExists,
            shortcutHintToggleHittable: shortcutHittable,
            shortcutHintToggleIsOn: shortcutIsOn,
            shortcutHintToggleValue: shortcutValue,
            currentAppToggleExists: currentAppExists,
            currentAppToggleHittable: currentAppHittable,
            currentAppToggleIsOn: currentAppIsOn,
            currentAppToggleValue: currentAppValue,
            currentAppTitleExists: currentAppTitleExists,
            currentAppTitleValue: currentAppTitleValue,
            currentAppDescriptionExists: currentAppDescriptionExists,
            currentAppDescriptionValue: currentAppDescriptionValue
        )
    }
}
