import Foundation

struct SpaceFixtureConfiguredTab: Equatable {
    let title: String
    let identifier: String
    let isSelected: Bool
}

struct SpaceFixtureConfiguredWindow: Equatable {
    let configuredTitle: String
    let windowTitle: String
    let mode: SpaceFixtureWindowMode
    let tabs: [SpaceFixtureConfiguredTab]

    var isFullscreenTarget: Bool {
        mode == .fullscreen
    }
}

struct SpaceFixtureLaunchConfiguration: Equatable {
    static let defaultWindowCount = 3
    static let defaultWindowTitlePrefix = "Fixture"
    static let defaultEnterFullscreenDelayMilliseconds = 400
    static let minimumWindowCount = 1

    let windows: [SpaceFixtureConfiguredWindow]
    let windowTitlePrefix: String
    let usesStaggeredLayout: Bool
    let enterFullscreenDelayMilliseconds: Int
    let preservesDesktopAfterFullscreen: Bool
    let workflowName: String?
    let workflowAppID: String?

    var windowCount: Int {
        windows.count
    }

    var fullscreenWindowIndex: Int? {
        windows.firstIndex(where: \.isFullscreenTarget).map { $0 + 1 }
    }

    var windowTitles: [String] {
        windows.map(\.windowTitle)
    }

    init(
        windows: [SpaceFixtureConfiguredWindow],
        windowTitlePrefix: String,
        usesStaggeredLayout: Bool,
        enterFullscreenDelayMilliseconds: Int,
        preservesDesktopAfterFullscreen: Bool,
        workflowName: String? = nil,
        workflowAppID: String? = nil
    ) {
        self.windows = windows
        self.windowTitlePrefix = windowTitlePrefix
        self.usesStaggeredLayout = usesStaggeredLayout
        self.enterFullscreenDelayMilliseconds = enterFullscreenDelayMilliseconds
        self.preservesDesktopAfterFullscreen = preservesDesktopAfterFullscreen
        self.workflowName = workflowName
        self.workflowAppID = workflowAppID
    }

    init(
        windowCount: Int,
        fullscreenWindowIndex: Int?,
        windowTitlePrefix: String,
        usesStaggeredLayout: Bool,
        enterFullscreenDelayMilliseconds: Int,
        preservesDesktopAfterFullscreen: Bool
    ) {
        let normalizedWindowCount = max(Self.minimumWindowCount, windowCount)
        let normalizedFullscreenWindowIndex: Int?
        if let fullscreenWindowIndex, (1...normalizedWindowCount).contains(fullscreenWindowIndex) {
            normalizedFullscreenWindowIndex = fullscreenWindowIndex
        } else {
            normalizedFullscreenWindowIndex = nil
        }
        let normalizedTitlePrefix = windowTitlePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitlePrefix = normalizedTitlePrefix.isEmpty
            ? Self.defaultWindowTitlePrefix
            : normalizedTitlePrefix

        let windows = (1...normalizedWindowCount).map { index in
            let title = "\(resolvedTitlePrefix) \(index)"
            return SpaceFixtureConfiguredWindow(
                configuredTitle: title,
                windowTitle: title,
                mode: normalizedFullscreenWindowIndex == index ? .fullscreen : .standard,
                tabs: []
            )
        }

        self.init(
            windows: windows,
            windowTitlePrefix: resolvedTitlePrefix,
            usesStaggeredLayout: usesStaggeredLayout,
            enterFullscreenDelayMilliseconds: max(0, enterFullscreenDelayMilliseconds),
            preservesDesktopAfterFullscreen: preservesDesktopAfterFullscreen
        )
    }

    func title(forWindowIndex index: Int) -> String {
        let normalizedIndex = max(0, index - 1)
        guard windows.indices.contains(normalizedIndex) else {
            return "\(windowTitlePrefix) \(index)"
        }
        return windows[normalizedIndex].windowTitle
    }
}

extension SpaceFixtureLaunchConfiguration {
    init(arguments: [String]) {
        let normalizedWindowCount = max(
            Self.minimumWindowCount,
            Self.intValue(after: "--window-count", in: arguments) ?? Self.defaultWindowCount
        )
        let normalizedDelayMilliseconds = max(
            0,
            Self.intValue(after: "--enter-fullscreen-delay-ms", in: arguments)
                ?? Self.defaultEnterFullscreenDelayMilliseconds
        )
        let normalizedWindowTitlePrefix = Self.stringValue(after: "--window-title-prefix", in: arguments)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        self.init(
            windowCount: normalizedWindowCount,
            fullscreenWindowIndex: Self.intValue(after: "--fullscreen-window-index", in: arguments),
            windowTitlePrefix: normalizedWindowTitlePrefix?.isEmpty == false
                ? normalizedWindowTitlePrefix!
                : Self.defaultWindowTitlePrefix,
            usesStaggeredLayout: arguments.contains("--staggered-layout"),
            enterFullscreenDelayMilliseconds: normalizedDelayMilliseconds,
            preservesDesktopAfterFullscreen: arguments.contains("--preserve-desktop-after-fullscreen")
        )
    }

