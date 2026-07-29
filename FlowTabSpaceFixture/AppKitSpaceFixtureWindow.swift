import AppKit

@MainActor
final class AppKitSpaceFixtureWindow: SpaceFixtureWindowing {
    let plan: SpaceFixtureWindowPlan

    private let contentView: SpaceFixtureWindowContentView
    private let window: NSWindow & FixtureAccessibilitySuppressing
    private let noisyCGSiblings: NoisyCGSiblingWindowSet?
    private var fullScreenObservation:
        SpaceFixtureFullScreenObservation?

    var applicationAccessibilityElement: Any {
        window
    }

    init(plan: SpaceFixtureWindowPlan) {
        self.plan = plan
        let contentView = SpaceFixtureWindowContentView(plan: plan)

        let window = Self.makeWindow(for: plan)
        window.title = plan.title
        window.identifier = NSUserInterfaceItemIdentifier(plan.windowAccessibilityIdentifier)
        window.isRestorable = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.setAccessibilityElement(true)
        window.setFrame(plan.frame, display: false)
        window.contentView = contentView
        if plan.suppressesWindowAccessibilityExposure {
            window.suppressAccessibilityExposure()
        }

        self.contentView = contentView
        self.window = window
        self.noisyCGSiblings = plan.noisyCGSiblings ? NoisyCGSiblingWindowSet(plan: plan) : nil
    }

    private static func makeWindow(for plan: SpaceFixtureWindowPlan) -> NSWindow & FixtureAccessibilitySuppressing {
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        switch plan.kind {
        case .standard:
            return ChromeLikeSpaceFixtureWindow(
                contentRect: plan.frame,
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
        case .panel:
            let panel = ChromeLikeSpaceFixturePanel(
                contentRect: plan.frame,
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            return panel
        }
    }

    func show(isKey: Bool) {
        if isKey {
            window.makeKeyAndOrderFront(nil)
            applyStartupStateIfNeeded()
            return
        }
        window.orderFrontRegardless()
        applyStartupStateIfNeeded()
    }

    func close() {
        fullScreenObservation?.cancel()
        fullScreenObservation = nil
        noisyCGSiblings?.close()
        window.close()
    }

    func enterFullScreen(
        completion: @escaping @MainActor () -> Void
    ) -> any SpaceFixtureCancellable {
        suppressNoisyFullScreenContentAccessibilityIfNeeded()
        fullScreenObservation?.cancel()
        let observation = SpaceFixtureFullScreenObservation(
            window: window
        ) { [weak self] in
            guard let self else { return }
            self.fullScreenObservation = nil
            self.showNoisyCGSiblingsIfNeeded()
            completion()
        }
        fullScreenObservation = observation
        if window.styleMask.contains(.fullScreen) {
            observation.completeFromInitialReadback()
            return observation
        }
        window.toggleFullScreen(nil)
        return observation
    }

    func updateWorkflowReadiness(windowTitles: [String]) {
        contentView.updateWorkflowReadiness(windowTitles: windowTitles)
        noisyCGSiblings?.updateWorkflowReadiness(windowTitles: windowTitles)
    }

    private func showNoisyCGSiblingsIfNeeded() {
        guard let noisyCGSiblings else { return }
        noisyCGSiblings.show(around: window)
    }

    private func applyStartupStateIfNeeded() {
        guard plan.startupState == .minimized else { return }
        window.miniaturize(nil)
    }

    private func suppressNoisyFullScreenContentAccessibilityIfNeeded() {
        guard plan.noisyCGSiblings, plan.isFullscreenTarget else { return }
        window.suppressAccessibilityExposure()
    }

}

@MainActor
private final class SpaceFixtureFullScreenObservation:
    SpaceFixtureCancellable
{
    private var notificationToken: NSObjectProtocol?
    private var completion: (@MainActor () -> Void)?

    init(
        window: NSWindow,
        completion: @escaping @MainActor () -> Void
    ) {
        self.completion = completion
        notificationToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.finish()
            }
        }
    }

    func cancel() {
        removeObserver()
        completion = nil
    }

    func completeFromInitialReadback() {
        finish()
    }

    private func finish() {
        guard let completion else { return }
        removeObserver()
        self.completion = nil
        completion()
    }

    private func removeObserver() {
        guard let notificationToken else { return }
        NotificationCenter.default.removeObserver(
            notificationToken
        )
        self.notificationToken = nil
    }

    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(
                notificationToken
            )
        }
    }
}

@MainActor
private protocol FixtureAccessibilitySuppressing: AnyObject {
    func suppressAccessibilityExposure()
}

@MainActor
private final class ChromeLikeSpaceFixtureWindow: NSWindow, FixtureAccessibilitySuppressing {
    private var suppressesAccessibilityExposure = false

