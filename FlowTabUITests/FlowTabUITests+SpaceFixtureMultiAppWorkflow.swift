import Foundation
import XCTest

enum SpaceFixtureMultiAppWorkflowDefaults {
    static let enterFullscreenDelayMilliseconds = 5_000
    static let expectedWindowCounts = [1, 3, 1]

    static var workflowSourceURL: URL {
        repositoryRootURL
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("fixtures", isDirectory: true)
            .appendingPathComponent("space-fixture-home-multi-app-workflow.json")
    }

    static var fullscreenOnlyWorkflowSourceURL: URL {
        repositoryRootURL
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("fixtures", isDirectory: true)
            .appendingPathComponent("space-fixture-home-fullscreen-only-workflow.json")
    }

    static var homeWindowRecencyWorkflowSourceURL: URL {
        repositoryRootURL
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("fixtures", isDirectory: true)
            .appendingPathComponent("space-fixture-home-window-recency-workflow.json")
    }

    static var switcherWorkflowSourceURL: URL {
        repositoryRootURL
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("fixtures", isDirectory: true)
            .appendingPathComponent("space-fixture-switcher-multi-app-workflow.json")
    }

    static var controlTabRuntimeTruthWorkflowSourceURL: URL {
        switcherRuntimeTruthWorkflowSourceURL(named: "space-fixture-control-tab-fullscreen-sibling-workflow.json")
    }

    static var controlTabNoisyRuntimeTruthWorkflowSourceURL: URL {
        switcherRuntimeTruthWorkflowSourceURL(named: "space-fixture-control-tab-noisy-cg-siblings-workflow.json")
    }

    static var optionTabWindowStateRuntimeTruthWorkflowSourceURL: URL {
        switcherRuntimeTruthWorkflowSourceURL(named: "space-fixture-option-tab-window-state-fullscreen-sibling-workflow.json")
    }

    static var optionTabWindowStateNoisyRuntimeTruthWorkflowSourceURL: URL {
        switcherRuntimeTruthWorkflowSourceURL(named: "space-fixture-option-tab-window-state-noisy-cg-siblings-workflow.json")
    }

    static var optionTabSpaceBackedRuntimeTruthWorkflowSourceURL: URL {
        switcherRuntimeTruthWorkflowSourceURL(named: "space-fixture-option-tab-space-backed-workflow.json")
    }

    static var optionTabProvisionalHiddenRuntimeTruthWorkflowSourceURL: URL {
        switcherRuntimeTruthWorkflowSourceURL(named: "space-fixture-option-tab-provisional-hidden-workflow.json")
    }

    static var windowSearchRuntimeTruthWorkflowSourceURL: URL {
        switcherRuntimeTruthWorkflowSourceURL(named: "space-fixture-window-search-fullscreen-sibling-workflow.json")
    }

    static var windowSearchNoisyRuntimeTruthWorkflowSourceURL: URL {
        switcherRuntimeTruthWorkflowSourceURL(named: "space-fixture-window-search-noisy-cg-siblings-workflow.json")
    }

    static var defaultResolvedWorkflowURL: URL {
        repositoryRootURL
            .appendingPathComponent(".build-local", isDirectory: true)
            .appendingPathComponent("space-fixture-workflow", isDirectory: true)
            .appendingPathComponent("variants", isDirectory: true)
            .appendingPathComponent("resolved-workflow.json")
    }

    static var defaultSystemAppMRUResolvedWorkflowURL: URL {
        repositoryRootURL
            .appendingPathComponent(".build-local", isDirectory: true)
            .appendingPathComponent("space-fixture-workflow", isDirectory: true)
            .appendingPathComponent("system-app-mru-variants", isDirectory: true)
            .appendingPathComponent("resolved-workflow.json")
    }

    private static var repositoryRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func switcherRuntimeTruthWorkflowSourceURL(named filename: String) -> URL {
        repositoryRootURL
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("fixtures", isDirectory: true)
            .appendingPathComponent(filename)
    }
}

