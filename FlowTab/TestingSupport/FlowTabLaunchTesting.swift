#if FLOWTAB_TESTING
import Foundation

enum FlowTabTestLaunchOptions {
    static let uiTestingEnvironmentKey = "FLOWTAB_UI_TESTING"
    static let uiTestingEnvironmentValue = "1"
    static let unitTestingBundlePathEnvironmentKey = "XCTestBundlePath"
    static let projectionAcknowledgementRouteArgument =
        "--flowtab-ui-projection-acknowledgement-route"
    static let currentAppProjectionEvidenceRouteArgument =
        "--flowtab-ui-current-app-projection-evidence-route"
    static let homeInitialProjectionApplicationRouteArgument =
        "--flowtab-ui-home-initial-projection-application-notification-name"
    static let homeInitialProjectionApplicationReadbackPathArgument =
        "--flowtab-ui-home-initial-projection-application-readback-path"
    static let initialPresentationResolutionNotificationArgument =
        "--flowtab-ui-initial-presentation-resolution-notification-name"
    static let initialPresentationResolutionReadbackPathArgument =
        "--flowtab-ui-initial-presentation-resolution-readback-path"
    static let axSuppressionReadbackRouteArgument =
        "--flowtab-ui-ax-suppression-readback-route"
    static let tabSwitchStressEvidenceNotificationArgument =
        "--flowtab-tab-stress-evidence-notification-name"

    static var argumentsOverrideForTesting: [String]?
    static var environmentOverrideForTesting: [String: String]?

    private static let uiTestArguments: Set<String> = [
        "--flowtab-ui-ax-trusted",
        currentAppProjectionEvidenceRouteArgument,
        "--flowtab-ui-enable-mock-hotkey-effects",
        "--flowtab-ui-enable-verbose-logs",
        "--flowtab-ui-frontmost-bundle-id",
        homeInitialProjectionApplicationRouteArgument,
        homeInitialProjectionApplicationReadbackPathArgument,
        initialPresentationResolutionNotificationArgument,
        initialPresentationResolutionReadbackPathArgument,
        "--flowtab-ui-initial-panel-occlusion-stale-ms",
        "--flowtab-ui-listen-switcher-trigger",
        "--flowtab-ui-mock-launch-at-login-service",
        "--flowtab-ui-mock-runtime",
        "--flowtab-ui-mock-runtime-variant",
        "--flowtab-ui-mock-window-preview-delay-ms",
        "--flowtab-ui-mock-window-previews",
        "--flowtab-ui-open-in-app-window-switcher",
        "--flowtab-ui-open-switcher",
        "--flowtab-ui-open-switcher-search",
        "--flowtab-ui-permission-state-path",
        axSuppressionReadbackRouteArgument,
        projectionAcknowledgementRouteArgument,
        "--flowtab-ui-record-hotkey-reload-diagnostics",
        "--flowtab-ui-redacted-runtime-logs",
        "--flowtab-ui-reset-defaults",
        "--flowtab-ui-runtime-log-level",
        "--flowtab-ui-screen-trusted",
        "--flowtab-ui-seed-logs",
        "--flowtab-ui-seed-window-recency-app-id",
        "--flowtab-ui-seed-window-recency-window-id",
        "--flowtab-ui-suppress-home-on-launch",
        "--flowtab-ui-suppress-panel-activation",
        "--flowtab-ui-switcher-command-payload-path"
    ]

    private static var arguments: [String] {
        argumentsOverrideForTesting ?? ProcessInfo.processInfo.arguments
    }

    private static var environment: [String: String] {
        environmentOverrideForTesting ?? ProcessInfo.processInfo.environment
    }

    static var usesMockRuntimeProjection: Bool {
        containsUITestArgument("--flowtab-ui-mock-runtime")
    }

    static var usesMockWindowPreviews: Bool {
        containsUITestArgument("--flowtab-ui-mock-window-previews")
    }

    static var mockWindowPreviewDelayMilliseconds: Int? {
        guard let rawValue = uiTestValue(after: "--flowtab-ui-mock-window-preview-delay-ms") else {
            return nil
        }
        return Int(rawValue)
    }

