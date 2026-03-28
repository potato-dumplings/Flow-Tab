import Foundation

public struct SwitcherSession: Sendable {
    public private(set) var mode: SessionMode
    public private(set) var selectedAppIndex: Int
    public private(set) var selectedGroupIndex: Int
    public private(set) var selectedWindowIndexByAppID: [String: Int]
    public private(set) var rememberedWindowIDByAppID: [String: String]

    public let preferences: SwitcherPreferences
    public let apps: [AppSwitchCandidate]
    public let groups: [AppGroup]

    public init(
        apps: [AppSwitchCandidate],
        preferences: SwitcherPreferences = .default,
        triggerDirection: CycleDirection = .forward,
        rememberedWindowIDByAppID: [String: String] = [:]
    ) {
        self.preferences = preferences
        self.apps = apps
        self.groups = Grouping.buildGroups(from: apps)
        self.mode = .appCycle
        self.selectedAppIndex = 0
        self.selectedGroupIndex = 0
        self.rememberedWindowIDByAppID = rememberedWindowIDByAppID

        var initialWindowIndices: [String: Int] = [:]
        for app in apps {
            initialWindowIndices[app.id] = Self.initialWindowIndex(
                for: app,
                strategy: preferences.windowSwitchingStrategy,
                rememberedWindowID: rememberedWindowIDByAppID[app.id]
            )
        }
        self.selectedWindowIndexByAppID = initialWindowIndices

        if !apps.isEmpty {
            selectedAppIndex = Self.initialAppIndex(count: apps.count, direction: triggerDirection)
            selectedGroupIndex = Grouping.groupIndex(containing: selectedApp.id, groups: groups)
        }
    }

    public var selectedApp: AppSwitchCandidate {
        apps[selectedAppIndex]
    }

    public var selectedWindow: WindowCandidate? {
        guard case .windowCycle(let appID) = mode else { return nil }
        guard let app = apps.first(where: { $0.id == appID }) else { return nil }
        guard !app.windows.isEmpty else { return nil }
        let windowIndex = selectedWindowIndexByAppID[appID] ?? 0
        return app.windows[safe: windowIndex]
    }

    public mutating func handle(_ keyInput: KeyInput) {
        guard !apps.isEmpty else { return }

        switch mode {
        case .appCycle:
            handleInAppCycle(keyInput)
        case .groupCycle:
            handleInGroupCycle(keyInput)
        case .windowCycle(let appID):
            handleInWindowCycle(keyInput, appID: appID)
        }
    }

    public mutating func releasePrimaryModifier() -> ActivationTarget? {
        commitSelection()
    }

    public mutating func commitSelection() -> ActivationTarget? {
        guard !apps.isEmpty else { return nil }

        if case .windowCycle(let appID) = mode {
            guard
                let app = apps.first(where: { $0.id == appID }),
                !app.windows.isEmpty
            else {
                return .app(appID: selectedApp.id)
            }

            let selectedWindowIndex = selectedWindowIndexByAppID[appID] ?? 0
            let window = app.windows[safe: selectedWindowIndex] ?? app.windows[0]
            rememberedWindowIDByAppID[appID] = window.id
            return activationTarget(appID: appID, window: window)
        }

        let app = selectedApp
        if let preferredWindow = preferredWindow(for: app) {
            return activationTarget(appID: app.id, window: preferredWindow)
        }
        return .app(appID: app.id)
    }

    private mutating func handleInAppCycle(_ keyInput: KeyInput) {
        switch keyInput {
        case .tabForward:
            moveApp(by: +1)
        case .tabBackward:
            moveApp(by: -1)
        case .leftArrow:
            moveApp(by: -1)
        case .rightArrow:
            moveApp(by: +1)
        case .upArrow:
            enterGroupCycle()
        case .downArrow:
            enterWindowCycleIfPossible()
        }
    }

    private mutating func handleInGroupCycle(_ keyInput: KeyInput) {
        switch keyInput {
        case .tabForward:
            moveAppInsideCurrentGroup(by: +1)
        case .tabBackward:
            moveAppInsideCurrentGroup(by: -1)
        case .leftArrow:
            moveGroup(by: -1)
        case .rightArrow:
            moveGroup(by: +1)
        case .downArrow:
            break
        case .upArrow:
            break
        }
    }

    private mutating func handleInWindowCycle(_ keyInput: KeyInput, appID: String) {
        switch keyInput {
        case .tabForward:
            moveWindow(appID: appID, by: +1)
        case .tabBackward:
            moveWindow(appID: appID, by: -1)
        case .upArrow:
            mode = .appCycle
        case .downArrow, .leftArrow, .rightArrow:
            break
        }
    }

    private mutating func moveApp(by delta: Int) {
        selectedAppIndex = Self.nextIndex(
            current: selectedAppIndex,
            count: apps.count,
            delta: delta,
            wraps: preferences.groupNavigationWraps
        )
        selectedGroupIndex = Grouping.groupIndex(containing: selectedApp.id, groups: groups)
    }

    private mutating func enterGroupCycle() {
        mode = .groupCycle
        selectedGroupIndex = Grouping.groupIndex(containing: selectedApp.id, groups: groups)
    }

