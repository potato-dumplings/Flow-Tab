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

struct RuntimeWindowContext {
    let id: String
    let title: String
    let isMinimized: Bool
    var cgWindowID: CGWindowID?
    var inferredTitleBarStyle: WindowTitleBarStyleGuess?
    var axWindow: AXUIElement? = nil
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