    static func load(arguments: [String]) throws -> SpaceFixtureLaunchConfiguration {
        let workflowConfigPath = Self.stringValue(after: "--workflow-config", in: arguments)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let workflowAppID = Self.stringValue(after: "--workflow-app-id", in: arguments)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if workflowConfigPath?.isEmpty == false || workflowAppID?.isEmpty == false {
            guard let workflowConfigPath, workflowConfigPath.isEmpty == false else {
                throw SpaceFixtureLaunchConfigurationError.missingWorkflowConfigPath
            }
            guard let workflowAppID, workflowAppID.isEmpty == false else {
                throw SpaceFixtureLaunchConfigurationError.missingWorkflowAppID
            }
            return try Self.loadWorkflowConfiguration(
                workflowConfigPath: workflowConfigPath,
                workflowAppID: workflowAppID,
                arguments: arguments
            )
        }

        return SpaceFixtureLaunchConfiguration(arguments: arguments)
    }

    private static func loadWorkflowConfiguration(
        workflowConfigPath: String,
        workflowAppID: String,
        arguments: [String]
    ) throws -> SpaceFixtureLaunchConfiguration {
        let workflowURL = URL(fileURLWithPath: workflowConfigPath)
        let workflowConfiguration = try SpaceFixtureWorkflowConfiguration.load(from: workflowURL)
        guard let appConfiguration = workflowConfiguration.appConfiguration(for: workflowAppID) else {
            throw SpaceFixtureLaunchConfigurationError.workflowAppNotFound(workflowAppID)
        }

        let normalizedWindows = normalizeWorkflowWindows(appConfiguration.windows)
        guard normalizedWindows.isEmpty == false else {
            throw SpaceFixtureLaunchConfigurationError.workflowAppHasNoWindows(workflowAppID)
        }

        return SpaceFixtureLaunchConfiguration(
            windows: normalizedWindows,
            windowTitlePrefix: Self.defaultWindowTitlePrefix,
            usesStaggeredLayout: arguments.contains("--staggered-layout"),
            enterFullscreenDelayMilliseconds: max(
                0,
                Self.intValue(after: "--enter-fullscreen-delay-ms", in: arguments)
                    ?? Self.defaultEnterFullscreenDelayMilliseconds
            ),
            preservesDesktopAfterFullscreen: arguments.contains("--preserve-desktop-after-fullscreen"),
            workflowName: workflowConfiguration.workflowName,
            workflowAppID: appConfiguration.appID
        )
    }

    private static func normalizeWorkflowWindows(
        _ workflowWindows: [SpaceFixtureWorkflowWindowConfiguration]
    ) -> [SpaceFixtureConfiguredWindow] {
        workflowWindows.enumerated().map { offset, window in
            let normalizedTabs = normalizeWorkflowTabs(window.tabs)
            let configuredTitle = normalizedTitle(
                window.title,
                fallback: "Window \(offset + 1)"
            )
            let windowTitle = normalizedTabs.first(where: \.isSelected)?.title ?? configuredTitle
            return SpaceFixtureConfiguredWindow(
                configuredTitle: configuredTitle,
                windowTitle: windowTitle,
                mode: window.mode,
                tabs: normalizedTabs
            )
        }
    }

    private static func normalizeWorkflowTabs(
        _ workflowTabs: [SpaceFixtureWorkflowTabConfiguration]
    ) -> [SpaceFixtureConfiguredTab] {
        let baseTabs = workflowTabs.enumerated().map { offset, tab in
            SpaceFixtureConfiguredTab(
                title: normalizedTitle(tab.title, fallback: "Tab \(offset + 1)"),
                identifier: normalizedTitle(tab.identifier, fallback: "tab-\(offset + 1)"),
                isSelected: tab.isSelected
            )
        }

        guard baseTabs.isEmpty == false else { return [] }
        let selectedIndex = baseTabs.firstIndex(where: \.isSelected) ?? 0
        return baseTabs.enumerated().map { offset, tab in
            SpaceFixtureConfiguredTab(
                title: tab.title,
                identifier: tab.identifier,
                isSelected: offset == selectedIndex
            )
        }
    }

    private static func normalizedTitle(
        _ rawValue: String?,
        fallback: String
    ) -> String {
        let trimmedValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue?.isEmpty == false ? trimmedValue! : fallback
    }

    fileprivate static func stringValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else { return nil }
        return arguments[nextIndex]
    }

    fileprivate static func intValue(after flag: String, in arguments: [String]) -> Int? {
        guard let value = stringValue(after: flag, in: arguments) else { return nil }
        return Int(value)
    }
}