    func suppressAccessibilityExposure() {
        suppressesAccessibilityExposure = true
        setAccessibilityElement(false)
        setAccessibilityChildren([])
        setAccessibilityWindows([])
    }

    override func isAccessibilityElement() -> Bool {
        suppressesAccessibilityExposure ? false : super.isAccessibilityElement()
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        suppressesAccessibilityExposure ? nil : super.accessibilityRole()
    }

    override func accessibilitySubrole() -> NSAccessibility.Subrole? {
        suppressesAccessibilityExposure ? nil : super.accessibilitySubrole()
    }

    override func accessibilityChildren() -> [Any]? {
        suppressesAccessibilityExposure ? [] : super.accessibilityChildren()
    }
}

@MainActor
private final class ChromeLikeSpaceFixturePanel: NSPanel, FixtureAccessibilitySuppressing {
    private var suppressesAccessibilityExposure = false

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    func suppressAccessibilityExposure() {
        suppressesAccessibilityExposure = true
        setAccessibilityElement(false)
        setAccessibilityChildren([])
        setAccessibilityWindows([])
    }

    override func isAccessibilityElement() -> Bool {
        suppressesAccessibilityExposure ? false : super.isAccessibilityElement()
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        suppressesAccessibilityExposure ? nil : super.accessibilityRole()
    }

    override func accessibilitySubrole() -> NSAccessibility.Subrole? {
        suppressesAccessibilityExposure ? nil : super.accessibilitySubrole()
    }

    override func accessibilityChildren() -> [Any]? {
        suppressesAccessibilityExposure ? [] : super.accessibilityChildren()
    }
}

@MainActor
private final class NoisyCGSiblingWindowSet {
    private enum ChromeLikeLayout {
        static let titlebarHeight: CGFloat = 37
        static let toolbarHeight: CGFloat = 41
        static let tabStripHeight: CGFloat = 80
        static let chromeStackHeight = titlebarHeight + toolbarHeight + tabStripHeight
        static let contentPlaneTopInset: CGFloat = 72
    }

    private struct Spec {
        let suffix: String
        let title: String?
        let height: CGFloat
        let insetFromTop: CGFloat
        let horizontalInset: CGFloat
        let fillsRemainingHeight: Bool
        let usesTitledWindow: Bool
        let exposesAccessibilityElement: Bool
        let ignoresCycle: Bool
        let rendersFixtureContent: Bool
    }

    private let plan: SpaceFixtureWindowPlan
    private var windows: [NSWindow] = []
    private var contentViews: [SpaceFixtureWindowContentView] = []
    private var currentWorkflowWindowTitles: [String] = []

    init(plan: SpaceFixtureWindowPlan) {
        self.plan = plan
    }

    func show(around hostWindow: NSWindow) {
        if windows.isEmpty {
            windows = makeWindows(around: hostWindow)
        }
        repositionWindows(around: hostWindow)
        for window in windows {
            window.orderFrontRegardless()
        }
    }

    func updateWorkflowReadiness(windowTitles: [String]) {
        currentWorkflowWindowTitles = windowTitles
        for contentView in contentViews {
            contentView.updateWorkflowReadiness(windowTitles: windowTitles)
        }
    }

    func close() {
        for window in windows {
            window.close()
        }
        windows.removeAll()
        contentViews.removeAll()
    }

    private func makeWindows(around hostWindow: NSWindow) -> [NSWindow] {
        contentViews = []
        return noisySiblingSpecs().map { spec in
            let window = NoisyCGSiblingWindow(
                contentRect: frame(for: spec, hostFrame: hostWindow.frame),
                styleMask: spec.usesTitledWindow ? [.titled] : [.borderless],
                backing: .buffered,
                defer: false,
                exposesAccessibilityElement: spec.exposesAccessibilityElement,
                accessibilityTitle: spec.title
            )
            window.title = spec.title ?? ""
            if let title = spec.title {
                window.setAccessibilityTitle(title)
            }
            window.titleVisibility = spec.title == nil ? .hidden : .visible
            window.titlebarAppearsTransparent = true
            window.identifier = NSUserInterfaceItemIdentifier(
                "\(plan.windowAccessibilityIdentifier).noisy-cg-sibling.\(spec.suffix)"
            )
            window.collectionBehavior = spec.ignoresCycle
                ? [.fullScreenAuxiliary, .ignoresCycle]
                : [.fullScreenAuxiliary]
            window.backgroundColor = .windowBackgroundColor
            window.isOpaque = true
            window.alphaValue = 1
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.canHide = false
            window.setAccessibilityElement(spec.exposesAccessibilityElement)
            if spec.rendersFixtureContent {
                let contentView = SpaceFixtureWindowContentView(
                    plan: plan,
                    contentTopInset: ChromeLikeLayout.contentPlaneTopInset
                )
                if !currentWorkflowWindowTitles.isEmpty {
                    contentView.updateWorkflowReadiness(windowTitles: currentWorkflowWindowTitles)
                }
                window.contentView = contentView
                contentViews.append(contentView)
            }
            return window
        }
    }

