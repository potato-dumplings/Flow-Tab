import ApplicationServices
import AppKit
import CoreGraphics
import XCTest

extension FlowTabUITests {
    private var spaceFixtureBundleIdentifier: String {
        "io.github.potato-dumplings.flowtab.spacefixture"
    }

    private var spaceFixtureHomeAppAccessibilityIdentifier: String {
        "flowtab.home.app.io-github-potato-dumplings-flowtab-spacefixture"
    }

    private var spaceFixtureWorkflowReadyAccessibilityIdentifier: String {
        "flowtab.spacefixture.workflow.ready"
    }

    private var spaceFixtureWorkflowSummaryAccessibilityIdentifier: String {
        "flowtab.spacefixture.workflow.summary"
    }

    func makeSpaceFixtureApp(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: spaceFixtureBundleIdentifier)
        app.launchArguments += additionalArguments
        return app
    }

    func terminateSpaceFixtureAppIfRunning() {
        let app = XCUIApplication(bundleIdentifier: spaceFixtureBundleIdentifier)
        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
    }

    func launchSpaceFixtureWorkflow(
        windowCount: Int = 3,
        fullscreenWindowIndex: Int? = 3,
        titlePrefix: String = "Workflow",
        enterFullscreenDelayMilliseconds: Int = 1_500
    ) -> XCUIApplication {
        terminateSpaceFixtureAppIfRunning()

        var additionalArguments = [
            "--window-count", String(windowCount),
            "--window-title-prefix", titlePrefix,
            "--staggered-layout",
            "--enter-fullscreen-delay-ms", String(enterFullscreenDelayMilliseconds),
            "--preserve-desktop-after-fullscreen"
        ]
        if let fullscreenWindowIndex {
            additionalArguments += ["--fullscreen-window-index", String(fullscreenWindowIndex)]
        }

        let app = makeSpaceFixtureApp(additionalArguments: additionalArguments)
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        waitForSpaceFixtureWorkflowToStabilize(
            in: app,
            windowCount: windowCount,
            titlePrefix: titlePrefix,
            fullscreenWindowIndex: fullscreenWindowIndex,
            settleTimeout: max(4.5, Double(enterFullscreenDelayMilliseconds) / 1_000 + 3.5)
        )

        return app
    }

    func waitForSpaceFixtureWorkflowToStabilize(
        in app: XCUIApplication,
        windowCount: Int,
        titlePrefix: String,
        fullscreenWindowIndex: Int?,
        settleTimeout: TimeInterval
    ) {
        let readyLabel = element(in: app, identifier: spaceFixtureWorkflowReadyAccessibilityIdentifier)
        XCTAssertTrue(readyLabel.waitForExistence(timeout: 8))
        XCTAssertEqual(readyLabel.label, "Ready")

        let summaryLabel = element(in: app, identifier: spaceFixtureWorkflowSummaryAccessibilityIdentifier)
        XCTAssertTrue(summaryLabel.waitForExistence(timeout: 8))
        assertValue(
            of: summaryLabel,
            equals: expectedSpaceFixtureWorkflowSummary(titlePrefix: titlePrefix, windowCount: windowCount),
            timeout: 8
        )

        if let fullscreenWindowIndex {
            let fullscreenMarker = element(
                in: app,
                identifier: "flowtab.spacefixture.window.mode.\(fullscreenWindowIndex)"
            )
            XCTAssertTrue(fullscreenMarker.waitForExistence(timeout: 8))
            XCTAssertEqual(fullscreenMarker.label, "Fullscreen Target")
        }

        // XCTest can observe the fixture window metadata before macOS finishes the
        // fullscreen Space transition, so give the system a wider settle window
        // before FlowTab samples the real runtime topology.
        RunLoop.current.run(until: Date().addingTimeInterval(settleTimeout))
    }

    func makeRealRuntimeFlowTabApp(additionalArguments: [String] = []) -> XCUIApplication {
        makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "-showPermissionReminder", "NO"
            ] + additionalArguments
        )
    }

    func testSpaceFixtureAppShowsConfiguredWindowTitles() throws {
        terminateSpaceFixtureAppIfRunning()

        let app = makeSpaceFixtureApp(
            additionalArguments: [
                "--window-count", "3",
                "--window-title-prefix", "UITest",
                "--staggered-layout"
            ]
        )
        app.launch()
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        waitForSpaceFixtureWorkflowToStabilize(
            in: app,
            windowCount: 3,
            titlePrefix: "UITest",
            fullscreenWindowIndex: nil,
            settleTimeout: 1
        )
        XCTAssertTrue(element(in: app, identifier: "flowtab.spacefixture.window.mode.1").waitForExistence(timeout: 5))
    }

    func testSpaceFixtureAppMarksFullscreenTargetWindowBeforeTransition() throws {
        terminateSpaceFixtureAppIfRunning()

        let app = makeSpaceFixtureApp(
            additionalArguments: [
                "--window-count", "2",
                "--window-title-prefix", "Targeted",
                "--fullscreen-window-index", "2",
                "--enter-fullscreen-delay-ms", "1500",
                "--staggered-layout"
            ]
        )
        app.launch()
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        waitForSpaceFixtureWorkflowToStabilize(
            in: app,
            windowCount: 2,
            titlePrefix: "Targeted",
            fullscreenWindowIndex: 2,
            settleTimeout: 1
        )
        XCTAssertTrue(element(in: app, identifier: "flowtab.spacefixture.window.mode.2").waitForExistence(timeout: 5))
        XCTAssertEqual(element(in: app, identifier: "flowtab.spacefixture.window.mode.2").label, "Fullscreen Target")
    }

    func testHomePageShowsRealSpaceFixtureWorkflowWindows() throws {
        guard assertRealSpaceFixtureWorkflowPrerequisites() else { return }

        let titlePrefix = "Workflow"
        let fixtureApp = launchSpaceFixtureWorkflow(
            windowCount: 3,
            fullscreenWindowIndex: 3,
            titlePrefix: titlePrefix,
            enterFullscreenDelayMilliseconds: 5_000
        )
        defer {
            if fixtureApp.state == .runningForeground || fixtureApp.state == .runningBackground {
                fixtureApp.terminate()
            }
        }

        let app = makeRealRuntimeFlowTabApp()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))

        XCTAssertTrue(
            tapFirstHittable(in: app.buttons.matching(identifier: Identifier.homeTabButton), timeout: 10)
        )

        let fixtureAppRows = app.buttons.matching(identifier: spaceFixtureHomeAppAccessibilityIdentifier)
        let fixtureAppRow = fixtureAppRows.firstMatch
        XCTAssertTrue(fixtureAppRow.waitForExistence(timeout: 20))
        assertValue(of: fixtureAppRow, equals: "3w", timeout: 20)
        XCTAssertTrue(
            tapFirstHittable(in: fixtureAppRows, timeout: 20),
            "FlowTab did not surface the real space fixture app on the home page"
        )
    }

    private func expectedSpaceFixtureWorkflowSummary(
        titlePrefix: String,
        windowCount: Int
    ) -> String {
        (1...windowCount).map { "\(titlePrefix) \($0)" }.joined(separator: " | ")
    }

    private func assertRealSpaceFixtureWorkflowPrerequisites() -> Bool {
        var missingPermissions: [String] = []
        if !AXIsProcessTrusted() {
            missingPermissions.append("Accessibility")
        }
        if !CGPreflightScreenCaptureAccess() {
            missingPermissions.append("Screen Recording")
        }
        guard !missingPermissions.isEmpty else { return true }

        XCTFail(
            """
            Real Space Fixture workflow requires real macOS permissions before it can run.
            Missing: \(missingPermissions.joined(separator: ", ")).
            Grant access in System Settings > Privacy & Security, then rerun this UI test.
            """
        )
        return false
    }
}
