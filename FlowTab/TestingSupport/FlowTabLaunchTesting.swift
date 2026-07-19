import AppKit
import Foundation

enum FlowTabTestLaunchOptions {
    static let uiTestingEnvironmentKey = "FLOWTAB_UI_TESTING"
    static let uiTestingEnvironmentValue = "1"

    static var argumentsOverrideForTesting: [String]?
    static var environmentOverrideForTesting: [String: String]?

    private static let uiTestArguments: Set<String> = [
        "--flowtab-ui-ax-trusted",
        "--flowtab-ui-enable-mock-hotkey-effects",
        "--flowtab-ui-enable-verbose-logs",
        "--flowtab-ui-frontmost-bundle-id",
        "--flowtab-ui-initial-panel-occlusion-stale-ms",
        "--flowtab-ui-listen-switcher-trigger",
        "--flowtab-ui-mock-launch-at-login-service",
        "--flowtab-ui-mock-runtime",
        "--flowtab-ui-mock-runtime-variant",
        "--flowtab-ui-mock-window-previews",
        "--flowtab-ui-open-in-app-window-switcher",
        "--flowtab-ui-open-switcher",
        "--flowtab-ui-open-switcher-search",
        "--flowtab-ui-record-hotkey-reload-diagnostics",
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
        containsUITestArgument("--flowtab-ui-suppress-home-on-launch")
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

    static var accessibilityTrustedOverride: Bool? {
        uiTestBoolValue(after: "--flowtab-ui-ax-trusted")
    }

    static var screenCaptureTrustedOverride: Bool? {
        uiTestBoolValue(after: "--flowtab-ui-screen-trusted")
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

    static var showsSwitcherDiagnostics: Bool {
        isRunningUITests && (opensSwitcherOnLaunch || listensForSwitcherTriggerNotifications)
    }

    static var tabSwitchStressDurationSeconds: Double {
        max(1, Double(value(after: "--flowtab-tab-stress-duration") ?? "") ?? 30)
    }

    static var tabSwitchStressIntervalMilliseconds: Double {
        max(1, Double(value(after: "--flowtab-tab-stress-interval-ms") ?? "") ?? 20)
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

protocol TabSwitchStressRunning: AnyObject {
    @MainActor func startIfNeeded()
}

@MainActor
final class TabSwitchStressRunner: TabSwitchStressRunning {
    static let shared = TabSwitchStressRunner()

    private var task: Task<Void, Never>?

    private init() {}

    func startIfNeeded() {
        guard task == nil else { return }
        guard FlowTabTestLaunchOptions.runsTabSwitchStressTest else { return }

        let sleepNanoseconds = UInt64(
            FlowTabTestLaunchOptions.tabSwitchStressIntervalMilliseconds * 1_000_000
        )
        let endTime = Date().addingTimeInterval(
            FlowTabTestLaunchOptions.tabSwitchStressDurationSeconds
        )

        task = Task { @MainActor in
            defer { self.task = nil }

            let cycle: [HomeTab] = [.home, .logs, .settings]
            var index = 0
            while Date() < endTime {
                HomeTabState.shared.selectedTab = cycle[index % cycle.count]
                index += 1
                try? await Task.sleep(nanoseconds: sleepNanoseconds)
            }
            NSApp.terminate(nil)
        }
    }
}
