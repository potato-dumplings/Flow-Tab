import CoreGraphics
import XCTest

extension FlowTabTests {
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
    }

    func testSpaceFixtureLaunchConfigurationNormalizesInvalidNumericArguments() {
        let configuration = SpaceFixtureLaunchConfiguration(
            arguments: [
                "FlowTabSpaceFixture",
                "--window-count", "0",
                "--fullscreen-window-index", "9",
                "--window-title-prefix", "  ",
                "--enter-fullscreen-delay-ms", "-25"
            ]
        )

        XCTAssertEqual(configuration.windowCount, SpaceFixtureLaunchConfiguration.minimumWindowCount)
        XCTAssertNil(configuration.fullscreenWindowIndex)
        XCTAssertEqual(configuration.windowTitlePrefix, SpaceFixtureLaunchConfiguration.defaultWindowTitlePrefix)
        XCTAssertEqual(configuration.enterFullscreenDelayMilliseconds, 0)
        XCTAssertFalse(configuration.preservesDesktopAfterFullscreen)
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
}
