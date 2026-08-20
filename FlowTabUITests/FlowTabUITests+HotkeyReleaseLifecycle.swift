import Carbon
import CoreGraphics
import XCTest

private enum FlowTabUITestHotkeyReleaseLifecycleWatchdog {
    static let panelPresentation: TimeInterval = 5
}

extension FlowTabUITests {
    func testPhysicalOptionTabMainKeyReleaseKeepsPanelUntilOptionRelease() {
        let launchLogSnapshot = makeRuntimeLogFileSnapshot()
        defer { launchLogSnapshot.cancel() }
        let app = makeApp(
            additionalArguments: hotkeyEffectArguments(
                resetDefaults: true,
                usesSystemAccessibilityPermission: true
            ) + [
                "--flowtab-ui-listen-switcher-trigger",
                "-showPermissionReminder",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(app)
        defer { app.terminate() }

        waitForRuntimeLogFiles(
            containing: ["mainRoute=carbon"],
            since: launchLogSnapshot
        )
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        assertTriggerMakesApplicationFrontmost(
            "com.apple.finder",
            timeout:
                FlowTabUITestHotkeyReleaseLifecycleWatchdog
                    .panelPresentation,
            message: "Physical Option+Tab must begin from another application."
        ) {
            finder.activate()
        }

        let summary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        XCUIElement.perform(withKeyModifiers: .option) {
            let firstPress = makeRuntimeLogFileSnapshot()
            defer { firstPress.cancel() }
            finder.typeKey(.tab, modifierFlags: .option)
            waitForRuntimeLogFiles(
                containing: [
                    "dispatch phase=pressed dir=forward",
                    "hotkeyPressed dir=forward panelVisible=0 action=show",
                    "dispatched phase=released dir=forward"
                ],
                since: firstPress
            )
            XCTAssertTrue(
                summary.waitForExistence(
                    timeout:
                        FlowTabUITestHotkeyReleaseLifecycleWatchdog
                            .panelPresentation
                )
            )
            XCTAssertTrue(
                summary.exists,
                "Releasing Tab while Option remains held must keep the panel active."
            )

            let secondPress = makeRuntimeLogFileSnapshot()
            defer { secondPress.cancel() }
            app.typeKey(.tab, modifierFlags: .option)
            waitForRuntimeLogFiles(
                containing: [
                    "hotkeyPressed dir=forward panelVisible=1 "
                        + "modifierPressed=1 action=advance"
                ],
                since: secondPress
            )
            XCTAssertTrue(summary.exists)
        }
        XCTAssertTrue(
            waitForNonExistence(
                summary,
                timeout:
                    FlowTabUITestHotkeyReleaseLifecycleWatchdog
                        .panelPresentation
            )
        )
    }

    func testOptionTabReleaseAfterHiddenCompletionAllowsNextSession() {
        let app = makeApp(
            additionalArguments: hotkeyEffectArguments(
                resetDefaults: true,
                usesSystemAccessibilityPermission: true
            ) + [
                "--flowtab-ui-enable-shortcut-event-injection",
                "--flowtab-ui-listen-switcher-trigger",
                "-showPermissionReminder",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(app)
        defer { app.terminate() }
        defer {
            setRuntimePressedKeySet(
                in: app,
                keyCodes: [],
                modifierFlags: []
            )
        }

        let summary = element(
            in: app,
            identifier: Identifier.switcherSummary
        )
        let firstPress = makeRuntimeLogFileSnapshot()
        defer { firstPress.cancel() }
        app.activate()
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [CGKeyCode(kVK_Tab)],
            modifierFlags: .option
        )
        waitForRuntimeLogFiles(
            containing: [
                "dispatch phase=pressed dir=forward",
                "hotkeyPressed dir=forward panelVisible=0 action=show"
            ],
            since: firstPress
        )
        XCTAssertTrue(
            summary.waitForExistence(
                timeout:
                    FlowTabUITestHotkeyReleaseLifecycleWatchdog
                        .panelPresentation
            )
        )

        setRuntimePressedKeySet(
            in: app,
            keyCodes: [],
            modifierFlags: .option
        )
        postFlowTabUITestSwitcherCommandAndWaitForDelivery(
            .confirm,
            traceLabel: "hidden-release.first-confirm"
        )
        XCTAssertTrue(
            waitForNonExistence(
                summary,
                timeout:
                    FlowTabUITestHotkeyReleaseLifecycleWatchdog
                        .panelPresentation
            )
        )

        let hiddenRelease = makeRuntimeLogFileSnapshot()
        defer { hiddenRelease.cancel() }
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [],
            modifierFlags: []
        )
        waitForRuntimeLogFiles(
            containing: [
                "hotkeyReplaySuppression end "
                    + "trigger=selection_end:finishSelection"
            ],
            since: hiddenRelease
        )

        let secondPress = makeRuntimeLogFileSnapshot()
        defer { secondPress.cancel() }
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [CGKeyCode(kVK_Tab)],
            modifierFlags: .option
        )
        waitForRuntimeLogFiles(
            containing: [
                "hotkeyPressed dir=forward panelVisible=0 action=show"
            ],
            since: secondPress
        )
        XCTAssertTrue(
            summary.waitForExistence(
                timeout:
                    FlowTabUITestHotkeyReleaseLifecycleWatchdog
                        .panelPresentation
            ),
            "Option+Tab must open a new panel after the hidden modifier release."
        )
    }
}
