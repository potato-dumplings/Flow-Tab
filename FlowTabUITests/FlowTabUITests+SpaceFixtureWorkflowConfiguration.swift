import Foundation
import XCTest

extension FlowTabUITests {
    func testSpaceFixtureAppLoadsWorkflowConfiguredTabbedWindows() throws {
        let identity = spaceFixtureAppIdentity
        terminateSpaceFixtureAppIfRunning()

        let workflowURL = try makeSpaceFixtureWorkflowFile(
            """
            {
              "workflowName": "tabbed-window-rendering",
              "apps": [
                {
                  "appID": "chrome",
                  "appName": "Chrome Fixture",
                  "bundleId": "com.example.fixture.chrome",
                  "launchOrder": 1,
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
                      "mode": "standard",
                      "tabs": [
                        { "title": "Mail", "isSelected": true },
                        { "title": "Calendar", "isSelected": false }
                      ]
                    }
                  ]
                }
              ]
            }
            """
        )

        let app: XCUIApplication
        if let appURL = identity.appURL {
            app = XCUIApplication(url: appURL)
        } else {
            app = XCUIApplication(bundleIdentifier: identity.bundleIdentifier)
        }
        app.launchArguments += [
            "--workflow-config", workflowURL.path,
            "--workflow-app-id", "chrome",
            "--staggered-layout"
        ]
        app.launch()
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        waitForSpaceFixtureWorkflowToStabilize(
            in: app,
            expectedWindowTitles: ["Docs", "Mail"],
            fullscreenWindowIndex: nil,
            settleTimeout: 1
        )

        let firstWindowTitle = element(in: app, identifier: "flowtab.spacefixture.window.title.1")
        XCTAssertTrue(firstWindowTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(firstWindowTitle.label, "Docs")

        let firstWindowSubtitle = element(in: app, identifier: "flowtab.spacefixture.window.subtitle.1")
        XCTAssertTrue(firstWindowSubtitle.waitForExistence(timeout: 5))
        XCTAssertEqual(firstWindowSubtitle.label, "Chrome Window 1")

        let selectedTab = element(in: app, identifier: "flowtab.spacefixture.window.tab.1.1")
        XCTAssertTrue(selectedTab.waitForExistence(timeout: 5))
        XCTAssertEqual(selectedTab.label, "Docs")

        let selectedTabSummary = element(in: app, identifier: "flowtab.spacefixture.window.selected-tab.1")
        XCTAssertTrue(selectedTabSummary.waitForExistence(timeout: 5))
        XCTAssertEqual(selectedTabSummary.label, "Selected Tab: Docs")

        let backgroundTab = element(in: app, identifier: "flowtab.spacefixture.window.tab.1.2")
        XCTAssertTrue(backgroundTab.waitForExistence(timeout: 5))
        XCTAssertEqual(backgroundTab.label, "PR")
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
