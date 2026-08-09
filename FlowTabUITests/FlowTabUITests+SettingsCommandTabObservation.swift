import Foundation
import XCTest

private enum FlowTabUITestCommandTabTakeoverObservationPolicy {
    static let markerReadbackCadence: TimeInterval = 0.1
    static let markerWatchdog: TimeInterval = 5
    static let statusProjectionWatchdog: TimeInterval = 5
    static let takeoverConfigurationLogWatchdog: TimeInterval = 10
    static let switcherTriggerLogWatchdog: TimeInterval = 10
    static let defaultsSuiteName =
        "io.github.potato-dumplings.flowtab"
    static let markerKey =
        "commandTabTakeoverPendingRestore"
}

extension FlowTabUITests {
    func testCommandTabSwitcherTriggerLogPolicyPreservesWatchdog() {
        XCTAssertEqual(
            FlowTabUITestCommandTabTakeoverObservationPolicy
                .switcherTriggerLogWatchdog,
            10
        )
    }

    func testCommandTabTakeoverConfigurationLogPolicyPreservesWatchdog() {
        XCTAssertEqual(
            FlowTabUITestCommandTabTakeoverObservationPolicy
                .takeoverConfigurationLogWatchdog,
            10
        )
    }

    func testCommandTabTakeoverStatusProjectionPolicyPreservesWatchdog() {
        XCTAssertEqual(
            FlowTabUITestCommandTabTakeoverObservationPolicy
                .statusProjectionWatchdog,
            5
        )
    }