enum SpaceFixtureMultiAppWorkflowError: LocalizedError, Equatable {
    case missingWorkflowPath(String)
    case workflowFileNotFound(String)
    case workflowFileUnreadable(String)
    case workflowFileInvalid(String)
    case workflowHasNoApps(String)
    case workflowAppMissingBundleIdentifier(String)
    case workflowAppMissingPath(String)
    case workflowAppPathNotFound(String, String)
    case workflowScenarioMissingAppVariant(String, String)
    case workflowScenarioBundleIdentifierMismatch(String, String, String)

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
        case let .workflowScenarioMissingAppVariant(appID, workflowName):
            return "Workflow scenario \(workflowName) could not find a built fixture app for \(appID)."
        case let .workflowScenarioBundleIdentifierMismatch(appID, expectedBundleIdentifier, actualBundleIdentifier):
            return """
            Workflow scenario \(appID) expects bundle identifier \(expectedBundleIdentifier), \
            but the installed fixture app uses \(actualBundleIdentifier).
            """
        }
    }
}

struct SpaceFixtureResolvedWorkflow: Equatable {
    let workflowName: String
    let workflowURL: URL
    let readinessWatchdog: TimeInterval
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

                let fullscreenWindowIndices =
                    app.windows.enumerated().compactMap {
                        index, window in
                        window.mode == .fullscreen
                            ? index + 1
                            : nil
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
                    expectedHomeWindowTitles: app.windows.compactMap(\.homeResolvedTitle),
                    fullscreenWindowIndex:
                        fullscreenWindowIndices.first,
                    fullscreenWindowIndices:
                        fullscreenWindowIndices,
                    fullscreenWindowTitles: app.windows
                        .filter { $0.mode == .fullscreen }
                        .map(\.resolvedTitle)
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

            let configuredReadinessWatchdog =
                TimeInterval(
                    document.settleTimeoutMilliseconds ?? 0
                ) / 1_000
            let fullscreenDelayMilliseconds =
                resolvedApps.contains(where: {
                    $0.fullscreenWindowIndex != nil
                })
                ? SpaceFixtureMultiAppWorkflowDefaults
                    .enterFullscreenDelayMilliseconds
                : 0

            return SpaceFixtureResolvedWorkflow(
                workflowName: document.workflowName,
                workflowURL: normalizedURL,
                readinessWatchdog: max(
                    configuredReadinessWatchdog,
                    SpaceFixtureWorkflowReadinessUITestPolicy
                        .watchdog(
                            enterFullscreenDelayMilliseconds:
                                fullscreenDelayMilliseconds
                        )
                ),
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

struct SpaceFixtureResolvedWorkflowDocument: Codable {
    let workflowName: String
    let settleTimeoutMilliseconds: Int?
    let apps: [SpaceFixtureResolvedWorkflowAppDocument]

    enum CodingKeys: String, CodingKey {
        case workflowName
        case settleTimeoutMilliseconds = "settleTimeoutMs"
        case apps
    }
}

struct SpaceFixtureResolvedWorkflowAppDocument: Codable {
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

enum SpaceFixtureResolvedWorkflowWindowMode: String, Codable {
    case standard
    case fullscreen
}

struct SpaceFixtureResolvedWorkflowWindowDocument: Codable {
    let title: String
    let mode: SpaceFixtureResolvedWorkflowWindowMode
    let tabs: [SpaceFixtureResolvedWorkflowTabDocument]
    let noisyCGSiblings: Bool?
    let publishesApplicationAXWindow: Bool?
    let suppressesWindowAccessibilityExposure: Bool?
    let startupState: String?

    var resolvedTitle: String {
        if let selectedTitle = tabs.first(where: \.isSelected)?.trimmedTitle, !selectedTitle.isEmpty {
            return selectedTitle
        }
        if let firstTabTitle = tabs.lazy.map(\.trimmedTitle).first(where: { !$0.isEmpty }) {
            return firstTabTitle
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var homeResolvedTitle: String? {
        if mode == .fullscreen {
            return nil
        }
        return resolvedTitle
    }
}

struct SpaceFixtureResolvedWorkflowTabDocument: Codable {
    let title: String
    let isSelected: Bool

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension SpaceFixtureResolvedWorkflow {
    var allExpectedWindowTitles: [String] {
        apps.flatMap(\.expectedWindowTitles)
    }

    var allExpectedHomeWindowTitles: [String] {
        apps.flatMap(\.expectedHomeWindowTitles)
    }

    var hasUniqueExpectedWindowTitles: Bool {
        Set(allExpectedWindowTitles).count == allExpectedWindowTitles.count
    }

    var hasUniqueExpectedHomeWindowTitles: Bool {
        Set(allExpectedHomeWindowTitles).count == allExpectedHomeWindowTitles.count
    }

    func otherExpectedWindowTitles(excluding appID: String) -> [String] {
        apps
            .filter { $0.appID != appID }
            .flatMap(\.expectedWindowTitles)
    }

    func otherExpectedHomeWindowTitles(excluding appID: String) -> [String] {
        apps
            .filter { $0.appID != appID }
            .flatMap(\.expectedHomeWindowTitles)
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
        XCTAssertEqual(workflow.apps[1].expectedHomeWindowTitles, ["Docs"])
        XCTAssertEqual(workflow.apps[1].fullscreenWindowIndex, 2)
        XCTAssertEqual(workflow.readinessWatchdog, 20)
    }

    func testSpaceFixtureResolvedWorkflowResolvesScenarioUsingInstalledWorkflowAppVariants() throws {
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

        let installedWorkflow = SpaceFixtureResolvedWorkflow(
            workflowName: "installed-variants",
            workflowURL: tempRootURL.appendingPathComponent("resolved-workflow.json"),
            readinessWatchdog: 20,
            apps: [
                .init(
                    appID: "finder",
                    appName: "Finder Fixture",
                    identity: SpaceFixtureAppIdentity(
                        bundleIdentifier: "com.example.fixture.finder",
                        appURL: finderAppURL
                    ),
                    launchOrder: 1,
                    windowCount: 1,
                    expectedWindowTitles: ["Finder Main"],
                    fullscreenWindowIndex: nil
                ),
                .init(
                    appID: "chrome",
                    appName: "Chrome Fixture",
                    identity: SpaceFixtureAppIdentity(
                        bundleIdentifier: "com.example.fixture.chrome",
                        appURL: chromeAppURL
                    ),
                    launchOrder: 2,
                    windowCount: 1,
                    expectedWindowTitles: ["Review"],
                    fullscreenWindowIndex: 1
                )
            ]
        )

        let sourceWorkflowURL = try makeSpaceFixtureWorkflowFile(
            """
            {
              "workflowName": "multi-app-home-fullscreen-only",
              "settleTimeoutMs": 8000,
              "apps": [
                {
                  "appID": "finder",
                  "appName": "Finder Fixture",
                  "bundleId": "com.example.fixture.finder",
                  "launchOrder": 1,
                  "windows": [
                    {
                      "title": "Finder Main",
                      "mode": "standard",
                      "tabs": []
                    }
                  ]
                },
                {
                  "appID": "chrome",
                  "appName": "Chrome Fixture",
                  "bundleId": "com.example.fixture.chrome",
                  "launchOrder": 2,
                  "windows": [
                    {
                      "title": "Chrome Fullscreen",
                      "mode": "fullscreen",
                      "tabs": [
                        { "title": "Review", "isSelected": true }
                      ]
                    }
                  ]
                }
              ]
            }
            """
        )

        let workflow = try resolveSpaceFixtureWorkflowScenario(
            sourceWorkflowURL: sourceWorkflowURL,
            using: installedWorkflow
        )

        XCTAssertEqual(workflow.workflowName, "multi-app-home-fullscreen-only")
        XCTAssertEqual(workflow.apps.map(\.appID), ["finder", "chrome"])
        XCTAssertEqual(workflow.apps[0].identity.appURL, finderAppURL.standardizedFileURL)
        XCTAssertEqual(workflow.apps[1].identity.appURL, chromeAppURL.standardizedFileURL)
        XCTAssertEqual(workflow.apps[1].expectedWindowTitles, ["Review"])
        XCTAssertEqual(workflow.apps[1].expectedHomeWindowTitles, [])
        XCTAssertEqual(workflow.apps[1].fullscreenWindowIndex, 1)
    }

    func testSpaceFixtureResolvedWorkflowComputesPerAppExcludedTitlesForHomeIsolation() {
        let workflow = SpaceFixtureResolvedWorkflow(
            workflowName: "multi-app-home-isolation",
            workflowURL: URL(fileURLWithPath: "/tmp/resolved-workflow.json"),
            readinessWatchdog: 20,
            apps: [
                .init(
                    appID: "finder",
                    appName: "Finder Fixture",
                    identity: SpaceFixtureAppIdentity(bundleIdentifier: "com.example.fixture.finder", appURL: nil),
                    launchOrder: 1,
                    windowCount: 1,
                    expectedWindowTitles: ["Finder Main"],
                    fullscreenWindowIndex: nil
                ),
                .init(
                    appID: "chrome",
                    appName: "Chrome Fixture",
                    identity: SpaceFixtureAppIdentity(bundleIdentifier: "com.example.fixture.chrome", appURL: nil),
                    launchOrder: 2,
                    windowCount: 3,
                    expectedWindowTitles: ["Docs", "Mail", "Review"],
                    fullscreenWindowIndex: 3
                ),
                .init(
                    appID: "notes",
                    appName: "Notes Fixture",
                    identity: SpaceFixtureAppIdentity(bundleIdentifier: "com.example.fixture.notes", appURL: nil),
                    launchOrder: 3,
                    windowCount: 1,
                    expectedWindowTitles: ["Notes Inbox"],
                    fullscreenWindowIndex: nil
                )
            ]
        )

        XCTAssertTrue(workflow.hasUniqueExpectedWindowTitles)
        XCTAssertEqual(
            Set(workflow.otherExpectedWindowTitles(excluding: "chrome")),
            Set(["Finder Main", "Notes Inbox"])
        )
        XCTAssertEqual(
            Set(workflow.otherExpectedWindowTitles(excluding: "finder")),
            Set(["Docs", "Mail", "Review", "Notes Inbox"])
        )
    }

    func testHomePageShowsFullscreenOnlyWorkflowAppAndResolvedWindowTitle() throws {
        let workflow: SpaceFixtureResolvedWorkflow
        do {
            workflow = try configuredFullscreenOnlySpaceFixtureWorkflow()
        } catch let error as SpaceFixtureMultiAppWorkflowError {
            switch error {
            case .missingWorkflowPath, .workflowScenarioMissingAppVariant, .workflowScenarioBundleIdentifierMismatch:
                throw XCTSkip(
                    multiAppWorkflowSetupMessage(
                        reason: error.localizedDescription,
                        scenarioSourceURL: SpaceFixtureMultiAppWorkflowDefaults.fullscreenOnlyWorkflowSourceURL
                    )
                )
            default:
                XCTFail(error.localizedDescription)
                return
            }
        } catch {
            XCTFail(error.localizedDescription)
            return
        }

        try validateMultiAppHomeFullscreenOnlyWorkflow(workflow)

        try runRealSpaceFixtureWorkflow(workflow) { workflow, app in
            try assertHomePageShowsOnlySelectedWorkflowAppTitles(
                workflow,
                in: app,
                setupMessage: { reason in
                    self.multiAppWorkflowSetupMessage(
                        reason: reason,
                        scenarioSourceURL: SpaceFixtureMultiAppWorkflowDefaults.fullscreenOnlyWorkflowSourceURL
                    )
                }
            )
        }
    }

    func testHomePageShowsMultipleRealSpaceFixtureWorkflowAppsAndWindowCounts() throws {
        try runRealSpaceFixtureMultiAppWorkflow { workflow, app in
            XCTAssertNotNil(
                waitForSpaceFixtureHomeAppRowsAfterNavigation(
                    workflow,
                    in: app
                )
            )
        }
    }

    func testHomePageSelectingWorkflowAppShowsOnlyThatAppsResolvedWindowTitles() throws {
        try runRealSpaceFixtureMultiAppWorkflow { workflow, app in
            try assertHomePageShowsOnlySelectedWorkflowAppTitles(
                workflow,
                in: app,
                setupMessage: { reason in
                    self.multiAppWorkflowSetupMessage(reason: reason)
                }
            )
        }
    }

    func terminateConfiguredSpaceFixtureWorkflowAppsIfRunning() {
        guard let workflow = try? SpaceFixtureResolvedWorkflow.configured() else { return }
        terminateSpaceFixtureWorkflowAppsIfRunning(workflow.apps.map(\.identity))
    }

    func runRealSpaceFixtureMultiAppWorkflow(
        flowTabAdditionalArguments: [String] = [],
        waitsForFullscreenMarkers: Bool = true,
        suppressesAppAccessibilityChildren: Bool = false,
        validatesPermissionsBeforeFixtureLaunch: Bool = false,
        preservesDesktopAfterFullscreen: Bool = true,
        prelaunchesFlowTabBeforeFixture: Bool = false,
        flowTabLaunchTraceLabel: String? = nil,
        workflowAppLaunchArguments: (SpaceFixtureResolvedWorkflow.App) -> [String] = { _ in [] },
        afterFlowTabLaunch: ((SpaceFixtureResolvedWorkflow, XCUIApplication) throws -> Void)? = nil,
        perform assertions: (SpaceFixtureResolvedWorkflow, XCUIApplication) throws -> Void
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
        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: flowTabAdditionalArguments,
            waitsForFullscreenMarkers: waitsForFullscreenMarkers,
            suppressesAppAccessibilityChildren: suppressesAppAccessibilityChildren,
            validatesPermissionsBeforeFixtureLaunch: validatesPermissionsBeforeFixtureLaunch,
            preservesDesktopAfterFullscreen: preservesDesktopAfterFullscreen,
            prelaunchesFlowTabBeforeFixture: prelaunchesFlowTabBeforeFixture,
            flowTabLaunchTraceLabel: flowTabLaunchTraceLabel,
            workflowAppLaunchArguments: workflowAppLaunchArguments,
            afterFlowTabLaunch: afterFlowTabLaunch,
            perform: assertions
        )
    }

    func runRealSpaceFixtureWorkflow(
        _ workflow: SpaceFixtureResolvedWorkflow,
        flowTabAdditionalArguments: [String] = [],
        waitsForFullscreenMarkers: Bool = true,
        suppressesAppAccessibilityChildren: Bool = false,
        validatesPermissionsBeforeFixtureLaunch: Bool = false,
        preservesDesktopAfterFullscreen: Bool = true,
        prelaunchesFlowTabBeforeFixture: Bool = false,
        beforeFlowTabLaunch: ((SpaceFixtureResolvedWorkflow) throws -> Void)? = nil,
        flowTabLaunchTraceLabel: String? = nil,
        workflowAppLaunchArguments: (SpaceFixtureResolvedWorkflow.App) -> [String] = { _ in [] },
        afterFlowTabLaunch: ((SpaceFixtureResolvedWorkflow, XCUIApplication) throws -> Void)? = nil,
        perform assertions: (SpaceFixtureResolvedWorkflow, XCUIApplication) throws -> Void
    ) throws {
        terminateSpaceFixtureWorkflowAppsIfRunning(workflow.apps.map(\.identity))
        guard
            !suppressesAppAccessibilityChildren
                || prelaunchesFlowTabBeforeFixture
        else {
            XCTFail(
                "Application AX suppression requires FlowTab to observe fixture projection before fixture launch."
            )
            return
        }

        let suppressionRoutes =
            suppressesAppAccessibilityChildren
            ? makeSpaceFixtureAXSuppressionRoutes(
                for: workflow
            )
            : []
        let suppressionObservationOwner =
            SpaceFixtureAXSuppressionObservationOwner(
                routes: suppressionRoutes
            )
        suppressionObservationOwner.start()
        defer {
            suppressionObservationOwner.cancel()
        }
        let routedFlowTabAdditionalArguments =
            flowTabAdditionalArguments
            + suppressionRoutes.flatMap(
                \.flowTabLaunchArguments
            )

        var flowTabAppForCleanup: XCUIApplication?
        defer {
            if let app = flowTabAppForCleanup,
               app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }

        let prelaunchedFlowTabApp: XCUIApplication?
        if prelaunchesFlowTabBeforeFixture {
            let app = makeRealRuntimeFlowTabApp(
                additionalArguments:
                    routedFlowTabAdditionalArguments
            )
            launchFlowTabUITestApplication(app, traceLabel: flowTabLaunchTraceLabel)
            assertRealSpaceFixtureFlowTabIsForegroundReady(
                app,
                traceLabel: flowTabLaunchTraceLabel,
                targetDescription: "prelaunch-before-fixture"
            )
            prelaunchedFlowTabApp = app
            flowTabAppForCleanup = app
        } else {
            prelaunchedFlowTabApp = nil
        }

        if validatesPermissionsBeforeFixtureLaunch {
            let permissionsAvailable = prelaunchedFlowTabApp.map {
                assertSpaceFixtureWorkflowPermissionsAvailable(in: $0)
            } ?? assertSpaceFixtureWorkflowPermissionsAvailable()
            guard permissionsAvailable else { return }
        }

        let fixtureApps = launchResolvedSpaceFixtureWorkflow(
            workflow,
            waitsForFullscreenMarkers: waitsForFullscreenMarkers,
            suppressesAppAccessibilityChildren: suppressesAppAccessibilityChildren,
            preservesDesktopAfterFullscreen: preservesDesktopAfterFullscreen,
            applicationAXSuppressionRoutes:
                suppressionRoutes,
            workflowAppLaunchArguments: workflowAppLaunchArguments
        )
        logFullscreenWorkflowSpaceObservations("workflow.afterFixtureLaunch", workflow: workflow)
        defer {
            terminateSpaceFixtureWorkflowApps(fixtureApps)
        }

        if suppressesAppAccessibilityChildren {
            logFullscreenWorkflowSpaceObservations("workflow.beforeAXSuppressionCheck", workflow: workflow)
            for route in suppressionRoutes {
                XCTAssertTrue(
                    suppressionObservationOwner
                        .waitForSuppression(
                            route: route
                        ),
                    "\(route.bundleIdentifier) did not publish exact application AX suppression evidence."
                )
            }
            logFullscreenWorkflowSpaceObservations("workflow.afterAXSuppressionCheck", workflow: workflow)
        }

        if !validatesPermissionsBeforeFixtureLaunch {
            logFullscreenWorkflowSpaceObservations("workflow.beforePermissionCheck", workflow: workflow)
            guard assertSpaceFixtureWorkflowPermissionsAvailable() else { return }
            logFullscreenWorkflowSpaceObservations("workflow.afterPermissionCheck", workflow: workflow)
        }

        logFullscreenWorkflowSpaceObservations("workflow.beforeBeforeFlowTabLaunch", workflow: workflow)
        try beforeFlowTabLaunch?(workflow)
        logFullscreenWorkflowSpaceObservations("workflow.afterBeforeFlowTabLaunch", workflow: workflow)

        let app: XCUIApplication
        if let prelaunchedFlowTabApp {
            app = prelaunchedFlowTabApp
        } else {
            app = makeRealRuntimeFlowTabApp(
                additionalArguments:
                    routedFlowTabAdditionalArguments
            )
            launchFlowTabUITestApplication(app, traceLabel: flowTabLaunchTraceLabel)
            flowTabAppForCleanup = app
            try afterFlowTabLaunch?(workflow, app)

            assertRealSpaceFixtureFlowTabIsForegroundReady(
                app,
                traceLabel: flowTabLaunchTraceLabel,
                targetDescription: "post-fixture-launch"
            )
        }
        try assertions(workflow, app)
    }

    func configuredFullscreenOnlySpaceFixtureWorkflow(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> SpaceFixtureResolvedWorkflow {
        let installedWorkflow = try SpaceFixtureResolvedWorkflow.configured(environment: environment)
        return try resolveSpaceFixtureWorkflowScenario(
            sourceWorkflowURL: SpaceFixtureMultiAppWorkflowDefaults.fullscreenOnlyWorkflowSourceURL,
            using: installedWorkflow
        )
    }

    func resolveSpaceFixtureWorkflowScenario(
        sourceWorkflowURL: URL,
        using installedWorkflow: SpaceFixtureResolvedWorkflow
    ) throws -> SpaceFixtureResolvedWorkflow {
        let sourceData = try Data(contentsOf: sourceWorkflowURL.standardizedFileURL)
        let sourceDocument = try JSONDecoder().decode(SpaceFixtureResolvedWorkflowDocument.self, from: sourceData)
        let installedAppsByID = Dictionary(
            uniqueKeysWithValues: installedWorkflow.apps.map { ($0.appID, $0) }
        )

        let resolvedApps = try sourceDocument.apps.map { app in
            guard let installedApp = installedAppsByID[app.appID] else {
                throw SpaceFixtureMultiAppWorkflowError.workflowScenarioMissingAppVariant(
                    app.appID,
                    sourceDocument.workflowName
                )
            }

            let expectedBundleIdentifier = app.bundleIdentifier
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let installedBundleIdentifier = installedApp.identity.bundleIdentifier
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard expectedBundleIdentifier == installedBundleIdentifier else {
                throw SpaceFixtureMultiAppWorkflowError.workflowScenarioBundleIdentifierMismatch(
                    app.appID,
                    expectedBundleIdentifier,
                    installedBundleIdentifier
                )
            }

            return SpaceFixtureResolvedWorkflowAppDocument(
                appID: app.appID,
                appName: app.appName,
                bundleIdentifier: app.bundleIdentifier,
                appPath: installedApp.identity.appURL?.path,
                launchOrder: app.launchOrder,
                windows: app.windows
            )
        }

        let resolvedDocument = SpaceFixtureResolvedWorkflowDocument(
            workflowName: sourceDocument.workflowName,
            settleTimeoutMilliseconds: sourceDocument.settleTimeoutMilliseconds,
            apps: resolvedApps
        )

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let resolvedWorkflowURL = directoryURL.appendingPathComponent("resolved-workflow.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(resolvedDocument).write(to: resolvedWorkflowURL)
        return try SpaceFixtureResolvedWorkflow.load(from: resolvedWorkflowURL)
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

    func validateMultiAppHomeFullscreenOnlyWorkflow(
        _ workflow: SpaceFixtureResolvedWorkflow
    ) throws {
        guard workflow.apps.count == 2 else {
            throw XCTSkip(
                multiAppWorkflowSetupMessage(
                    reason: "Resolved workflow does not match the fullscreen-only Home fixture scenario.",
                    scenarioSourceURL: SpaceFixtureMultiAppWorkflowDefaults.fullscreenOnlyWorkflowSourceURL
                )
            )
        }

        guard workflow.apps.contains(where: { $0.windowCount == 1 && $0.fullscreenWindowIndex == 1 }) else {
            throw XCTSkip(
                multiAppWorkflowSetupMessage(
                    reason: "Resolved workflow is missing the fullscreen-only app fixture.",
                    scenarioSourceURL: SpaceFixtureMultiAppWorkflowDefaults.fullscreenOnlyWorkflowSourceURL
                )
            )
        }

        guard workflow.apps.contains(where: { $0.windowCount == 1 && $0.fullscreenWindowIndex == nil }) else {
            throw XCTSkip(
                multiAppWorkflowSetupMessage(
                    reason: "Resolved workflow is missing the standard desktop app fixture.",
                    scenarioSourceURL: SpaceFixtureMultiAppWorkflowDefaults.fullscreenOnlyWorkflowSourceURL
                )
            )
        }
    }

    private func assertHomePageShowsOnlySelectedWorkflowAppTitles(
        _ workflow: SpaceFixtureResolvedWorkflow,
        in app: XCUIApplication,
        setupMessage: (String) -> String
    ) throws {
        guard workflow.hasUniqueExpectedHomeWindowTitles else {
            throw XCTSkip(
                setupMessage(
                    "Resolved workflow does not define unique window titles per app for Home isolation assertions."
                )
            )
        }

        guard waitForSpaceFixtureHomeAppInventoryAfterNavigation(
            workflow,
            in: app
        ) != nil else {
            return
        }

        for workflowApp in workflow.apps {
            guard selectSpaceFixtureHomeAppAndWaitForExactWindowProjection(
                workflowApp,
                in: workflow,
                app: app
            ) != nil else {
                return
            }
        }
    }

    func multiAppWorkflowSetupMessage(
        reason: String,
        scenarioSourceURL: URL = SpaceFixtureMultiAppWorkflowDefaults.workflowSourceURL
    ) -> String {
        """
        \(reason)

        Build or refresh the shared multi-app fixture app variants with:
          ./scripts/testing/build-space-fixture-workflow.sh --workflow-config \(scenarioSourceURL.path)

        Baseline resolved workflow path:
          \(SpaceFixtureMultiAppWorkflowDefaults.defaultResolvedWorkflowURL.path)

        Scenario source:
          \(scenarioSourceURL.path)

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

    func makeSpaceFixtureWorkflowApplication(for identity: SpaceFixtureAppIdentity) -> XCUIApplication {
        if let appURL = identity.appURL {
            return XCUIApplication(url: appURL)
        }
        return XCUIApplication(bundleIdentifier: identity.bundleIdentifier)
    }

    func logFullscreenWorkflowSpaceObservations(
        _ stage: String,
        workflow: SpaceFixtureResolvedWorkflow
    ) {
        for workflowApp in workflow.apps where workflowApp.fullscreenWindowIndex != nil {
            logWorkflowSpaceObservation("\(stage).\(workflowApp.appID)", app: workflowApp)
        }
    }

    private func terminateSpaceFixtureWorkflowAppsIfRunning(_ identities: [SpaceFixtureAppIdentity]) {
        for identity in identities.reversed() {
            let app = makeSpaceFixtureWorkflowApplication(for: identity)
            if app.state == .runningForeground || app.state == .runningBackground {
                terminateSpaceFixtureApplicationAndWait(app, identity: identity)
            }
        }
    }

    private func terminateSpaceFixtureWorkflowApps(_ apps: [XCUIApplication]) {
        for app in apps.reversed() where app.state == .runningForeground || app.state == .runningBackground {
            terminateSpaceFixtureApplicationAndWait(app)
        }
    }
}
