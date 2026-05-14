import AppKit
import Foundation

enum FlowTabTestLaunchOptions {
    static var argumentsOverrideForTesting: [String]?

    private static var arguments: [String] {
        argumentsOverrideForTesting ?? ProcessInfo.processInfo.arguments
    }

    static var usesMockRuntimeSnapshot: Bool {
        arguments.contains("--flowtab-ui-mock-runtime")
    }

    static var usesMockWindowPreviews: Bool {
        arguments.contains("--flowtab-ui-mock-window-previews")
    }

    static var resetsUserDefaultsOnLaunch: Bool {
        arguments.contains("--flowtab-ui-reset-defaults")
    }

    static var opensSwitcherOnLaunch: Bool {
        arguments.contains("--flowtab-ui-open-switcher")
            || arguments.contains("--flowtab-ui-open-switcher-search")
            || arguments.contains("--flowtab-ui-open-in-app-window-switcher")
    }

    static var listensForSwitcherTriggerNotifications: Bool {
        arguments.contains("--flowtab-ui-listen-switcher-trigger")
    }

    static var suppressesHomeWindowOnLaunch: Bool {
        arguments.contains("--flowtab-ui-suppress-home-on-launch")
    }

    static var suppressesPanelApplicationActivation: Bool {
        arguments.contains("--flowtab-ui-suppress-panel-activation")
    }

    static var opensInAppWindowSwitcherOnLaunch: Bool {
        arguments.contains("--flowtab-ui-open-in-app-window-switcher")
    }

    static var entersSearchOnLaunch: Bool {
        arguments.contains("--flowtab-ui-open-switcher-search")
    }

    static var frontmostBundleIdentifierOverride: String? {
        value(after: "--flowtab-ui-frontmost-bundle-id")
    }

    static var switcherCommandPayloadPath: String? {
        value(after: "--flowtab-ui-switcher-command-payload-path")
    }

    static var accessibilityTrustedOverride: Bool? {
        boolValue(after: "--flowtab-ui-ax-trusted")
    }

    static var screenCaptureTrustedOverride: Bool? {
        boolValue(after: "--flowtab-ui-screen-trusted")
    }

    static var seededLogCount: Int? {
        guard let rawValue = value(after: "--flowtab-ui-seed-logs") else { return nil }
        return Int(rawValue)
    }

    static var mockRuntimeVariant: String? {
        value(after: "--flowtab-ui-mock-runtime-variant")
    }

    static var initialPanelOcclusionStaleMilliseconds: Int? {
        guard let rawValue = value(after: "--flowtab-ui-initial-panel-occlusion-stale-ms") else {
            return nil
        }
        return Int(rawValue)
    }

    static var seededWindowRecency: (appID: String, windowID: String)? {
        guard
            let appID = value(after: "--flowtab-ui-seed-window-recency-app-id"),
            let windowID = value(after: "--flowtab-ui-seed-window-recency-window-id")
        else {
            return nil
        }
        return (appID, windowID)
    }

    static var runtimeLogLevelOverrideRawValue: String? {
        value(after: "--flowtab-ui-runtime-log-level")
    }

    static var enablesVerboseRuntimeLogs: Bool {
        arguments.contains("--flowtab-ui-enable-verbose-logs")
    }

    static var recordsHotkeyReloadDiagnostics: Bool {
        arguments.contains("--flowtab-ui-record-hotkey-reload-diagnostics")
    }

    static var usesMockLaunchAtLoginService: Bool {
        arguments.contains("--flowtab-ui-mock-launch-at-login-service")
    }

    static var enablesMockHotkeyEffects: Bool {
        arguments.contains("--flowtab-ui-enable-mock-hotkey-effects")
    }

    static var runsTabSwitchStressTest: Bool {
        arguments.contains("--flowtab-tab-stress")
    }

    static var isRunningUITests: Bool {
        arguments.contains(where: { $0.hasPrefix("--flowtab-ui-") })
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
