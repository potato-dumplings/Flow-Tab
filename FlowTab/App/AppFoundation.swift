import AppKit
import SwiftUI
import FlowTabCore

protocol AppWindowOpeningWindow: AnyObject {
    var isPanelWindow: Bool { get }
    var isMiniaturized: Bool { get }
    var isVisible: Bool { get }
    var flowTabWindowLevel: NSWindow.Level { get }
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

protocol AppActivationPolicyApplying: AnyObject {
    var flowTabActivationPolicy: NSApplication.ActivationPolicy { get }

    func setFlowTabActivationPolicy(_ policy: NSApplication.ActivationPolicy)
}

protocol AppTerminationRequesting: AnyObject {
    func terminate(_ sender: Any?)
}

extension NSWindow: AppWindowOpeningWindow {
    var isPanelWindow: Bool {
        self is NSPanel
    }

    var flowTabWindowLevel: NSWindow.Level {
        level
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

extension NSApplication: AppActivationPolicyApplying {
    var flowTabActivationPolicy: NSApplication.ActivationPolicy {
        activationPolicy()
    }

    func setFlowTabActivationPolicy(_ policy: NSApplication.ActivationPolicy) {
        setActivationPolicy(policy)
    }
}

extension NSApplication: AppTerminationRequesting {}

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

enum AppWindowLayout {
    static let width: CGFloat = 1120
    static let height: CGFloat = 850
}

enum AppWindowCoordinator {
    static let switcherPanelWindowIdentifier = "flowtab.window.switcher-panel"
    static let homeWindowIdentifier = "flowtab.window.home"

    @MainActor
    static var activateMainWindowOrOpenHomeSceneOverride: (() -> Void)?
    @MainActor
    private static var appKitHomeWindow: NSWindow?

    static func openHome() {
        open(.home)
    }

    static func openLogs() {
        open(.logs)
    }

    static func openSettings() {
        open(.settings)
    }

    private static func open(_ tab: HomeTab) {
        Task { @MainActor in
            openInCurrentProcess(tab)
        }
    }

    @MainActor
    static func openHomeInCurrentProcess() {
        openInCurrentProcess(.home)
    }

    @MainActor
    private static func openInCurrentProcess(_ tab: HomeTab) {
        if HomeTabState.shared.selectedTab != tab {
            HomeTabState.shared.selectedTab = tab
        }
        activateMainWindowOrOpenHomeSceneForCurrentProcess()
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
        if let window = application.appWindows.first(where: {
            !$0.isPanelWindow
                && ($0.isVisible || $0.isMiniaturized)
                && $0.flowTabWindowLevel == .normal
        }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        if let nsApplication = application as? NSApplication {
            openAppKitHomeWindow(application: nsApplication)
        } else {
            _ = application.sendShowSettingsWindowAction()
        }
    }

    @MainActor
    private static func openAppKitHomeWindow(application: NSApplication) {
        let window = appKitHomeWindow ?? makeAppKitHomeWindow()
        appKitHomeWindow = window

        application.activate(ignoringOtherApps: true)
        if application.isHidden {
            application.unhide(nil)
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    @MainActor
    private static func makeAppKitHomeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: AppWindowLayout.width,
                height: AppWindowLayout.height
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "FlowTab"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.identifier = NSUserInterfaceItemIdentifier(homeWindowIdentifier)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: HomeRootView()
                .frame(minWidth: AppWindowLayout.width, minHeight: AppWindowLayout.height)
        )
        window.center()
        return window
    }
}
