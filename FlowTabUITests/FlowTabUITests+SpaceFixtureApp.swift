import AppKit
import Foundation
import XCTest

private enum SpaceFixtureEnvironmentKey {
    static let appPath = "FLOWTAB_SPACE_FIXTURE_APP_PATH"
    static let bundleIdentifier = "FLOWTAB_SPACE_FIXTURE_BUNDLE_ID"
}

struct SpaceFixtureAppIdentity: Equatable {
    static let defaultBundleIdentifier = "io.github.potato-dumplings.flowtab.spacefixture"

    let bundleIdentifier: String
    let appURL: URL?

    var homeAppAccessibilityIdentifier: String {
        "flowtab.home.app.\(bundleIdentifier.spaceFixtureAccessibilitySlug)"
    }

    var switcherAppAccessibilityIdentifier: String {
        "flowtab.switcher.app.\(bundleIdentifier.spaceFixtureAccessibilitySlug)"
    }

    var switcherSearchAppAccessibilityIdentifier: String {
        "flowtab.switcher.search.app.\(bundleIdentifier.spaceFixtureAccessibilitySlug)"
    }

    var switcherSearchQuery: String {
        let ignoredTokens = Set(["com", "org", "net", "io", "app", "www"])
        let relevantTokens = bundleIdentifier
            .split(separator: ".")
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && !ignoredTokens.contains($0) }

        let tailTokens = relevantTokens.suffix(2)
        if !tailTokens.isEmpty {
            return tailTokens.joined(separator: " ")
        }
        return "spacefixture"
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
    var spaceFixtureAppIdentity: SpaceFixtureAppIdentity {
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

    func launchSpaceFixtureWorkflow(
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
            expectedWindowTitles: expectedSpaceFixtureWorkflowWindowTitles(
                titlePrefix: titlePrefix,
                windowCount: windowCount
            ),
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
        waitForSpaceFixtureWorkflowToStabilize(
            in: app,
            expectedWindowTitles: expectedSpaceFixtureWorkflowWindowTitles(
                titlePrefix: titlePrefix,
                windowCount: windowCount
            ),
            fullscreenWindowIndex: fullscreenWindowIndex,
            settleTimeout: settleTimeout
        )
    }

    func waitForSpaceFixtureWorkflowToStabilize(
        in app: XCUIApplication,
        expectedWindowTitles: [String],
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
            equals: expectedSpaceFixtureWorkflowSummary(windowTitles: expectedWindowTitles),
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

    func makeRealRuntimeFlowTabApp(
        showsPermissionReminder: Bool = false,
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        var launchArguments = ["--flowtab-ui-reset-defaults"]
        if !showsPermissionReminder {
            launchArguments += ["-showPermissionReminder", "NO"]
        }
        return makeApp(additionalArguments: launchArguments + additionalArguments)
    }

    func expectedSpaceFixtureWorkflowWindowTitles(
        titlePrefix: String,
        windowCount: Int
    ) -> [String] {
        (1...windowCount).map { "\(titlePrefix) \($0)" }
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

    private func expectedSpaceFixtureWorkflowSummary(
        titlePrefix: String,
        windowCount: Int
    ) -> String {
        expectedSpaceFixtureWorkflowSummary(
            windowTitles: expectedSpaceFixtureWorkflowWindowTitles(
                titlePrefix: titlePrefix,
                windowCount: windowCount
            )
        )
    }

    func expectedSpaceFixtureWorkflowSummary(windowTitles: [String]) -> String {
        windowTitles.joined(separator: " | ")
    }

    func assertSpaceFixtureWorkflowPermissionsAvailable() -> Bool {
        let app = makeRealRuntimeFlowTabApp(
            showsPermissionReminder: true,
            additionalArguments: []
        )
        launchFlowTabUITestApplication(app)
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }

        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 12))
        XCTAssertTrue(
            tapFirstHittable(in: app.buttons.matching(identifier: Identifier.homeTabButton), timeout: 10)
        )

        let openSettingsButtons = app.buttons.matching(identifier: Identifier.permissionOpenSettings)
        guard openSettingsButtons.firstMatch.waitForExistence(timeout: 2) else { return true }

        XCTAssertTrue(hasHittableElement(in: openSettingsButtons, timeout: 5))
        XCTAssertTrue(app.buttons.matching(identifier: Identifier.permissionDismiss).firstMatch.waitForExistence(timeout: 5))
        XCTFail(
            """
            Space Fixture workflow requires Accessibility and Screen Recording permissions.
            FlowTab showed the missing-permissions prompt instead of fixture window data.
            """
        )
        return false
    }
}
