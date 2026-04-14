import AppKit
import XCTest

extension FlowTabUITests {
    private var spaceFixtureBundleIdentifier: String {
        "io.github.potato-dumplings.flowtab.spacefixture"
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
        XCTAssertTrue(element(in: app, identifier: "flowtab.spacefixture.window.title.1").waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, identifier: "flowtab.spacefixture.window.title.2").waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, identifier: "flowtab.spacefixture.window.title.3").waitForExistence(timeout: 5))
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
        XCTAssertTrue(element(in: app, identifier: "flowtab.spacefixture.window.title.2").waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, identifier: "flowtab.spacefixture.window.mode.2").waitForExistence(timeout: 5))
        XCTAssertEqual(element(in: app, identifier: "flowtab.spacefixture.window.mode.2").label, "Fullscreen Target")
    }
}