    static var resetsUserDefaultsOnLaunch: Bool {
        containsUITestArgument("--flowtab-ui-reset-defaults")
    }

    static var opensSwitcherOnLaunch: Bool {
        containsUITestArgument("--flowtab-ui-open-switcher")
            || containsUITestArgument("--flowtab-ui-open-switcher-search")
            || containsUITestArgument("--flowtab-ui-open-in-app-window-switcher")
    }

    static var listensForSwitcherTriggerNotifications: Bool {
        containsUITestArgument("--flowtab-ui-listen-switcher-trigger")
    }

    static var suppressesHomeWindowOnLaunch: Bool {
        isRunningUnitTests
            || containsUITestArgument("--flowtab-ui-suppress-home-on-launch")
    }

    static var suppressesPanelApplicationActivation: Bool {
        containsUITestArgument("--flowtab-ui-suppress-panel-activation")
    }

    static var opensInAppWindowSwitcherOnLaunch: Bool {
        containsUITestArgument("--flowtab-ui-open-in-app-window-switcher")
    }

    static var entersSearchOnLaunch: Bool {
        containsUITestArgument("--flowtab-ui-open-switcher-search")
    }

    static var switcherCommandPayloadPath: String? {
        uiTestValue(after: "--flowtab-ui-switcher-command-payload-path")
    }

    static var frontmostBundleIdentifierOverride: String? {
        uiTestValue(after: "--flowtab-ui-frontmost-bundle-id")
    }

    static var projectionAcknowledgementRoutes:
        [FlowTabUITestProjectionAcknowledgementRoute]
    {
        guard isRunningUITests else { return [] }
        var routes:
            [FlowTabUITestProjectionAcknowledgementRoute] = []
        var notificationNames: Set<String> = []
        for index in arguments.indices
        where arguments[index]
            == projectionAcknowledgementRouteArgument
        {
            guard index + 3 < arguments.count else { continue }
            let notificationName = arguments[index + 1]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let bundleIdentifier = arguments[index + 2]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !notificationName.isEmpty,
                  !bundleIdentifier.isEmpty,
                  let expectedWindowCount =
                    Int(arguments[index + 3]),
                  expectedWindowCount > 0,
                  notificationNames.insert(
                    notificationName
                  ).inserted
            else {
                continue
            }
            routes.append(
                FlowTabUITestProjectionAcknowledgementRoute(
                    notificationName:
                        Notification.Name(notificationName),
                    bundleIdentifier: bundleIdentifier,
                    expectedWindowCount: expectedWindowCount
                )
            )
        }
        return routes
    }

    static var currentAppProjectionEvidenceRoute:
        FlowTabUITestCurrentAppProjectionEvidenceRoute?
    {
        guard isRunningUITests else { return nil }
        for index in arguments.indices
        where arguments[index]
            == currentAppProjectionEvidenceRouteArgument
        {
            guard index + 3 < arguments.count else {
                continue
            }
            let notificationName = arguments[index + 1]
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            let bundleIdentifier = arguments[index + 2]
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            let readbackPath = arguments[index + 3]
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            guard !notificationName.isEmpty,
                  !bundleIdentifier.isEmpty,
                  !readbackPath.isEmpty,
                  NSString(string: readbackPath).isAbsolutePath
            else {
                continue
            }
            return FlowTabUITestCurrentAppProjectionEvidenceRoute(
                notificationName:
                    Notification.Name(notificationName),
                readbackURL:
                    URL(
                        fileURLWithPath: readbackPath,
                        isDirectory: false
                    )
                    .standardizedFileURL,
                bundleIdentifier: bundleIdentifier
            )
        }
        return nil
    }

