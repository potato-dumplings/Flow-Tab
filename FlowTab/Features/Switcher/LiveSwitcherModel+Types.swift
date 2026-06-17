import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

extension SessionMode {
    var debugName: String {
        switch self {
        case .appCycle:
            return "appCycle"
        case .groupCycle:
            return "groupCycle"
        case .windowCycle(let appID):
            return "windowCycle(\(appID))"
        }
    }
}

extension KeyInput {
    var debugName: String {
        switch self {
        case .tabForward:
            return "tabForward"
        case .tabBackward:
            return "tabBackward"
        case .upArrow:
            return "upArrow"
        case .downArrow:
            return "downArrow"
        case .leftArrow:
            return "leftArrow"
        case .rightArrow:
            return "rightArrow"
        }
    }
}

extension CycleDirection {
    var debugName: String {
        switch self {
        case .forward:
            return "forward"
        case .backward:
            return "backward"
        }
    }
}

enum SwitcherOverlayStyle {
    case appAndWindow
    case windowOnly

    var debugName: String {
        switch self {
        case .appAndWindow:
            return "appAndWindow"
        case .windowOnly:
            return "windowOnly"
        }
    }

    var contentTraceKind: String {
        switch self {
        case .appAndWindow:
            return "global"
        case .windowOnly:
            return "inApp"
        }
    }
}

struct WindowPreviewItem: Identifiable {
    let id: String
    let title: String
    let image: NSImage?
    let titleBarStyle: WindowTitleBarStyleGuess?
    let isSelected: Bool
}

struct WindowPreviewPageSummary {
    let itemCount: Int
    let selectedIndex: Int?
}

struct SearchAppResultItem: Identifiable {
    let id: String
    let app: AppSwitchCandidate
    let isSelected: Bool
}

struct SearchWindowResultItem: Identifiable {
    let id: String
    let title: String
    let appName: String
    let icon: NSImage?
    let isSelected: Bool
}

struct SearchHeaderHighlightItem {
    let title: String
    let icon: NSImage?
}

struct AppSwitcherProjectionSessionPayload {
    let apps: [AppSwitchCandidate]
    let contextsByID: [String: RuntimeAppContext]

    var windowCount: Int {
        apps.reduce(0) { $0 + $1.windows.count }
    }

    init(apps: [AppSwitchCandidate], contextsByID: [String: RuntimeAppContext]) {
        self.apps = apps
        self.contextsByID = contextsByID
    }

    init(projection: RuntimeAppSwitcherProjection) {
        self.init(
            apps: projection.appCycleApps,
            contextsByID: projection.contextsByID
        )
    }
}
