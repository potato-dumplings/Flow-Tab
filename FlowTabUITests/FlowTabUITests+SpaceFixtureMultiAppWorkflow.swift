import Foundation
import XCTest

private enum SpaceFixtureMultiAppWorkflowDefaults {
    static let enterFullscreenDelayMilliseconds = 5_000
    static let expectedWindowCounts = [1, 3, 1]

    static var workflowSourceURL: URL {
        repositoryRootURL
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("fixtures", isDirectory: true)
            .appendingPathComponent("space-fixture-home-multi-app-workflow.json")
    }

    static var defaultResolvedWorkflowURL: URL {
        repositoryRootURL
            .appendingPathComponent(".build-local", isDirectory: true)
            .appendingPathComponent("space-fixture-workflow", isDirectory: true)
            .appendingPathComponent("variants", isDirectory: true)
            .appendingPathComponent("resolved-workflow.json")
    }

    private static var repositoryRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private enum SpaceFixtureMultiAppWorkflowError: LocalizedError, Equatable {
    case missingWorkflowPath(String)
    case workflowFileNotFound(String)
    case workflowFileUnreadable(String)
    case workflowFileInvalid(String)
    case workflowHasNoApps(String)
    case workflowAppMissingBundleIdentifier(String)
    case workflowAppMissingPath(String)
    case workflowAppPathNotFound(String, String)

    var errorDescription: String? {
        switch self {
        case let .missingWorkflowPath(path):
            return "Missing resolved workflow JSON at \(path)"
        case let .workflowFileNotFound(path):
            return "Workflow configuration file was not found: \(path)"
        case let .workflowFileUnreadable(path):
            return "Workflow configuration file could not be read: \(path)"
        case let .workflowFileInvalid(path):
            return "Workflow configuration file is invalid JSON: \(path)"
        case let .workflowHasNoApps(path):
            return "Workflow configuration does not define any apps: \(path)"
        case let .workflowAppMissingBundleIdentifier(appID):
            return "Workflow app \(appID) does not define a bundle identifier."
        case let .workflowAppMissingPath(appID):
            return "Workflow app \(appID) does not define an appPath."
        case let .workflowAppPathNotFound(appID, path):
            return "Workflow app \(appID) references a missing app bundle: \(path)"
        }
    }
}

private struct SpaceFixtureResolvedWorkflow: Equatable {
    struct App: Equatable {
        let appID: String
        let appName: String
        let identity: SpaceFixtureAppIdentity
        let launchOrder: Int
        let windowCount: Int
        let expectedWindowTitles: [String]
        let fullscreenWindowIndex: Int?
    }

    let workflowName: String
    let workflowURL: URL
    let settleTimeout: TimeInterval
    let apps: [App]

