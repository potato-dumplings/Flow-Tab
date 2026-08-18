import Foundation
import XCTest

private enum
    FlowTabUITestSettingsEnglishAppearanceProjectionObservationTestPolicy
{
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSettingsEnglishAppearanceProjectionPolicyUsesNamedWatchdog() {
        let watchdog =
            FlowTabUITestSettingsEnglishAppearanceProjectionPolicy
                .projectionWatchdog
        XCTAssertEqual(watchdog, 17)
        XCTAssertTrue(watchdog.isFinite)
        XCTAssertGreaterThan(watchdog, 0)
    }

    func testSettingsEnglishAppearanceProjectionRequiresCompleteSnapshot() {
        XCTAssertTrue(
            settingsEnglishAppearanceProjectionSnapshot()
                .isExactProjection
        )
        XCTAssertFalse(
            settingsEnglishAppearanceProjectionSnapshot(
                appState: .runningBackground
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsEnglishAppearanceProjectionSnapshot(
                settingsContentExists: false
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsEnglishAppearanceProjectionSnapshot(
                pageTitleExists: false
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsEnglishAppearanceProjectionSnapshot(
                pageSubtitleExists: false
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsEnglishAppearanceProjectionSnapshot(
                appearanceTitleExists: false
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsEnglishAppearanceProjectionSnapshot(
                themeModeTitleExists: false
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsEnglishAppearanceProjectionSnapshot(
                priorPageSubtitleExists: true,
                priorPageSubtitleValue: "基础显示设置、快捷键与权限"
            ).isExactProjection
        )
    }

    func testSettingsEnglishAppearanceProjectionAcceptsInitialExactEvidence() {
        let owner =
            FlowTabUITestSettingsEnglishAppearanceProjectionObservationOwner(
                observationRegistration: nil,
                readback: {
                    self.settingsEnglishAppearanceProjectionSnapshot()
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
    }

    func testSettingsEnglishAppearanceProjectionRequiresPostTriggerEvidence() {
        var acceptsEvidence = false
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsEnglishAppearanceProjectionObservationOwner(
                acceptsEvidence: { acceptsEvidence },
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    self.settingsEnglishAppearanceProjectionSnapshot()
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)
        XCTAssertNil(owner.resolvedEvidence)

        acceptsEvidence = true
        owner.requestReadback(source: .triggerReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSettingsEnglishAppearanceProjectionUsesLaterEvidenceAndCancels() {
        var snapshot =
            settingsEnglishAppearanceProjectionSnapshot(
                pageSubtitleExists: false,
                appearanceTitleExists: false,
                themeModeTitleExists: false,
                priorPageSubtitleExists: true,
                priorPageSubtitleValue: "基础显示设置、快捷键与权限"
            )
        var readback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsEnglishAppearanceProjectionObservationOwner(
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
                settingsEnglishAppearanceProjectionSnapshot(
                    priorPageSubtitleExists: true,
                    priorPageSubtitleValue:
                        "基础显示设置、快捷键与权限"
                )
            readback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = settingsEnglishAppearanceProjectionSnapshot()
        readback?(.scheduledReadback)
        readback?(.triggerReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSettingsEnglishAppearanceProjectionRejectsStaleGenerationsUnderPressure() {
        for _ in
            0..<FlowTabUITestSettingsEnglishAppearanceProjectionObservationTestPolicy
                .pressureIterations
        {
            var snapshot =
                settingsEnglishAppearanceProjectionSnapshot(
                    pageSubtitleExists: false,
                    priorPageSubtitleExists: true,
                    priorPageSubtitleValue:
                        "基础显示设置、快捷键与权限"
                )
            var readbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner =
                FlowTabUITestSettingsEnglishAppearanceProjectionObservationOwner(
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

            snapshot = settingsEnglishAppearanceProjectionSnapshot()
            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            readbacks[1](.scheduledReadback)
            readbacks[1](.triggerReadback)
            XCTAssertEqual(owner.resolvedEvidence?.generation, 2)
            owner.cancel()
        }
    }

    func testSettingsEnglishAppearanceProjectionWatchdogReportsFinalEvidence() {
        let owner =
            FlowTabUITestSettingsEnglishAppearanceProjectionObservationOwner(
                observationRegistration: nil,
                readback: {
                    self.settingsEnglishAppearanceProjectionSnapshot(
                        themeModeTitleExists: false,
                        priorPageSubtitleExists: true,
                        priorPageSubtitleValue:
                            "基础显示设置、快捷键与权限"
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsEnglishAppearanceProjectionObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("source=watchdogReadback")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("themeModeTitleExists=false")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("priorPageSubtitleExists=true")
        )
    }

    private func settingsEnglishAppearanceProjectionSnapshot(
        appState: XCUIApplication.State = .runningForeground,
        settingsContentExists: Bool = true,
        pageTitleExists: Bool = true,
        pageTitleValue: String? = "Settings",
        pageSubtitleExists: Bool = true,
        pageSubtitleValue: String? = "Display, hotkeys, and permissions",
        appearanceTitleExists: Bool = true,
        appearanceTitleValue: String? = "Appearance",
        themeModeTitleExists: Bool = true,
        themeModeTitleValue: String? = "Theme mode",
        priorPageSubtitleExists: Bool = false,
        priorPageSubtitleValue: String? = nil
    ) -> FlowTabUITestSettingsEnglishAppearanceProjectionSnapshot {
        FlowTabUITestSettingsEnglishAppearanceProjectionSnapshot(
            appState: appState,
            settingsContentExists: settingsContentExists,
            pageTitleExists: pageTitleExists,
            pageTitleValue: pageTitleValue,
            pageSubtitleExists: pageSubtitleExists,
            pageSubtitleValue: pageSubtitleValue,
            appearanceTitleExists: appearanceTitleExists,
            appearanceTitleValue: appearanceTitleValue,
            themeModeTitleExists: themeModeTitleExists,
            themeModeTitleValue: themeModeTitleValue,
            priorPageSubtitleExists: priorPageSubtitleExists,
            priorPageSubtitleValue: priorPageSubtitleValue
        )
    }
}
