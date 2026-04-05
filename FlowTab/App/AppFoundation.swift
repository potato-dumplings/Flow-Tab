import AppKit
import SwiftUI
import FlowTabCore

protocol AppWindowOpeningWindow: AnyObject {
    var isPanelWindow: Bool { get }
    var isMiniaturized: Bool { get }
    var isVisible: Bool { get }
    var flowTabWindowIdentifier: String? { get }

    func deminiaturize(_ sender: Any?)
    func makeKeyAndOrderFront(_ sender: Any?)
    func orderFrontRegardless()
}

protocol AppWindowOpeningApplication: AnyObject {
    var isHidden: Bool { get }
    var appWindows: [any AppWindowOpeningWindow] { get }

    func activate(ignoringOtherApps flag: Bool)
    func unhide(_ sender: Any?)
    func sendShowSettingsWindowAction() -> Bool
}

extension NSWindow: AppWindowOpeningWindow {
    var isPanelWindow: Bool {
        self is NSPanel
    }

    var flowTabWindowIdentifier: String? {
        identifier?.rawValue
    }
}

extension NSApplication: AppWindowOpeningApplication {
    var appWindows: [any AppWindowOpeningWindow] {
        windows.map { $0 }
    }

    func sendShowSettingsWindowAction() -> Bool {
        sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

protocol MRUTracking {
    func startIfNeeded()
}

extension SystemAppMRUTracker: MRUTracking {}

enum HomeTab: Hashable {
    case home
    case logs
    case settings
}

@MainActor
final class HomeTabState: ObservableObject {
    static let shared = HomeTabState()
    @Published var selectedTab: HomeTab = .home

    private init() {}
}

enum AppWindowCoordinator {
    static let switcherPanelWindowIdentifier = "flowtab.switcher.panel"

    @MainActor
    static var activateMainWindowOrOpenHomeSceneOverride: (() -> Void)?

    static func openHome() {
        Task { @MainActor in
            if HomeTabState.shared.selectedTab != .home {
                HomeTabState.shared.selectedTab = .home
            }
            activateMainWindowOrOpenHomeSceneForCurrentProcess()
        }
    }

    static func openLogs() {
        Task { @MainActor in
            if HomeTabState.shared.selectedTab != .logs {
                HomeTabState.shared.selectedTab = .logs
            }
            activateMainWindowOrOpenHomeSceneForCurrentProcess()
        }
    }

    static func openSettings() {
        Task { @MainActor in
            if HomeTabState.shared.selectedTab != .settings {
                HomeTabState.shared.selectedTab = .settings
            }
            activateMainWindowOrOpenHomeSceneForCurrentProcess()
        }
    }

    @MainActor
    private static func activateMainWindowOrOpenHomeSceneForCurrentProcess() {
        if let activateMainWindowOrOpenHomeSceneOverride {
            activateMainWindowOrOpenHomeSceneOverride()
            return
        }
        activateMainWindowOrOpenHomeScene()
    }

    @MainActor
    static func activateMainWindowOrOpenHomeScene() {
        activateMainWindowOrOpenHomeScene(application: NSApp)
    }

    @MainActor
    static func activateMainWindowOrOpenHomeScene(application: any AppWindowOpeningApplication) {
        guard !application.appWindows.contains(where: {
            $0.isPanelWindow
                && $0.isVisible
                && $0.flowTabWindowIdentifier == switcherPanelWindowIdentifier
        }) else {
            return
        }
        application.activate(ignoringOtherApps: true)
        if application.isHidden {
            application.unhide(nil)
        }
        if let window = application.appWindows.first(where: { !$0.isPanelWindow }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        _ = application.sendShowSettingsWindowAction()
    }
}
