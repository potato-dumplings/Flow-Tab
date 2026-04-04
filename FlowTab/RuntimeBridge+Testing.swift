import Foundation

enum FlowTabTestLaunchOptions {
    // Allows deterministic launch-argument parsing tests without mutating process state.
    static var argumentsOverrideForTesting: [String]?

    private static var arguments: [String] {
        argumentsOverrideForTesting ?? ProcessInfo.processInfo.arguments
    }

    static var usesMockRuntimeSnapshot: Bool {
        arguments.contains("--flowtab-ui-mock-runtime")
    }

    static var resetsUserDefaultsOnLaunch: Bool {
        arguments.contains("--flowtab-ui-reset-defaults")
    }

    static var opensSwitcherOnLaunch: Bool {
        arguments.contains("--flowtab-ui-open-switcher")
            || arguments.contains("--flowtab-ui-open-switcher-search")
    }

    static var entersSearchOnLaunch: Bool {
        arguments.contains("--flowtab-ui-open-switcher-search")
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

    static var runtimeLogLevelOverrideRawValue: String? {
        value(after: "--flowtab-ui-runtime-log-level")
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