    private mutating func moveGroup(by delta: Int) {
        guard !groups.isEmpty else { return }
        selectedGroupIndex = Self.nextIndex(
            current: selectedGroupIndex,
            count: groups.count,
            delta: delta,
            wraps: preferences.groupNavigationWraps
        )
        if let appID = groups[selectedGroupIndex].apps.first?.id {
            selectAppInternally(withID: appID)
        }
    }

    private mutating func moveAppInsideCurrentGroup(by delta: Int) {
        guard !groups.isEmpty else { return }
        let group = groups[selectedGroupIndex]
        guard !group.apps.isEmpty else { return }

        let currentLocalIndex = group.apps.firstIndex(where: { $0.id == selectedApp.id }) ?? 0
        let nextLocalIndex = Self.nextIndex(
            current: currentLocalIndex,
            count: group.apps.count,
            delta: delta,
            wraps: preferences.groupNavigationWraps
        )
        selectAppInternally(withID: group.apps[nextLocalIndex].id)
    }

    public mutating func enterWindowCycleIfPossible() {
        _ = enterWindowCycle(allowSingleWindow: false)
    }

    @discardableResult
    public mutating func enterWindowCycle(allowSingleWindow: Bool) -> Bool {
        let app = selectedApp
        guard !app.windows.isEmpty else { return false }
        if !allowSingleWindow, app.windows.count < 2 {
            return false
        }
        mode = .windowCycle(appID: app.id)
        return true
    }

    private mutating func moveWindow(appID: String, by delta: Int) {
        guard let app = apps.first(where: { $0.id == appID }) else { return }
        guard !app.windows.isEmpty else { return }

        let currentWindowIndex = selectedWindowIndexByAppID[appID] ?? 0
        selectedWindowIndexByAppID[appID] = Self.nextIndex(
            current: currentWindowIndex,
            count: app.windows.count,
            delta: delta,
            wraps: true
        )
    }

    @discardableResult
    public mutating func selectApp(withID appID: String) -> Bool {
        guard !apps.isEmpty else { return false }
        guard let appIndex = apps.firstIndex(where: { $0.id == appID }) else { return false }
        selectedAppIndex = appIndex
        selectedGroupIndex = Grouping.groupIndex(containing: appID, groups: groups)
        mode = .appCycle
        return true
    }

    @discardableResult
    public mutating func selectWindow(appID: String, windowID: String) -> Bool {
        guard let appIndex = apps.firstIndex(where: { $0.id == appID }) else { return false }
        let app = apps[appIndex]
        guard let windowIndex = app.windows.firstIndex(where: { $0.id == windowID }) else { return false }
        selectedAppIndex = appIndex
        selectedGroupIndex = Grouping.groupIndex(containing: appID, groups: groups)
        selectedWindowIndexByAppID[appID] = windowIndex
        mode = .windowCycle(appID: appID)
        return true
    }

    private mutating func selectAppInternally(withID appID: String) {
        if let appIndex = apps.firstIndex(where: { $0.id == appID }) {
            selectedAppIndex = appIndex
        }
    }

    private func preferredWindow(for app: AppSwitchCandidate) -> WindowCandidate? {
        guard !app.windows.isEmpty else { return nil }
        switch preferences.windowSwitchingStrategy {
        case .recentActiveWindow:
            return app.windows.max(by: { $0.lastActiveAt < $1.lastActiveAt })
        case .rememberLastSelectedWindow:
            if
                let rememberedID = rememberedWindowIDByAppID[app.id],
                let rememberedWindow = app.windows.first(where: { $0.id == rememberedID })
            {
                return rememberedWindow
            }
            return app.windows.max(by: { $0.lastActiveAt < $1.lastActiveAt })
        }
    }

    private func activationTarget(appID: String, window: WindowCandidate) -> ActivationTarget {
        if window.isMinimized && !preferences.autoRestoreMinimizedWindowOnSwitch {
            return .app(appID: appID)
        }

        return .window(
            appID: appID,
            windowID: window.id,
            restoreIfMinimized: window.isMinimized && preferences.autoRestoreMinimizedWindowOnSwitch
        )
    }

    private static func initialWindowIndex(
        for app: AppSwitchCandidate,
        strategy: WindowSwitchingStrategy,
        rememberedWindowID: String?
    ) -> Int {
        guard !app.windows.isEmpty else { return 0 }

        if
            strategy == .rememberLastSelectedWindow,
            let rememberedWindowID,
            let rememberedIndex = app.windows.firstIndex(where: { $0.id == rememberedWindowID })
        {
            return rememberedIndex
        }

        guard let index = app.windows.indices.max(by: { app.windows[$0].lastActiveAt < app.windows[$1].lastActiveAt }) else {
            return 0
        }
        return index
    }

    private static func initialAppIndex(count: Int, direction: CycleDirection) -> Int {
        guard count > 0 else { return 0 }
        if count == 1 { return 0 }
        switch direction {
        case .forward:
            return 1
        case .backward:
            return count - 1
        }
    }

    private static func nextIndex(
        current: Int,
        count: Int,
        delta: Int,
        wraps: Bool
    ) -> Int {
        guard count > 0 else { return 0 }

        if wraps {
            let raw = (current + delta) % count
            return raw >= 0 ? raw : raw + count
        }

        let candidate = current + delta
        return min(max(candidate, 0), count - 1)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
