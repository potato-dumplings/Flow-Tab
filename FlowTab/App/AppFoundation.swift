import AppKit
import SwiftUI
import FlowTabCore

protocol AppWindowOpeningWindow: AnyObject {
    var isPanelWindow: Bool { get }
    var isMiniaturized: Bool { get }
    var isVisible: Bool { get }
    var canBecomeKeyWindow: Bool { get }
    var isAppContentWindow: Bool { get }
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

    var canBecomeKeyWindow: Bool {
        canBecomeKey
    }

    var isAppContentWindow: Bool {
        styleMask.contains(.titled)
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
    private static let temporaryRegularActivationPollIntervalNanoseconds: UInt64 = 20_000_000
    private static let temporaryRegularActivationMaximumPolls = 250

    @MainActor
    static var activateMainWindowOrOpenHomeSceneOverride: (() -> Void)?
    @MainActor
    private static var appKitHomeWindow: NSWindow?
    @MainActor
    private static var temporaryRegularActivationRestoreTask: Task<Void, Never>?

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

    @discardableResult
    @MainActor
    static func activateMainWindowOrOpenHomeScene(
        application: any AppWindowOpeningApplication,
        activationPolicyApplication: (any AppActivationPolicyApplying)? = nil,
        temporarilyUseRegularActivation: Bool = false
    ) -> (any AppWindowOpeningWindow)? {
        guard !application.appWindows.contains(where: {
            $0.isPanelWindow
                && $0.isVisible
                && $0.flowTabWindowIdentifier == switcherPanelWindowIdentifier
        }) else {
            return nil
        }

        let didTemporarilyUseRegularActivation = beginTemporaryRegularActivationIfNeeded(
            activationPolicyApplication: activationPolicyApplication,
            temporarilyUseRegularActivation: temporarilyUseRegularActivation
        )
        var openedWindow: (any AppWindowOpeningWindow)?
        defer {
            finishTemporaryRegularActivationIfNeeded(
                didTemporarilyUseRegularActivation,
                application: application,
                window: openedWindow,
                activationPolicyApplication: activationPolicyApplication
            )
        }

        if let window = application.appWindows.first(where: {
            !$0.isPanelWindow
                && $0.canBecomeKeyWindow
                && $0.isAppContentWindow
                && ($0.isVisible || $0.isMiniaturized)
                && $0.flowTabWindowLevel == .normal
        }) {
            presentWindow(application: application, window: window)
            openedWindow = window
            return openedWindow
        }
        if let nsApplication = application as? NSApplication {
            openedWindow = openAppKitHomeWindow(application: nsApplication)
        } else {
            application.activate(ignoringOtherApps: true)
            if application.isHidden {
                application.unhide(nil)
            }
            _ = application.sendShowSettingsWindowAction()
            openedWindow = nil
        }
        return openedWindow
    }

    @discardableResult
    @MainActor
    private static func openAppKitHomeWindow(application: NSApplication) -> NSWindow {
        let window = appKitHomeWindow ?? makeAppKitHomeWindow()
        appKitHomeWindow = window

        presentWindow(application: application, window: window)
        return window
    }

    @MainActor
    private static func beginTemporaryRegularActivationIfNeeded(
        activationPolicyApplication: (any AppActivationPolicyApplying)?,
        temporarilyUseRegularActivation: Bool
    ) -> Bool {
        guard temporarilyUseRegularActivation else { return false }
        guard let activationPolicyApplication else { return false }

        temporaryRegularActivationRestoreTask?.cancel()
        temporaryRegularActivationRestoreTask = nil
        guard activationPolicyApplication.flowTabActivationPolicy != .regular else { return true }
        guard activationPolicyApplication.flowTabActivationPolicy == .accessory else { return false }

        activationPolicyApplication.setFlowTabActivationPolicy(.regular)
        RuntimeLog.info(.app, "activationPolicy=regular source=status_item_temporary_activation")
        return true
    }

    @MainActor
    private static func finishTemporaryRegularActivationIfNeeded(
        _ didTemporarilyUseRegularActivation: Bool,
        application: any AppWindowOpeningApplication,
        window: (any AppWindowOpeningWindow)?,
        activationPolicyApplication: (any AppActivationPolicyApplying)?
    ) {
        guard didTemporarilyUseRegularActivation else { return }
        guard let activationPolicyApplication else { return }
        guard let window else {
            restoreAccessoryActivationPolicy(
                activationPolicyApplication,
                reason: "status_item_no_regular_window"
            )
            return
        }

        scheduleAccessoryPolicyRestoration(
            application: application,
            window: window,
            activationPolicyApplication: activationPolicyApplication
        )
    }

    @MainActor
    private static func scheduleAccessoryPolicyRestoration(
        application: any AppWindowOpeningApplication,
        window: any AppWindowOpeningWindow,
        activationPolicyApplication: any AppActivationPolicyApplying
    ) {
        temporaryRegularActivationRestoreTask?.cancel()
        temporaryRegularActivationRestoreTask = Task { @MainActor in
            var remainingPolls = temporaryRegularActivationMaximumPolls
            var hasObservedVisibleWindow = window.isVisible
            while !Task.isCancelled {
                guard activationPolicyApplication.flowTabActivationPolicy == .regular else { return }
                if regularWindowActivationIsStable(application: application, window: window) {
                    restoreAccessoryActivationPolicy(
                        activationPolicyApplication,
                        application: application,
                        window: window,
                        reactivatesWindow: true,
                        reason: "status_item_window_stable"
                    )
                    return
                }
                if window.isVisible {
                    hasObservedVisibleWindow = true
                    presentWindow(application: application, window: window)
                } else if hasObservedVisibleWindow && !window.isMiniaturized {
                    restoreAccessoryActivationPolicy(
                        activationPolicyApplication,
                        reason: "status_item_window_unavailable"
                    )
                    return
                } else {
                    presentWindow(application: application, window: window)
                }
                guard remainingPolls > 0 else {
                    restoreAccessoryActivationPolicy(
                        activationPolicyApplication,
                        reason: "status_item_window_stability_timeout"
                    )
                    return
                }
                remainingPolls -= 1
                try? await Task.sleep(nanoseconds: temporaryRegularActivationPollIntervalNanoseconds)
            }
        }
    }

    @MainActor
    private static func regularWindowActivationIsStable(
        application: any AppWindowOpeningApplication,
        window: any AppWindowOpeningWindow
    ) -> Bool {
        let applicationIsActive = (application as? NSApplication)?.isActive ?? true
        return applicationIsActive && window.isVisible
    }

    @MainActor
    private static func restoreAccessoryActivationPolicy(
        _ activationPolicyApplication: any AppActivationPolicyApplying,
        application: (any AppWindowOpeningApplication)? = nil,
        window: (any AppWindowOpeningWindow)? = nil,
        reactivatesWindow: Bool = false,
        reason: String
    ) {
        guard activationPolicyApplication.flowTabActivationPolicy == .regular else { return }
        activationPolicyApplication.setFlowTabActivationPolicy(.accessory)
        RuntimeLog.info(.app, "activationPolicy=accessory source=\(reason)")
        guard reactivatesWindow, let application, let window else { return }
        presentWindow(application: application, window: window)
    }

    @MainActor
    private static func presentWindow(
        application: any AppWindowOpeningApplication,
        window: any AppWindowOpeningWindow
    ) {
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
