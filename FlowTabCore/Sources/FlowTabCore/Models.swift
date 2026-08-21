import Foundation

public struct WindowCandidate: Equatable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let isMinimized: Bool
    public let lastActiveAt: TimeInterval

    public init(
        id: String,
        title: String,
        isMinimized: Bool,
        lastActiveAt: TimeInterval
    ) {
        self.id = id
        self.title = title
        self.isMinimized = isMinimized
        self.lastActiveAt = lastActiveAt
    }
}

public struct AppSwitchCandidate: Equatable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let groupID: String
    public let lastActiveAt: TimeInterval
    public var windows: [WindowCandidate]

    public init(
        id: String,
        displayName: String,
        groupID: String,
        lastActiveAt: TimeInterval,
        windows: [WindowCandidate]
    ) {
        self.id = id
        self.displayName = displayName
        self.groupID = groupID
        self.lastActiveAt = lastActiveAt
        self.windows = windows
    }
}

public struct AppGroup: Equatable, Sendable {
    public let id: String
    public let apps: [AppSwitchCandidate]

    public init(id: String, apps: [AppSwitchCandidate]) {
        self.id = id
        self.apps = apps
    }
}

public enum SessionMode: Equatable, Sendable {
    case appCycle
    case groupCycle
    case windowCycle(appID: String)
}

public enum CycleDirection: Sendable {
    case forward
    case backward
}

public enum KeyInput: Equatable, Sendable {
    case tabForward
    case tabBackward
    case upArrow
    case downArrow
    case leftArrow
    case rightArrow
}

public struct AppActivationFallback: Equatable, Sendable {
    public let windowID: String
    public let restoreIfMinimized: Bool

    public init(windowID: String, restoreIfMinimized: Bool) {
        self.windowID = windowID
        self.restoreIfMinimized = restoreIfMinimized
    }
}

public enum ActivationTarget: Equatable, Sendable {
    case app(appID: String, fallback: AppActivationFallback? = nil)
    case window(appID: String, windowID: String, restoreIfMinimized: Bool)
}
