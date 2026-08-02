import AppKit
import SwiftUI
import FlowTabCore

@MainActor
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

@MainActor
protocol AppWindowOpeningApplication: AnyObject {
    var isHidden: Bool { get }
    var appWindows: [any AppWindowOpeningWindow] { get }

    func activate(ignoringOtherApps flag: Bool)
    func unhide(_ sender: Any?)
    func sendShowSettingsWindowAction() -> Bool
}

@MainActor
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
    typealias OpenOperation = Task<Void, Never>

    static let switcherPanelWindowIdentifier = "flowtab.window.switcher-panel"
    static let homeWindowIdentifier = "flowtab.window.home"

    @MainActor
    static var activateMainWindowOrOpenHomeSceneOverride: (() -> Void)?
    @MainActor
    private static var appKitHomeWindow: NSWindow?
    @MainActor
    private static var temporaryRegularActivationRestorationOwner:
        TemporaryRegularActivationRestorationOwner?
    @MainActor
    private static var temporaryRegularActivationGeneration: UInt64 = 0

    @discardableResult
    static func openHome() -> OpenOperation {
        open(.home)
    }

    @discardableResult
    static func openLogs() -> OpenOperation {
        open(.logs)
    }

    @discardableResult
    static func openSettings() -> OpenOperation {
        open(.settings)
    }

    private static func open(
        _ tab: HomeTab
    ) -> OpenOperation {
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

        if let window = application.appWindows.first(where: {
            !$0.isPanelWindow
                && $0.canBecomeKeyWindow
                && $0.isAppContentWindow
                && ($0.isVisible || $0.isMiniaturized)
                && $0.flowTabWindowLevel == .normal
        }) {
            prepareAndPresentWindow(
                application: application,
                window: window,
                didTemporarilyUseRegularActivation:
                    didTemporarilyUseRegularActivation,
                activationPolicyApplication: activationPolicyApplication
            )
            return window
        }
        if let nsApplication = application as? NSApplication {
            let window = appKitHomeWindowForPresentation()
            prepareAndPresentWindow(
                application: nsApplication,
                window: window,
                didTemporarilyUseRegularActivation:
                    didTemporarilyUseRegularActivation,
                activationPolicyApplication: activationPolicyApplication
            )
            return window
        }

        application.activate(ignoringOtherApps: true)
        if application.isHidden {
            application.unhide(nil)
        }
        _ = application.sendShowSettingsWindowAction()
        finishWindowlessTemporaryRegularActivationIfNeeded(
            didTemporarilyUseRegularActivation,
            activationPolicyApplication: activationPolicyApplication
        )
        return nil
    }

    @discardableResult
    @MainActor
    private static func appKitHomeWindowForPresentation() -> NSWindow {
        let window = appKitHomeWindow ?? makeAppKitHomeWindow()
        appKitHomeWindow = window
        return window
    }

    @MainActor
    private static func beginTemporaryRegularActivationIfNeeded(
        activationPolicyApplication: (any AppActivationPolicyApplying)?,
        temporarilyUseRegularActivation: Bool
    ) -> Bool {
        temporaryRegularActivationRestorationOwner?.cancel()
        temporaryRegularActivationRestorationOwner = nil
        guard temporarilyUseRegularActivation else { return false }
        guard let activationPolicyApplication else { return false }

        guard activationPolicyApplication.flowTabActivationPolicy != .regular else { return true }
        guard activationPolicyApplication.flowTabActivationPolicy == .accessory else { return false }

        activationPolicyApplication.setFlowTabActivationPolicy(.regular)
        RuntimeLog.info(.app, "activationPolicy=regular source=status_item_temporary_activation")
        return true
    }

    @MainActor
    private static func finishWindowlessTemporaryRegularActivationIfNeeded(
        _ didTemporarilyUseRegularActivation: Bool,
        activationPolicyApplication: (any AppActivationPolicyApplying)?
    ) {
        guard didTemporarilyUseRegularActivation else { return }
        guard let activationPolicyApplication else { return }
        restoreAccessoryActivationPolicy(
            activationPolicyApplication,
            reason: "status_item_no_regular_window"
        )
    }

    @MainActor
    private static func prepareAndPresentWindow(
        application: any AppWindowOpeningApplication,
        window: any AppWindowOpeningWindow,
        didTemporarilyUseRegularActivation: Bool,
        activationPolicyApplication:
            (any AppActivationPolicyApplying)?
    ) {
        guard
            didTemporarilyUseRegularActivation,
            let activationPolicyApplication
        else {
            presentWindow(application: application, window: window)
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
        temporaryRegularActivationRestorationOwner?.cancel()
        temporaryRegularActivationGeneration &+= 1
        let generation = temporaryRegularActivationGeneration
        let owner = TemporaryRegularActivationRestorationOwner(
            generation: generation,
            application: application,
            window: window,
            activationPolicyApplication: activationPolicyApplication
        )
        temporaryRegularActivationRestorationOwner = owner
        owner.start(
            requestPresentation: {
                presentWindow(application: application, window: window)
            },
            onOutcome: { outcome in
                handleTemporaryRegularActivationOutcome(
                    outcome,
                    generation: generation,
                    application: application,
                    window: window,
                    activationPolicyApplication:
                        activationPolicyApplication
                )
            }
        )
    }

    @MainActor
    private static func handleTemporaryRegularActivationOutcome(
        _ outcome: TemporaryRegularActivationRestorationOutcome,
        generation: UInt64,
        application: any AppWindowOpeningApplication,
        window: any AppWindowOpeningWindow,
        activationPolicyApplication: any AppActivationPolicyApplying
    ) {
        guard
            temporaryRegularActivationRestorationOwner?.generation
                == generation
        else {
            return
        }
        temporaryRegularActivationRestorationOwner = nil

        switch outcome {
        case let .stable(evidence):
            restoreAccessoryActivationPolicy(
                activationPolicyApplication,
                application: application,
                window: window,
                reactivatesWindow: true,
                reason: "status_item_window_stable",
                evidence: evidence
            )
        case let .windowUnavailable(evidence):
            restoreAccessoryActivationPolicy(
                activationPolicyApplication,
                reason: "status_item_window_unavailable",
                evidence: evidence
            )
        case let .watchdogExpired(evidence):
            restoreAccessoryActivationPolicy(
                activationPolicyApplication,
                reason: "status_item_window_stability_timeout",
                evidence: evidence
            )
        case .activationPolicyChanged:
            return
        }
    }

    @MainActor
    private static func restoreAccessoryActivationPolicy(
        _ activationPolicyApplication: any AppActivationPolicyApplying,
        application: (any AppWindowOpeningApplication)? = nil,
        window: (any AppWindowOpeningWindow)? = nil,
        reactivatesWindow: Bool = false,
        reason: String,
        evidence: TemporaryRegularActivationEvidence? = nil
    ) {
        guard activationPolicyApplication.flowTabActivationPolicy == .regular else { return }
        activationPolicyApplication.setFlowTabActivationPolicy(.accessory)
        let evidenceFields = evidence.map { " \($0.logFields)" } ?? ""
        RuntimeLog.info(
            .app,
            "activationPolicy=accessory source=\(reason)\(evidenceFields)"
        )
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