    func testSettingsCommandTabTakeoverTriggersSwitcherAndRestoresSystemShortcut() throws {
        let app = makeApp(
            additionalArguments:
                hotkeyEffectArguments(resetDefaults: true)
        )
        launchFlowTabUITestApplication(app)
        defer {
            if app.state != .notRunning {
                app.activate()
                app.typeKey("q", modifierFlags: .command)
                if !app.wait(for: .notRunning, timeout: 6) {
                    app.terminate()
                    _ = app.wait(for: .notRunning, timeout: 6)
                }
            }
        }
        openSettingsTab(in: app)

        selectOption(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyMainKey,
            optionIdentifier: "space"
        )
        assertValue(
            of: element(
                in: app,
                identifier: Identifier.settingsHotkeyMainKey
            ),
            equals: "space"
        )

        let activeTakeoverText =
            "已接管系统 Command + Tab"
        let activeTakeoverStatus = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format:
                        "identifier == %@ AND (label CONTAINS %@ OR value CONTAINS %@)",
                    Identifier.settingsHotkeyMainTakeoverStatus,
                    activeTakeoverText,
                    activeTakeoverText
                )
            )
            .firstMatch
        let activeStatusObservation =
            FlowTabUITestConditionObservationOwner(
                observationRegistration:
                    FlowTabUITestConditionReadbackScheduler
                        .mainRunLoopRegistration(
                            cadence:
                                FlowTabUITestConditionObservationPolicy
                                    .xcuiReadbackCadence
                        ),
                readback: { activeTakeoverStatus.exists },
                isSatisfied: { $0 },
                describe: {
                    "identifier="
                        + Identifier.settingsHotkeyMainTakeoverStatus
                        + " exists=\($0)"
                }
            )
        activeStatusObservation.start()
        defer { activeStatusObservation.cancel() }
        guard let activeStatusBaseline =
            activeStatusObservation.latestEvidence
        else {
            XCTFail(
                "Command+Tab takeover status has no baseline. "
                    + activeStatusObservation.diagnosticSummary
            )
            return
        }
        guard !activeStatusBaseline.value else {
            XCTFail(
                "Command+Tab takeover status baseline was already active. "
                    + activeStatusObservation.diagnosticSummary
            )
            return
        }

        let takeoverConfigurationMarkers = [
            "updated main=Command + Tab",
            "system Command+Tab shortcuts disabled for FlowTab takeover",
            "commandTabTakeoverActive=true",
            "hotkeyReloadNotification sender=AppDelegate main=Command + Tab"
        ]
        let takeoverLogBaseline = makeRuntimeLogFileSnapshot()
        defer { takeoverLogBaseline.cancel() }
        let takeoverLogObservation =
            FlowTabUITestRuntimeLogObservationOwner(
                expectation:
                    .allMarkers(takeoverConfigurationMarkers),
                observationRegistration:
                    takeoverLogBaseline.observationRegistration(),
                readback: takeoverLogBaseline.makeReadback
            )
        takeoverLogObservation.start()
        defer { takeoverLogObservation.cancel() }
        guard takeoverLogObservation.resolvedEvidence == nil else {
            XCTFail(
                "Command+Tab configuration logs were present at baseline. "
                    + takeoverLogObservation.diagnosticSummary
            )
            return
        }

        assertCommandTabTakeoverMarker(expectedValue: true) {
            selectOption(
                in: app,
                controlIdentifier:
                    Identifier.settingsHotkeyMainModifier,
                optionIdentifier: "command"
            )
            selectOption(
                in: app,
                controlIdentifier: Identifier.settingsHotkeyMainKey,
                optionIdentifier: "tab"
            )
            assertValue(
                of: element(
                    in: app,
                    identifier:
                        Identifier.settingsHotkeyMainModifier
                ),
                equals: "command"
            )
            assertValue(
                of: element(
                    in: app,
                    identifier: Identifier.settingsHotkeyMainKey
                ),
                equals: "tab"
            )

            guard
                takeoverLogObservation.waitForResolution(
                    timeout:
                        FlowTabUITestCommandTabTakeoverObservationPolicy
                            .takeoverConfigurationLogWatchdog
                ) != nil
            else {
                XCTFail(
                    "Command+Tab configuration log watchdog expired. "
                        + takeoverLogObservation.diagnosticSummary
                )
                return
            }
        }
        activeStatusObservation.requestReadback(
            source: .triggerReadback
        )
        let activeStatusEvidence =
            activeStatusObservation.waitForResolution(
                timeout:
                    FlowTabUITestCommandTabTakeoverObservationPolicy
                        .statusProjectionWatchdog
            )
        XCTAssertNotNil(
            activeStatusEvidence,
            "Command+Tab takeover status projection watchdog expired. "
                + activeStatusObservation.diagnosticSummary
        )
        guard activeStatusEvidence != nil else { return }

        let switcherTriggerMarkers = [
            "hotkeyPressed dir=forward panelVisible=0 action=show",
            "HotKey Forward"
        ]
        let triggerLogBaseline = makeRuntimeLogFileSnapshot()
        defer { triggerLogBaseline.cancel() }
        let triggerLogObservation =
            FlowTabUITestRuntimeLogObservationOwner(
                expectation:
                    .allMarkers(switcherTriggerMarkers),
                observationRegistration:
                    triggerLogBaseline.observationRegistration(),
                readback: triggerLogBaseline.makeReadback
            )
        triggerLogObservation.start()
        defer { triggerLogObservation.cancel() }
        guard triggerLogObservation.resolvedEvidence == nil else {
            XCTFail(
                "Command+Tab trigger logs were present at baseline. "
                    + triggerLogObservation.diagnosticSummary
            )
            return
        }

        app.activate()
        app.typeKey(.tab, modifierFlags: .command)
        guard
            triggerLogObservation.waitForResolution(
                timeout:
                    FlowTabUITestCommandTabTakeoverObservationPolicy
                        .switcherTriggerLogWatchdog
            ) != nil
        else {
            XCTFail(
                "Command+Tab trigger log watchdog expired. "
                    + triggerLogObservation.diagnosticSummary
            )
            return
        }

        assertCommandTabTakeoverMarker(expectedValue: false) {
            app.activate()
            app.typeKey("q", modifierFlags: .command)
            XCTAssertTrue(
                app.wait(for: .notRunning, timeout: 8)
            )
        }

        resetHotkeyDefaultsAfterCommandTabTakeoverTest()
    }

    private func assertCommandTabTakeoverMarker(
        expectedValue: Bool,
        trigger: () -> Void
    ) {
        let defaults =
            UserDefaults(
                suiteName:
                    FlowTabUITestCommandTabTakeoverObservationPolicy
                        .defaultsSuiteName
            ) ?? .standard
        let owner = FlowTabUITestConditionObservationOwner(
            observationRegistration:
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestCommandTabTakeoverObservationPolicy
                                .markerReadbackCadence
                    ),
            readback: {
                defaults.synchronize()
                return defaults.bool(
                    forKey:
                        FlowTabUITestCommandTabTakeoverObservationPolicy
                            .markerKey
                )
            },
            isSatisfied: { $0 == expectedValue },
            describe: {
                "expected=\(expectedValue) actual=\($0)"
            }
        )
        owner.start()
        defer { owner.cancel() }
        let baselineValue = owner.latestEvidence?.value

        guard baselineValue == !expectedValue else {
            XCTFail(
                "Unexpected takeover marker baseline "
                    + "\(String(describing: baselineValue)). "
                    + owner.diagnosticSummary
            )
            return
        }

        trigger()

        guard
            owner.waitForResolution(
                timeout:
                    FlowTabUITestCommandTabTakeoverObservationPolicy
                        .markerWatchdog
            ) != nil
        else {
            XCTFail(
                "Takeover marker did not become \(expectedValue). "
                    + "baseline=\(String(describing: baselineValue)) "
                    + owner.diagnosticSummary
            )
            return
        }
    }

    private func resetHotkeyDefaultsAfterCommandTabTakeoverTest() {
        let cleanupApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "-showPermissionReminder",
                "NO",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(cleanupApp)
        cleanupApp.terminate()
        _ = cleanupApp.wait(for: .notRunning, timeout: 6)
    }
}
