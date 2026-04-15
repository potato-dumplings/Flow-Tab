import ApplicationServices
import AppKit
import CoreGraphics
import Foundation
import XCTest

private enum SpaceFixtureEnvironmentKey {
    static let appPath = "FLOWTAB_SPACE_FIXTURE_APP_PATH"
    static let bundleIdentifier = "FLOWTAB_SPACE_FIXTURE_BUNDLE_ID"
}

private struct SpaceFixtureAppIdentity: Equatable {
    static let defaultBundleIdentifier = "io.github.potato-dumplings.flowtab.spacefixture"

    let bundleIdentifier: String
    let appURL: URL?

    var homeAppAccessibilityIdentifier: String {
        "flowtab.home.app.\(bundleIdentifier.spaceFixtureAccessibilitySlug)"
    }

    static func configured(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SpaceFixtureAppIdentity {
        let configuredBundleIdentifier = environment[SpaceFixtureEnvironmentKey.bundleIdentifier]?
            .trimmedSpaceFixtureValue
        let resolvedBundleIdentifier = configuredBundleIdentifier?.isEmpty == false
            ? configuredBundleIdentifier!
            : defaultBundleIdentifier

        guard
            let configuredAppPath = environment[SpaceFixtureEnvironmentKey.appPath]?.trimmedSpaceFixtureValue,
            !configuredAppPath.isEmpty
        else {
            return SpaceFixtureAppIdentity(bundleIdentifier: resolvedBundleIdentifier, appURL: nil)
        }

        let appURL = URL(fileURLWithPath: configuredAppPath).standardizedFileURL
        let bundleIdentifier = configuredBundleIdentifier?.isEmpty == false
            ? configuredBundleIdentifier!
            : Bundle(url: appURL)?.bundleIdentifier ?? defaultBundleIdentifier

        return SpaceFixtureAppIdentity(bundleIdentifier: bundleIdentifier, appURL: appURL)
    }
}

private extension String {
    var trimmedSpaceFixtureValue: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var spaceFixtureAccessibilitySlug: String {
        let replaced = trimmedSpaceFixtureValue
            .lowercased()
            .replacingOccurrences(
                of: #"[^a-z0-9]+"#,
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return replaced.isEmpty ? "item" : replaced
    }
}

extension FlowTabUITests {
    private var spaceFixtureAppIdentity: SpaceFixtureAppIdentity {
        SpaceFixtureAppIdentity.configured()
    }

    private var spaceFixtureWorkflowReadyAccessibilityIdentifier: String {
        "flowtab.spacefixture.workflow.ready"
    }

    private var spaceFixtureWorkflowSummaryAccessibilityIdentifier: String {
        "flowtab.spacefixture.workflow.summary"
    }

    private func makeSpaceFixtureApplication(for identity: SpaceFixtureAppIdentity) -> XCUIApplication {
        if let appURL = identity.appURL {
            return XCUIApplication(url: appURL)
        }
        return XCUIApplication(bundleIdentifier: identity.bundleIdentifier)
    }

    private func makeSpaceFixtureApp(
        identity: SpaceFixtureAppIdentity = .configured(),
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = makeSpaceFixtureApplication(for: identity)
        app.launchArguments += additionalArguments
        return app
    }

    func terminateSpaceFixtureAppIfRunning() {
        terminateSpaceFixtureAppIfRunning(identity: .configured())
    }

    private func terminateSpaceFixtureAppIfRunning(identity: SpaceFixtureAppIdentity) {
        let app = makeSpaceFixtureApplication(for: identity)
        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
    }

    private func launchSpaceFixtureWorkflow(
        identity: SpaceFixtureAppIdentity = .configured(),
        windowCount: Int = 3,
        fullscreenWindowIndex: Int? = 3,
        titlePrefix: String = "Workflow",
        enterFullscreenDelayMilliseconds: Int = 1_500
    ) -> XCUIApplication {
        terminateSpaceFixtureAppIfRunning(identity: identity)

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

        let app = makeSpaceFixtureApp(identity: identity, additionalArguments: additionalArguments)
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

    func testSpaceFixtureAppIdentityUsesEnvironmentOverridesForCustomFixtureVariants() {
        let identity = SpaceFixtureAppIdentity.configured(
            environment: [
                SpaceFixtureEnvironmentKey.appPath: "/tmp/Chrome Fixture.app",
                SpaceFixtureEnvironmentKey.bundleIdentifier: "com.example.chrome.fixture"
            ]
        )

        XCTAssertEqual(identity.appURL, URL(fileURLWithPath: "/tmp/Chrome Fixture.app").standardizedFileURL)
        XCTAssertEqual(identity.bundleIdentifier, "com.example.chrome.fixture")
        XCTAssertEqual(
            identity.homeAppAccessibilityIdentifier,
            "flowtab.home.app.com-example-chrome-fixture"
        )
    }

    func testSpaceFixtureAppIdentityFallsBackToDefaultBundleIdentifierWithoutOverrides() {
        let identity = SpaceFixtureAppIdentity.configured(environment: [:])

        XCTAssertNil(identity.appURL)
        XCTAssertEqual(identity.bundleIdentifier, SpaceFixtureAppIdentity.defaultBundleIdentifier)
        XCTAssertEqual(
            identity.homeAppAccessibilityIdentifier,
            "flowtab.home.app.io-github-potato-dumplings-flowtab-spacefixture"
        )
    }

    func testSpaceFixtureAppShowsConfiguredWindowTitles() throws {
        let identity = spaceFixtureAppIdentity
        terminateSpaceFixtureAppIfRunning(identity: identity)

        let app = makeSpaceFixtureApp(
            identity: identity,
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
        let identity = spaceFixtureAppIdentity
        terminateSpaceFixtureAppIfRunning(identity: identity)

        let app = makeSpaceFixtureApp(
            identity: identity,
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
        let identity = spaceFixtureAppIdentity
        let fixtureApp = launchSpaceFixtureWorkflow(
            identity: identity,
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

        let fixtureAppRows = app.buttons.matching(identifier: identity.homeAppAccessibilityIdentifier)
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
