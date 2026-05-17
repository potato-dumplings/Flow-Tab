import CoreGraphics
import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testFlowTabAccessibilitySlugNormalizesBundleIdentifierCharacters() {
        XCTAssertEqual(
            "Com.Example Chrome_Fixture".flowTabAccessibilitySlug,
            "com-example-chrome-fixture"
        )
    }

    func testFlowTabAccessibilitySlugFallsBackWhenInputOnlyContainsSeparators() {
        XCTAssertEqual(" -._ ".flowTabAccessibilitySlug, "item")
    }

    func testFlowTabAccessibilityIdentifierComponentKeepsReadableSlug() {
        XCTAssertTrue(
            "Com.Example Chrome_Fixture".flowTabAccessibilityIdentifierComponent
                .hasPrefix("com-example-chrome-fixture.id-")
        )
    }

    func testFlowTabAccessibilityIdentifierComponentSeparatesSlugCollisions() {
        XCTAssertNotEqual(
            "a b".flowTabAccessibilityIdentifierComponent,
            "a-b".flowTabAccessibilityIdentifierComponent
        )
        XCTAssertNotEqual(
            "你好".flowTabAccessibilityIdentifierComponent,
            "世界".flowTabAccessibilityIdentifierComponent
        )
    }

    func testMockWindowIDGenerationIsDeterministicForSameTitle() {
        let first = FlowTabUITestBootstrapper.deterministicMockWindowIDForTesting(title: "Inbox - Gmail")
        let second = FlowTabUITestBootstrapper.deterministicMockWindowIDForTesting(title: "Inbox - Gmail")

        XCTAssertEqual(first, second)
    }

    func testMockWindowIDGenerationNormalizesMissingAndBlankTitles() {
        let missing = FlowTabUITestBootstrapper.deterministicMockWindowIDForTesting(title: nil)
        let blank = FlowTabUITestBootstrapper.deterministicMockWindowIDForTesting(title: "   ")

        XCTAssertEqual(missing, blank)
    }

    func testMockWindowIDGenerationSeparatesRepresentativeTitles() {
        let inbox = FlowTabUITestBootstrapper.deterministicMockWindowIDForTesting(title: "Inbox - Gmail")
        let calendar = FlowTabUITestBootstrapper.deterministicMockWindowIDForTesting(title: "Calendar - Work")

        XCTAssertNotEqual(inbox, calendar)
    }

    func testSpaceFixtureLaunchConfigurationUsesDefaultsWhenArgumentsAreMissing() {
        let configuration = SpaceFixtureLaunchConfiguration(arguments: ["FlowTabSpaceFixture"])

        XCTAssertEqual(configuration.windowCount, SpaceFixtureLaunchConfiguration.defaultWindowCount)
        XCTAssertNil(configuration.fullscreenWindowIndex)
        XCTAssertEqual(configuration.windowTitlePrefix, SpaceFixtureLaunchConfiguration.defaultWindowTitlePrefix)
        XCTAssertFalse(configuration.usesStaggeredLayout)
        XCTAssertEqual(
            configuration.enterFullscreenDelayMilliseconds,
            SpaceFixtureLaunchConfiguration.defaultEnterFullscreenDelayMilliseconds
        )
        XCTAssertFalse(configuration.preservesDesktopAfterFullscreen)
        XCTAssertTrue(configuration.publishesApplicationAccessibilityChildren)
        XCTAssertEqual(configuration.terminationDelayMilliseconds, 0)
    }

    func testSpaceFixtureLaunchConfigurationNormalizesInvalidNumericArguments() {
        let configuration = SpaceFixtureLaunchConfiguration(
            arguments: [
                "FlowTabSpaceFixture",
                "--window-count", "0",
                "--fullscreen-window-index", "9",
                "--window-title-prefix", "  ",
                "--enter-fullscreen-delay-ms", "-25",
                "--terminate-delay-ms", "-40",
                "--suppress-app-accessibility-children"
            ]
        )

        XCTAssertEqual(configuration.windowCount, SpaceFixtureLaunchConfiguration.minimumWindowCount)
        XCTAssertNil(configuration.fullscreenWindowIndex)
        XCTAssertEqual(configuration.windowTitlePrefix, SpaceFixtureLaunchConfiguration.defaultWindowTitlePrefix)
        XCTAssertEqual(configuration.enterFullscreenDelayMilliseconds, 0)
        XCTAssertFalse(configuration.preservesDesktopAfterFullscreen)
        XCTAssertFalse(configuration.publishesApplicationAccessibilityChildren)
        XCTAssertEqual(configuration.terminationDelayMilliseconds, 0)
    }

    func testSpaceFixtureLaunchConfigurationParsesTerminationDelay() {
        let configuration = SpaceFixtureLaunchConfiguration(
            arguments: [
                "FlowTabSpaceFixture",
                "--terminate-delay-ms", "1200"
            ]
        )

        XCTAssertEqual(configuration.terminationDelayMilliseconds, 1200)
    }

    func testSpaceFixtureWindowPlannerCreatesStaggeredPlansAndFullscreenMarker() {
        let configuration = SpaceFixtureLaunchConfiguration(
            windowCount: 3,
            fullscreenWindowIndex: 2,
            windowTitlePrefix: "UITest",
            usesStaggeredLayout: true,
            enterFullscreenDelayMilliseconds: 900,
            preservesDesktopAfterFullscreen: false
        )

        let plans = SpaceFixtureWindowPlanner.makePlans(
            configuration: configuration,
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(plans.map(\.title), ["UITest 1", "UITest 2", "UITest 3"])
        XCTAssertEqual(plans.map(\.isFullscreenTarget), [false, true, false])
        XCTAssertNotEqual(plans[0].frame.origin, plans[1].frame.origin)
        XCTAssertNotEqual(plans[1].frame.origin, plans[2].frame.origin)
        XCTAssertEqual(plans[1].modeText, "Fullscreen Target")
    }

    func testSpaceFixtureLaunchConfigurationLoadsWorkflowWindowsAndTabs() throws {
        let workflowURL = try makeSpaceFixtureWorkflowFile(
            """
            {
              "workflowName": "multi-app-space-topology",
              "settleTimeoutMs": 8000,
              "apps": [
                {
                  "appID": "chrome",
                  "appName": "Chrome Fixture",
                  "bundleId": "com.example.fixture.chrome",
                  "launchOrder": 3,
                  "windows": [
                    {
                      "title": "Chrome Window 1",
                      "mode": "standard",
                      "tabs": [
                        { "title": "Docs", "isSelected": true },
                        { "title": "PR", "isSelected": false }
                      ]
                    },
                    {
                      "title": "Chrome Window 2",
                      "mode": "fullscreen",
                      "noisyCGSiblings": true,
                      "tabs": [
                        { "title": "Mail", "isSelected": false },
                        { "title": "Calendar", "isSelected": true }
                      ]
                    }
                  ]
                }
              ]
            }
            """
        )

        let configuration = try SpaceFixtureLaunchConfiguration.load(
            arguments: [
                "FlowTabSpaceFixture",
                "--workflow-config", workflowURL.path,
                "--workflow-app-id", "chrome",
                "--staggered-layout",
                "--enter-fullscreen-delay-ms", "900",
                "--terminate-delay-ms", "1100",
                "--preserve-desktop-after-fullscreen",
                "--suppress-app-accessibility-children"
            ]
        )

        XCTAssertEqual(configuration.workflowName, "multi-app-space-topology")
        XCTAssertEqual(configuration.workflowAppID, "chrome")
        XCTAssertEqual(configuration.workflowAppName, "Chrome Fixture")
        XCTAssertEqual(configuration.windowCount, 2)
        XCTAssertEqual(configuration.windowTitles, ["Docs", "Calendar"])
        XCTAssertEqual(configuration.fullscreenWindowIndex, 2)
        XCTAssertTrue(configuration.usesStaggeredLayout)
        XCTAssertEqual(configuration.enterFullscreenDelayMilliseconds, 900)
        XCTAssertEqual(configuration.terminationDelayMilliseconds, 1100)
        XCTAssertTrue(configuration.preservesDesktopAfterFullscreen)
        XCTAssertFalse(configuration.publishesApplicationAccessibilityChildren)
        XCTAssertEqual(configuration.windows[0].configuredTitle, "Chrome Window 1")
        XCTAssertFalse(configuration.windows[0].noisyCGSiblings)
        XCTAssertTrue(configuration.windows[1].noisyCGSiblings)
        XCTAssertEqual(configuration.windows[0].tabs.map(\.title), ["Docs", "PR"])
        XCTAssertEqual(configuration.windows[0].tabs.map(\.isSelected), [true, false])
        XCTAssertEqual(configuration.windows[1].tabs.map(\.isSelected), [false, true])
    }

    func testSpaceFixtureLaunchConfigurationSelectsFirstWorkflowTabWhenNoneMarkedSelected() throws {
        let workflowURL = try makeSpaceFixtureWorkflowFile(
            """
            {
              "workflowName": "tab-normalization",
              "apps": [
                {
                  "appID": "browser",
                  "appName": "Browser Fixture",
                  "bundleId": "com.example.fixture.browser",
                  "launchOrder": 1,
                  "windows": [
                    {
                      "title": "Browser Window",
                      "mode": "standard",
                      "tabs": [
                        { "title": "Inbox", "isSelected": false },
                        { "title": "Calendar", "isSelected": false }
                      ]
                    }
                  ]
                }
              ]
            }
            """
        )

        let configuration = try SpaceFixtureLaunchConfiguration.load(
            arguments: [
                "FlowTabSpaceFixture",
                "--workflow-config", workflowURL.path,
                "--workflow-app-id", "browser"
            ]
        )

        XCTAssertEqual(configuration.windowTitles, ["Inbox"])
        XCTAssertEqual(configuration.windows[0].tabs.map(\.isSelected), [true, false])
    }

    func testSpaceFixtureLaunchConfigurationRequiresWorkflowAppIDWhenWorkflowConfigProvided() throws {
        let workflowURL = try makeSpaceFixtureWorkflowFile(
            """
            {
              "workflowName": "missing-app-id",
              "apps": []
            }
            """
        )

        XCTAssertThrowsError(
            try SpaceFixtureLaunchConfiguration.load(
                arguments: [
                    "FlowTabSpaceFixture",
                    "--workflow-config", workflowURL.path
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? SpaceFixtureLaunchConfigurationError,
                .missingWorkflowAppID
            )
        }
    }

    func testSpaceFixtureWindowPlannerUsesTabbedWorkflowWindowTitles() {
        let configuration = SpaceFixtureLaunchConfiguration(
            windows: [
                SpaceFixtureConfiguredWindow(
                    configuredTitle: "Chrome Window 1",
                    windowTitle: "Docs",
                    mode: .standard,
                    tabs: [
                        SpaceFixtureConfiguredTab(title: "Docs", identifier: "tab-1", isSelected: true),
                        SpaceFixtureConfiguredTab(title: "PR", identifier: "tab-2", isSelected: false)
                    ]
                ),
                SpaceFixtureConfiguredWindow(
                    configuredTitle: "Chrome Window 2",
                    windowTitle: "Calendar",
                    mode: .fullscreen,
                    tabs: [
                        SpaceFixtureConfiguredTab(title: "Mail", identifier: "tab-1", isSelected: false),
                        SpaceFixtureConfiguredTab(title: "Calendar", identifier: "tab-2", isSelected: true)
                    ],
                    noisyCGSiblings: true
                )
            ],
            windowTitlePrefix: SpaceFixtureLaunchConfiguration.defaultWindowTitlePrefix,
            usesStaggeredLayout: false,
            enterFullscreenDelayMilliseconds: 400,
            preservesDesktopAfterFullscreen: false,
            workflowAppName: "Chrome Fixture"
        )

        let plans = SpaceFixtureWindowPlanner.makePlans(
            configuration: configuration,
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(plans.map(\.title), ["Docs", "Calendar"])
        XCTAssertEqual(plans.map(\.fixtureAppName), ["Chrome Fixture", "Chrome Fixture"])
        XCTAssertEqual(plans.map(\.noisyCGSiblings), [false, true])
        XCTAssertEqual(plans[0].subtitleText, "Chrome Window 1")
        XCTAssertEqual(plans[0].tabs.map(\.title), ["Docs", "PR"])
        XCTAssertEqual(plans[1].modeText, "Fullscreen Target")
    }

    private func makeSpaceFixtureWorkflowFile(_ contents: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("workflow.json")
        try Data(contents.utf8).write(to: fileURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return fileURL
    }
}