    private func repositionWindows(around hostWindow: NSWindow) {
        for (window, spec) in zip(windows, noisySiblingSpecs()) {
            window.setFrame(frame(for: spec, hostFrame: hostWindow.frame), display: true)
        }
    }

    private func frame(for spec: Spec, hostFrame: CGRect) -> CGRect {
        let normalizedHostFrame = hostFrame.standardized
        let height = spec.fillsRemainingHeight
            ? max(80, normalizedHostFrame.height - spec.insetFromTop)
            : min(spec.height, max(80, normalizedHostFrame.height / 4))
        return CGRect(
            x: normalizedHostFrame.minX + spec.horizontalInset,
            y: normalizedHostFrame.maxY - spec.insetFromTop - height,
            width: max(80, normalizedHostFrame.width - (spec.horizontalInset * 2)),
            height: height
        )
    }

    private func noisySiblingSpecs() -> [Spec] {
        let appNameTitle = plan.fixtureAppName ?? plan.title
        return [
            Spec(
                suffix: "titlebar",
                title: appNameTitle,
                height: ChromeLikeLayout.titlebarHeight,
                insetFromTop: 0,
                horizontalInset: 0,
                fillsRemainingHeight: false,
                usesTitledWindow: false,
                exposesAccessibilityElement: false,
                ignoresCycle: true,
                rendersFixtureContent: false
            ),
            Spec(
                suffix: "toolbar",
                title: appNameTitle,
                height: ChromeLikeLayout.toolbarHeight,
                insetFromTop: ChromeLikeLayout.titlebarHeight,
                horizontalInset: 0,
                fillsRemainingHeight: false,
                usesTitledWindow: false,
                exposesAccessibilityElement: false,
                ignoresCycle: true,
                rendersFixtureContent: false
            ),
            Spec(
                suffix: "omnibox",
                title: appNameTitle,
                height: ChromeLikeLayout.tabStripHeight,
                insetFromTop: ChromeLikeLayout.titlebarHeight + ChromeLikeLayout.toolbarHeight,
                horizontalInset: 0,
                fillsRemainingHeight: false,
                usesTitledWindow: false,
                exposesAccessibilityElement: false,
                ignoresCycle: true,
                rendersFixtureContent: false
            ),
            Spec(
                suffix: "content-plane",
                title: plan.title,
                height: 0,
                insetFromTop: ChromeLikeLayout.chromeStackHeight,
                horizontalInset: 0,
                fillsRemainingHeight: true,
                usesTitledWindow: true,
                exposesAccessibilityElement: true,
                ignoresCycle: false,
                rendersFixtureContent: true
            ),
            Spec(
                suffix: "content-wrapper",
                title: plan.title,
                height: 165,
                insetFromTop: ChromeLikeLayout.titlebarHeight,
                horizontalInset: 0,
                fillsRemainingHeight: false,
                usesTitledWindow: false,
                exposesAccessibilityElement: false,
                ignoresCycle: false,
                rendersFixtureContent: false
            ),
            Spec(
                suffix: "preview-overlay",
                title: nil,
                height: 418,
                insetFromTop: 63,
                horizontalInset: 96,
                fillsRemainingHeight: false,
                usesTitledWindow: false,
                exposesAccessibilityElement: false,
                ignoresCycle: true,
                rendersFixtureContent: false
            ),
            Spec(
                suffix: "floating-strip",
                title: nil,
                height: 80,
                insetFromTop: 202,
                horizontalInset: 160,
                fillsRemainingHeight: false,
                usesTitledWindow: false,
                exposesAccessibilityElement: false,
                ignoresCycle: true,
                rendersFixtureContent: false
            )
        ]
    }
}

@MainActor
private final class NoisyCGSiblingWindow: NSWindow {
    private let exposesAccessibilityElementFlag: Bool
    private let accessibilityTitleOverride: String?

    init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool,
        exposesAccessibilityElement: Bool,
        accessibilityTitle: String?
    ) {
        self.exposesAccessibilityElementFlag = exposesAccessibilityElement
        self.accessibilityTitleOverride = accessibilityTitle
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
    }

    override func isAccessibilityElement() -> Bool {
        exposesAccessibilityElementFlag ? super.isAccessibilityElement() : false
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        exposesAccessibilityElementFlag ? super.accessibilityRole() : nil
    }

    override func accessibilitySubrole() -> NSAccessibility.Subrole? {
        exposesAccessibilityElementFlag ? super.accessibilitySubrole() : nil
    }

    override func accessibilityTitle() -> String? {
        accessibilityTitleOverride ?? super.accessibilityTitle()
    }

    override func accessibilityChildren() -> [Any]? {
        exposesAccessibilityElementFlag ? super.accessibilityChildren() : []
    }
}
