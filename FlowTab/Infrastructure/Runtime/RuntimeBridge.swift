import AppKit
import ApplicationServices
import Foundation
import FlowTabCore

enum WindowTitleBarStyleGuess: String {
    case dark
    case light
}

struct RuntimeSnapshot {
    let apps: [AppSwitchCandidate]
    let contextsByID: [String: RuntimeAppContext]
}

struct RuntimeAppContext {
    let appID: String
    let runningApp: NSRunningApplication
    let windowsByID: [String: RuntimeWindowContext]
}

enum WindowBindingConfirmationSource: String {
    case stickyBinding
    case publicExactMatch
    case privateExactBridge
    case fullscreenContentRebinding
    case fullscreenContentFallbackBinding
    case desktopSiblingBinding
}

struct RuntimeWindowContext {
    let id: String
    let title: String
    let isMinimized: Bool
    let ownerPID: pid_t
    var cgWindowID: CGWindowID?
    let spaceIDs: [Int]
    var inferredTitleBarStyle: WindowTitleBarStyleGuess?
    var activationHandleID: String?
    var axWindow: AXUIElement? = nil
    let frame: CGRect?
    let allowsPublicAXRecovery: Bool
    let hasStickyBinding: Bool
    let lastConfirmationSource: WindowBindingConfirmationSource?

    init(
        id: String,
        title: String,
        isMinimized: Bool,
        ownerPID: pid_t = 0,
        cgWindowID: CGWindowID? = nil,
        spaceIDs: [Int] = [],
        inferredTitleBarStyle: WindowTitleBarStyleGuess? = nil,
        activationHandleID: String? = nil,
        axWindow: AXUIElement? = nil,
        frame: CGRect? = nil,
        allowsPublicAXRecovery: Bool = false,
        hasStickyBinding: Bool = false,
        lastConfirmationSource: WindowBindingConfirmationSource? = nil
    ) {
        self.id = id
        self.title = title
        self.isMinimized = isMinimized
        self.ownerPID = ownerPID
        self.cgWindowID = cgWindowID
        self.spaceIDs = RuntimeWindowTopologyClassifier.normalizedSpaceIDs(spaceIDs)
        self.inferredTitleBarStyle = inferredTitleBarStyle
        self.activationHandleID = activationHandleID
        self.axWindow = axWindow
        self.frame = frame
        self.allowsPublicAXRecovery = allowsPublicAXRecovery
        self.hasStickyBinding = hasStickyBinding
        self.lastConfirmationSource = lastConfirmationSource
    }
}


struct RuntimeHomeAppSummary: Equatable, Identifiable {
    let appID: String
    let displayName: String
    let groupID: String
    let lastActiveAt: TimeInterval
    let windowCount: Int
    let pid: pid_t

    var id: String { appID }
}

struct RuntimeHomeAppSnapshot {
    let summary: RuntimeHomeAppSummary
    let candidate: AppSwitchCandidate
    let context: RuntimeAppContext
}