    static func configured(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> SpaceFixtureResolvedWorkflow {
        let configuredPath = environment["FLOWTAB_SPACE_FIXTURE_WORKFLOW_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let workflowURL: URL
        if let configuredPath, !configuredPath.isEmpty {
            workflowURL = URL(fileURLWithPath: configuredPath).standardizedFileURL
        } else {
            workflowURL = SpaceFixtureMultiAppWorkflowDefaults.defaultResolvedWorkflowURL
            guard FileManager.default.fileExists(atPath: workflowURL.path) else {
                throw SpaceFixtureMultiAppWorkflowError.missingWorkflowPath(workflowURL.path)
            }
        }

        return try load(from: workflowURL)
    }

    static func load(from workflowURL: URL) throws -> SpaceFixtureResolvedWorkflow {
        let normalizedURL = workflowURL.standardizedFileURL

        do {
            let data = try Data(contentsOf: normalizedURL)
            let document = try JSONDecoder().decode(SpaceFixtureResolvedWorkflowDocument.self, from: data)
            guard !document.apps.isEmpty else {
                throw SpaceFixtureMultiAppWorkflowError.workflowHasNoApps(normalizedURL.path)
            }

            let resolvedApps = try document.apps.map { app in
                let bundleIdentifier = app.bundleIdentifier
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !bundleIdentifier.isEmpty else {
                    throw SpaceFixtureMultiAppWorkflowError.workflowAppMissingBundleIdentifier(app.appID)
                }

                let appPath = (app.appPath ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !appPath.isEmpty else {
                    throw SpaceFixtureMultiAppWorkflowError.workflowAppMissingPath(app.appID)
                }

                let appURL = URL(fileURLWithPath: appPath).standardizedFileURL
                guard FileManager.default.fileExists(atPath: appURL.path) else {
                    throw SpaceFixtureMultiAppWorkflowError.workflowAppPathNotFound(app.appID, appURL.path)
                }

                return App(
                    appID: app.appID,
                    appName: app.appName.isEmpty ? bundleIdentifier : app.appName,
                    identity: SpaceFixtureAppIdentity(
                        bundleIdentifier: bundleIdentifier,
                        appURL: appURL
                    ),
                    launchOrder: app.launchOrder,
                    windowCount: app.windows.count,
                    expectedWindowTitles: app.windows.map(\.resolvedTitle),
                    fullscreenWindowIndex: app.windows.firstIndex(where: { $0.mode == .fullscreen }).map { $0 + 1 }
                )
            }
            .sorted {
                if $0.launchOrder != $1.launchOrder {
                    return $0.launchOrder < $1.launchOrder
                }
                if $0.appName != $1.appName {
                    return $0.appName < $1.appName
                }
                return $0.identity.bundleIdentifier < $1.identity.bundleIdentifier
            }

            let configuredSettleTimeout = TimeInterval(document.settleTimeoutMilliseconds ?? 0) / 1_000
            let fullscreenSettleTimeout = resolvedApps.contains(where: { $0.fullscreenWindowIndex != nil })
                ? Double(SpaceFixtureMultiAppWorkflowDefaults.enterFullscreenDelayMilliseconds) / 1_000 + 3.5
                : 0

            return SpaceFixtureResolvedWorkflow(
                workflowName: document.workflowName,
                workflowURL: normalizedURL,
                settleTimeout: max(configuredSettleTimeout, fullscreenSettleTimeout, 1),
                apps: resolvedApps
            )
        } catch let error as SpaceFixtureMultiAppWorkflowError {
            throw error
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw SpaceFixtureMultiAppWorkflowError.workflowFileNotFound(normalizedURL.path)
        } catch is CocoaError {
            throw SpaceFixtureMultiAppWorkflowError.workflowFileUnreadable(normalizedURL.path)
        } catch is DecodingError {
            throw SpaceFixtureMultiAppWorkflowError.workflowFileInvalid(normalizedURL.path)
        } catch {
            throw SpaceFixtureMultiAppWorkflowError.workflowFileUnreadable(normalizedURL.path)
        }
    }
}

private struct SpaceFixtureResolvedWorkflowDocument: Decodable {
    let workflowName: String
    let settleTimeoutMilliseconds: Int?
    let apps: [SpaceFixtureResolvedWorkflowAppDocument]

    enum CodingKeys: String, CodingKey {
        case workflowName
        case settleTimeoutMilliseconds = "settleTimeoutMs"
        case apps
    }
}

private struct SpaceFixtureResolvedWorkflowAppDocument: Decodable {
    let appID: String
    let appName: String
    let bundleIdentifier: String
    let appPath: String?
    let launchOrder: Int
    let windows: [SpaceFixtureResolvedWorkflowWindowDocument]

    enum CodingKeys: String, CodingKey {
        case appID
        case appName
        case bundleIdentifier = "bundleId"
        case appPath
        case launchOrder
        case windows
    }
}

private enum SpaceFixtureResolvedWorkflowWindowMode: String, Decodable {
    case standard
    case fullscreen
}

private struct SpaceFixtureResolvedWorkflowWindowDocument: Decodable {
    let title: String
    let mode: SpaceFixtureResolvedWorkflowWindowMode
    let tabs: [SpaceFixtureResolvedWorkflowTabDocument]

    var resolvedTitle: String {
        if let selectedTitle = tabs.first(where: \.isSelected)?.trimmedTitle, !selectedTitle.isEmpty {
            return selectedTitle
        }
        if let firstTabTitle = tabs.lazy.map(\.trimmedTitle).first(where: { !$0.isEmpty }) {
            return firstTabTitle
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SpaceFixtureResolvedWorkflowTabDocument: Decodable {
    let title: String
    let isSelected: Bool

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension FlowTabUITests {
    func testSpaceFixtureResolvedWorkflowUsesEnvironmentOverrideAndResolvesWindowMetadata() throws {
        let tempRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRootURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempRootURL)
        }

        let finderAppURL = try makeTemporarySpaceFixtureAppBundle(
            named: "Finder Fixture.app",
            in: tempRootURL
        )
        let chromeAppURL = try makeTemporarySpaceFixtureAppBundle(
            named: "Chrome Fixture.app",
            in: tempRootURL
        )

        let workflowURL = try makeSpaceFixtureWorkflowFile(
            """
            {
              "workflowName": "multi-app-home-window-counts",
              "settleTimeoutMs": 8000,
              "apps": [
                {
                  "appID": "chrome",
                  "appName": "Chrome Fixture",
                  "bundleId": "com.example.fixture.chrome",
                  "appPath": "\(chromeAppURL.path)",
                  "launchOrder": 2,
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
                      "tabs": [
                        { "title": "Review", "isSelected": true }
                      ]
                    }
                  ]
                },
                {
                  "appID": "finder",
                  "appName": "Finder Fixture",
                  "bundleId": "com.example.fixture.finder",
                  "appPath": "\(finderAppURL.path)",
                  "launchOrder": 1,
                  "windows": [
                    {
                      "title": "Finder Main",
                      "mode": "standard",
                      "tabs": []
                    }
                  ]
                }
              ]
            }
            """
        )

        let workflow = try SpaceFixtureResolvedWorkflow.configured(
            environment: ["FLOWTAB_SPACE_FIXTURE_WORKFLOW_PATH": workflowURL.path]
        )

        XCTAssertEqual(workflow.workflowName, "multi-app-home-window-counts")
        XCTAssertEqual(workflow.workflowURL, workflowURL.standardizedFileURL)
        XCTAssertEqual(workflow.apps.map(\.appID), ["finder", "chrome"])
        XCTAssertEqual(workflow.apps.map(\.windowCount), [1, 2])
        XCTAssertEqual(workflow.apps[0].expectedWindowTitles, ["Finder Main"])
        XCTAssertEqual(workflow.apps[1].expectedWindowTitles, ["Docs", "Review"])
        XCTAssertEqual(workflow.apps[1].fullscreenWindowIndex, 2)
        XCTAssertEqual(workflow.settleTimeout, 8.5)
    }

    func testHomePageShowsMultipleRealSpaceFixtureWorkflowAppsAndWindowCounts() throws {
        try runRealSpaceFixtureMultiAppWorkflow { workflow, app in
            XCTAssertTrue(
                tapFirstHittable(in: app.buttons.matching(identifier: Identifier.homeTabButton), timeout: 10)
            )

            for workflowApp in workflow.apps {
                let homeRow = app.buttons
                    .matching(identifier: workflowApp.identity.homeAppAccessibilityIdentifier)
                    .firstMatch
                XCTAssertTrue(
                    homeRow.waitForExistence(timeout: 20),
                    "FlowTab did not surface \(workflowApp.appName) on the home page"
                )
                assertValue(of: homeRow, equals: "\(workflowApp.windowCount)w", timeout: 20)
            }
        }
    }

    func terminateConfiguredSpaceFixtureWorkflowAppsIfRunning() {
        guard let workflow = try? SpaceFixtureResolvedWorkflow.configured() else { return }
        terminateSpaceFixtureWorkflowAppsIfRunning(workflow.apps.map(\.identity))
    }

    private func runRealSpaceFixtureMultiAppWorkflow(
        flowTabAdditionalArguments: [String] = [],
        perform assertions: (SpaceFixtureResolvedWorkflow, XCUIApplication) -> Void
    ) throws {
        let workflow: SpaceFixtureResolvedWorkflow
        do {
            workflow = try SpaceFixtureResolvedWorkflow.configured()
        } catch let error as SpaceFixtureMultiAppWorkflowError {
            if case .missingWorkflowPath = error {
                throw XCTSkip(multiAppWorkflowSetupMessage(reason: error.localizedDescription))
            }
            XCTFail(error.localizedDescription)
            return
        } catch {
            XCTFail(error.localizedDescription)
            return
        }

        try validateMultiAppHomeWindowCountWorkflow(workflow)
        terminateSpaceFixtureWorkflowAppsIfRunning(workflow.apps.map(\.identity))
        let fixtureApps = launchResolvedSpaceFixtureWorkflow(workflow)
        defer {
            terminateSpaceFixtureWorkflowApps(fixtureApps)
        }

        guard assertSpaceFixtureWorkflowPermissionsAvailable() else { return }

        let app = makeRealRuntimeFlowTabApp(additionalArguments: flowTabAdditionalArguments)
        launchFlowTabUITestApplication(app)
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }

        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 12))
        assertions(workflow, app)
    }

    private func validateMultiAppHomeWindowCountWorkflow(
        _ workflow: SpaceFixtureResolvedWorkflow
    ) throws {
        guard workflow.apps.map(\.windowCount) == SpaceFixtureMultiAppWorkflowDefaults.expectedWindowCounts else {
            throw XCTSkip(multiAppWorkflowSetupMessage(reason: "Resolved workflow does not match the Home window-count fixture scenario."))
        }

        guard workflow.apps.contains(where: { $0.windowCount == 3 && $0.fullscreenWindowIndex != nil }) else {
            throw XCTSkip(multiAppWorkflowSetupMessage(reason: "Resolved workflow is missing the fullscreen Chrome-style app fixture."))
        }
    }

    private func multiAppWorkflowSetupMessage(reason: String) -> String {
        """
        \(reason)

        Build the multi-app fixture workflow with:
          ./scripts/testing/build-space-fixture-workflow.sh --workflow-config \(SpaceFixtureMultiAppWorkflowDefaults.workflowSourceURL.path)

        Then rerun the test with:
          \(SpaceFixtureMultiAppWorkflowDefaults.defaultResolvedWorkflowURL.path)

        Or set FLOWTAB_SPACE_FIXTURE_WORKFLOW_PATH to the resolved workflow JSON you generated.
        """
    }

    private func makeTemporarySpaceFixtureAppBundle(
        named name: String,
        in directoryURL: URL
    ) throws -> URL {
        let appURL = directoryURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        return appURL
    }

    private func makeSpaceFixtureWorkflowApplication(for identity: SpaceFixtureAppIdentity) -> XCUIApplication {
        if let appURL = identity.appURL {
            return XCUIApplication(url: appURL)
        }
        return XCUIApplication(bundleIdentifier: identity.bundleIdentifier)
    }

    private func launchResolvedSpaceFixtureWorkflow(
        _ workflow: SpaceFixtureResolvedWorkflow
    ) -> [XCUIApplication] {
        var launchedApps: [XCUIApplication] = []

        for workflowApp in workflow.apps {
            let app = makeSpaceFixtureWorkflowApplication(for: workflowApp.identity)
            app.launchArguments += [
                "--workflow-config", workflow.workflowURL.path,
                "--workflow-app-id", workflowApp.appID,
                "--staggered-layout",
                "--enter-fullscreen-delay-ms", String(SpaceFixtureMultiAppWorkflowDefaults.enterFullscreenDelayMilliseconds),
                "--preserve-desktop-after-fullscreen"
            ]
            app.launch()

            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            waitForSpaceFixtureWorkflowToStabilize(
                in: app,
                expectedWindowTitles: workflowApp.expectedWindowTitles,
                fullscreenWindowIndex: workflowApp.fullscreenWindowIndex,
                settleTimeout: 0
            )
            launchedApps.append(app)
        }

        RunLoop.current.run(until: Date().addingTimeInterval(workflow.settleTimeout))
        return launchedApps
    }

    private func terminateSpaceFixtureWorkflowAppsIfRunning(_ identities: [SpaceFixtureAppIdentity]) {
        for identity in identities.reversed() {
            let app = makeSpaceFixtureWorkflowApplication(for: identity)
            if app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }
    }

    private func terminateSpaceFixtureWorkflowApps(_ apps: [XCUIApplication]) {
        for app in apps.reversed() where app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
    }
}