    static var homeInitialProjectionApplicationRoute:
        FlowTabUITestHomeInitialProjectionApplicationRoute?
    {
        guard isRunningUITests,
              let notificationName = uiTestValue(
                after:
                    homeInitialProjectionApplicationRouteArgument
              )?.trimmingCharacters(
                in: .whitespacesAndNewlines
              ),
              !notificationName.isEmpty,
              let readbackPath = uiTestValue(
                after:
                    homeInitialProjectionApplicationReadbackPathArgument
              )?.trimmingCharacters(
                in: .whitespacesAndNewlines
              ),
              !readbackPath.isEmpty,
              NSString(string: readbackPath).isAbsolutePath
        else {
            return nil
        }
        return FlowTabUITestHomeInitialProjectionApplicationRoute(
            notificationName:
                Notification.Name(notificationName),
            readbackURL:
                URL(
                    fileURLWithPath: readbackPath,
                    isDirectory: false
                )
                .standardizedFileURL
        )
    }

    static var initialPresentationResolutionRoute:
        FlowTabUITestInitialPresentationResolutionRoute?
    {
        guard isRunningUITests,
              let notificationName = uiTestValue(
                after:
                    initialPresentationResolutionNotificationArgument
              )?.trimmingCharacters(
                in: .whitespacesAndNewlines
              ),
              !notificationName.isEmpty,
              let readbackPath = uiTestValue(
                after:
                    initialPresentationResolutionReadbackPathArgument
              )?.trimmingCharacters(
                in: .whitespacesAndNewlines
              ),
              !readbackPath.isEmpty,
              NSString(string: readbackPath).isAbsolutePath
        else {
            return nil
        }
        return FlowTabUITestInitialPresentationResolutionRoute(
            notificationName:
                Notification.Name(notificationName),
            readbackURL:
                URL(
                    fileURLWithPath: readbackPath,
                    isDirectory: false
                )
                .standardizedFileURL
        )
    }

    static var axSuppressionReadbackRoutes:
        [FlowTabUITestAXSuppressionReadbackRoute]
    {
        guard isRunningUITests else { return [] }
        var routes:
            [FlowTabUITestAXSuppressionReadbackRoute] = []
        var completionNames: Set<String> = []
        var verificationNames: Set<String> = []
        for index in arguments.indices
        where arguments[index]
            == axSuppressionReadbackRouteArgument
        {
            guard index + 4 < arguments.count else {
                continue
            }
            let completionName = arguments[index + 1]
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            let verificationName = arguments[index + 2]
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            let bundleIdentifier = arguments[index + 3]
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            guard !completionName.isEmpty,
                  !verificationName.isEmpty,
                  !bundleIdentifier.isEmpty,
                  let expectedWindowCount =
                    Int(arguments[index + 4]),
                  expectedWindowCount > 0,
                  completionNames.insert(
                    completionName
                  ).inserted,
                  verificationNames.insert(
                    verificationName
                  ).inserted
            else {
                continue
            }
            routes.append(
                FlowTabUITestAXSuppressionReadbackRoute(
                    completionNotificationName:
                        Notification.Name(
                            completionName
                        ),
                    verificationNotificationName:
                        Notification.Name(
                            verificationName
                        ),
                    bundleIdentifier:
                        bundleIdentifier,
                    expectedWindowCount:
                        expectedWindowCount
                )
            )
        }
        return routes
    }

    static var accessibilityTrustedOverride: Bool? {
        if usesDynamicPermissionState {
            return dynamicPermissionState?.accessibilityTrusted ?? false
        }
        return uiTestBoolValue(after: "--flowtab-ui-ax-trusted")
    }

    static var screenCaptureTrustedOverride: Bool? {
        if usesDynamicPermissionState {
            return dynamicPermissionState?.screenCaptureTrusted ?? false
        }
        return uiTestBoolValue(after: "--flowtab-ui-screen-trusted")
    }

    static var seededLogCount: Int? {
        guard let rawValue = uiTestValue(after: "--flowtab-ui-seed-logs") else { return nil }
        return Int(rawValue)
    }

    static var mockRuntimeVariant: String? {
        uiTestValue(after: "--flowtab-ui-mock-runtime-variant")
    }

    static var initialPanelOcclusionStaleMilliseconds: Int? {
        guard let rawValue = uiTestValue(after: "--flowtab-ui-initial-panel-occlusion-stale-ms") else {
            return nil
        }
        return Int(rawValue)
    }

