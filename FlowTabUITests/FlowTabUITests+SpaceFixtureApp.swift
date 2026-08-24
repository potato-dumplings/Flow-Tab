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
        "flowtab.home.app.\(bundleIdentifier.flowTabUITestAccessibilityIdentifierComponent)"
    }

    var switcherAppAccessibilityIdentifier: String {
        "flowtab.switcher.app.\(bundleIdentifier.flowTabUITestAccessibilityIdentifierComponent)"
    }

    var switcherSearchAppAccessibilityIdentifier: String {
        "flowtab.switcher.search.app.\(bundleIdentifier.flowTabUITestAccessibilityIdentifierComponent)"
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

}

extension FlowTabUITests {
    var spaceFixtureAppIdentity: SpaceFixtureAppIdentity {
        SpaceFixtureAppIdentity.configured()
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
            terminateSpaceFixtureApplicationAndWait(
                app,
                identity: identity
            )
        }
    }

    func launchSpaceFixtureApplicationAndWaitForForeground(
        _ app: XCUIApplication,
        timeout: TimeInterval =
            FlowTabUITestSupportWatchdogPolicy
                .spaceFixtureForegroundActivation
    ) {
        app.launch()
        if app.wait(
            for: .runningForeground,
            timeout: min(
                timeout,
                FlowTabUITestSupportWatchdogPolicy
                    .spaceFixtureInitialForegroundObservation
            )
        ) {
            return
        }
        app.activate()
        let becameForeground = app.wait(
            for: .runningForeground,
            timeout: timeout
        )
        XCTAssertTrue(
            becameForeground,
            "Space fixture foreground watchdog expired. "
                + "finalState=\(String(describing: app.state))"
        )
    }

    func launchSpaceFixtureWorkflow(
        identity: SpaceFixtureAppIdentity = .configured(),
        windowCount: Int = 3,
        fullscreenWindowIndex: Int? = 3,
        titlePrefix: String = "Workflow",
        enterFullscreenDelayMilliseconds: Int = 1_500,
        terminationDelayMilliseconds: Int = 0,
        closeWindowIndex: Int? = nil,
        closeWindowDelayMilliseconds: Int = 0,
        deferredOpenWindowIndex: Int? = nil,
        fixtureAdditionalArguments: [String] = []
    ) -> XCUIApplication {
        terminateSpaceFixtureAppIfRunning(identity: identity)
        let readinessRoute =
            makeSpaceFixtureWorkflowReadinessRoute()
        let readinessObservation =
            SpaceFixtureWorkflowReadinessObservationOwner(
                route: readinessRoute
            )
        readinessObservation.start()
        defer { readinessObservation.cancel() }

        var additionalArguments = [
            "--window-count", String(windowCount),
            "--window-title-prefix", titlePrefix,
            "--staggered-layout",
            "--enter-fullscreen-delay-ms", String(enterFullscreenDelayMilliseconds),
            "--terminate-delay-ms", String(terminationDelayMilliseconds),
            "--preserve-desktop-after-fullscreen"
        ]
        if let fullscreenWindowIndex {
            additionalArguments += ["--fullscreen-window-index", String(fullscreenWindowIndex)]
        }
        if let closeWindowIndex {
            additionalArguments += [
                "--close-window-index", String(closeWindowIndex),
                "--close-window-delay-ms", String(closeWindowDelayMilliseconds)
            ]
        }
        if let deferredOpenWindowIndex {
            additionalArguments += [
                "--deferred-open-window-index",
                String(deferredOpenWindowIndex)
            ]
        }
        additionalArguments += fixtureAdditionalArguments
        additionalArguments +=
            readinessRoute.fixtureLaunchArguments

        let app = makeSpaceFixtureApp(identity: identity, additionalArguments: additionalArguments)
        launchSpaceFixtureApplicationAndWaitForForeground(app)
        let readinessWatchdog =
            SpaceFixtureWorkflowReadinessUITestPolicy
                .watchdog(
                    enterFullscreenDelayMilliseconds:
                        enterFullscreenDelayMilliseconds
                )
        let initialWindowPlanIndices = (1...windowCount).filter {
            $0 != deferredOpenWindowIndex
        }
        let initialFullscreenWindowIndex =
            fullscreenWindowIndex == deferredOpenWindowIndex
                ? nil
                : fullscreenWindowIndex
        guard let readinessEvidence =
            waitForSpaceFixtureWorkflowReadinessEvidence(
                observation: readinessObservation,
                identity: identity,
                windowCount: windowCount,
                fullscreenWindowIndex:
                    initialFullscreenWindowIndex,
                expectedWindowPlanIndices:
                    initialWindowPlanIndices,
                timeout: readinessWatchdog
            )
        else {
            return app
        }
        waitForSpaceFixtureWorkflowReadiness(
            in: app,
            expectedWindowTitles: expectedSpaceFixtureWorkflowWindowTitles(
                titlePrefix: titlePrefix,
                windowCount: windowCount
            ).enumerated().compactMap { offset, title in
                initialWindowPlanIndices.contains(offset + 1)
                    ? title
                    : nil
            },
            fullscreenWindowIndex: initialFullscreenWindowIndex,
            readinessTimeout: readinessWatchdog,
            readinessEvidence: readinessEvidence
        )

        return app
    }

    func terminateSpaceFixtureApplicationAndWait(
        _ app: XCUIApplication,
        identity: SpaceFixtureAppIdentity,
        timeout: TimeInterval = 5
    ) {
        terminateSpaceFixtureApplicationAndWait(
            app,
            targetDescription:
                identity.bundleIdentifier,
            timeout: timeout
        )
    }

    func terminateSpaceFixtureApplicationAndWait(
        _ app: XCUIApplication,
        targetDescription: String = "space-fixture application",
        timeout: TimeInterval = 5
    ) {
        let evidence =
            terminateFlowTabUITestApplication(
                app,
                targetDescription: targetDescription,
                timeout: timeout
            )
        XCTAssertTrue(
            evidence.isSatisfied,
            "Space fixture termination failed. "
                + evidence.diagnosticSummary
        )
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
            "flowtab.home.app.\("com.example.chrome.fixture".flowTabUITestAccessibilityIdentifierComponent)"
        )
    }

    func testSpaceFixtureAppIdentityFallsBackToDefaultBundleIdentifierWithoutOverrides() {
        let identity = SpaceFixtureAppIdentity.configured(environment: [:])

        XCTAssertNil(identity.appURL)
        XCTAssertEqual(identity.bundleIdentifier, SpaceFixtureAppIdentity.defaultBundleIdentifier)
        XCTAssertEqual(
            identity.homeAppAccessibilityIdentifier,
            "flowtab.home.app.\(SpaceFixtureAppIdentity.defaultBundleIdentifier.flowTabUITestAccessibilityIdentifierComponent)"
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
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                terminateSpaceFixtureApplicationAndWait(
                    app,
                    identity: identity
                )
            }
        }
        assertSpaceFixtureWindowModePublication(
            in: app,
            windowIndex: 1,
            expectedLabel: "Standard Window"
        ) {
            launchSpaceFixtureApplicationAndWaitForForeground(app)
            waitForSpaceFixtureWorkflowReadiness(
                in: app,
                windowCount: 3,
                titlePrefix: "UITest",
                fullscreenWindowIndex: nil,
                readinessTimeout:
                    SpaceFixtureWorkflowReadinessUITestPolicy
                        .defaultWatchdog
            )
        }
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
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                terminateSpaceFixtureApplicationAndWait(
                    app,
                    identity: identity
                )
            }
        }
        assertSpaceFixtureWindowModePublication(
            in: app,
            windowIndex: 2,
            expectedLabel: "Fullscreen Target"
        ) {
            launchSpaceFixtureApplicationAndWaitForForeground(app)
        }
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

}