    static var seededWindowRecency: (appID: String, windowID: String)? {
        guard
            let appID = uiTestValue(after: "--flowtab-ui-seed-window-recency-app-id"),
            let windowID = uiTestValue(after: "--flowtab-ui-seed-window-recency-window-id")
        else {
            return nil
        }
        return (appID, windowID)
    }

    static var runtimeLogLevelOverrideRawValue: String? {
        uiTestValue(after: "--flowtab-ui-runtime-log-level")
    }

    static var enablesVerboseRuntimeLogs: Bool {
        containsUITestArgument("--flowtab-ui-enable-verbose-logs")
    }

    static var requiresRedactedRuntimeLogs: Bool {
        containsUITestArgument("--flowtab-ui-redacted-runtime-logs")
    }

    static var recordsHotkeyReloadDiagnostics: Bool {
        containsUITestArgument("--flowtab-ui-record-hotkey-reload-diagnostics")
    }

    static var usesMockLaunchAtLoginService: Bool {
        containsUITestArgument("--flowtab-ui-mock-launch-at-login-service")
    }

    static var enablesMockHotkeyEffects: Bool {
        containsUITestArgument("--flowtab-ui-enable-mock-hotkey-effects")
    }

    static var runsTabSwitchStressTest: Bool {
        arguments.contains("--flowtab-tab-stress")
    }

    static var isRunningUITests: Bool {
        environment[uiTestingEnvironmentKey] == uiTestingEnvironmentValue
            && arguments.contains(where: { uiTestArguments.contains($0) })
    }

    static var isRunningUnitTests: Bool {
        guard !isRunningUITests else { return false }
        guard let bundlePath = environment[unitTestingBundlePathEnvironmentKey] else {
            return false
        }
        return URL(fileURLWithPath: bundlePath).lastPathComponent == "FlowTabTests.xctest"
    }

    static var showsSwitcherDiagnostics: Bool {
        isRunningUITests && (opensSwitcherOnLaunch || listensForSwitcherTriggerNotifications)
    }

    static var tabSwitchStressDurationSeconds: Double {
        max(1, Double(value(after: "--flowtab-tab-stress-duration") ?? "") ?? 30)
    }

    static var tabSwitchStressIntervalMilliseconds: Double {
        max(1, Double(value(after: "--flowtab-tab-stress-interval-ms") ?? "") ?? 20)
    }

    static var tabSwitchStressEvidenceNotificationName:
        String?
    {
        value(
            after:
                tabSwitchStressEvidenceNotificationArgument
        )
    }

    private static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else { return nil }
        return arguments[nextIndex]
    }

    private static func containsUITestArgument(_ flag: String) -> Bool {
        isRunningUITests && arguments.contains(flag)
    }

    private static func uiTestValue(after flag: String) -> String? {
        guard isRunningUITests else { return nil }
        return value(after: flag)
    }

    private static func uiTestBoolValue(after flag: String) -> Bool? {
        guard isRunningUITests else { return nil }
        return boolValue(after: flag)
    }

    private struct DynamicPermissionState: Decodable {
        let accessibilityTrusted: Bool
        let screenCaptureTrusted: Bool
    }

    private static var usesDynamicPermissionState: Bool {
        uiTestValue(after: "--flowtab-ui-permission-state-path") != nil
    }

    private static var dynamicPermissionState: DynamicPermissionState? {
        guard
            let rawPath = uiTestValue(
                after: "--flowtab-ui-permission-state-path"
            ),
            NSString(string: rawPath).isAbsolutePath
        else {
            return nil
        }
        let stateURL = URL(
            fileURLWithPath: rawPath,
            isDirectory: false
        ).standardizedFileURL
        guard let data = try? Data(contentsOf: stateURL) else {
            return nil
        }
        return try? JSONDecoder().decode(
            DynamicPermissionState.self,
            from: data
        )
    }

    private static func boolValue(after flag: String) -> Bool? {
        guard let rawValue = value(after: flag)?.lowercased() else { return nil }
        switch rawValue {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return nil
        }
    }
}
#endif
