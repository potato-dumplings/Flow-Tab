import AppKit

@MainActor
final class AppKitSpaceFixtureWindow: SpaceFixtureWindowing {
    let plan: SpaceFixtureWindowPlan

    private let contentView: SpaceFixtureWindowContentView
    private let window: ChromeLikeSpaceFixtureWindow
    private let noisyCGSiblings: NoisyCGSiblingWindowSet?

    var applicationAccessibilityElement: Any {
        window
    }

    init(plan: SpaceFixtureWindowPlan) {
        self.plan = plan
        let contentView = SpaceFixtureWindowContentView(plan: plan)

        let window = ChromeLikeSpaceFixtureWindow(
            contentRect: plan.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = plan.title
        window.identifier = NSUserInterfaceItemIdentifier(plan.windowAccessibilityIdentifier)
        window.isRestorable = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.setAccessibilityElement(true)
        window.setFrame(plan.frame, display: false)
        window.contentView = contentView

        self.contentView = contentView
        self.window = window
        self.noisyCGSiblings = plan.noisyCGSiblings ? NoisyCGSiblingWindowSet(plan: plan) : nil
    }

    func show(isKey: Bool) {
        if isKey {
            window.makeKeyAndOrderFront(nil)
            return
        }
        window.orderFrontRegardless()
    }

    func enterFullScreen() {
        suppressNoisyFullScreenContentAccessibilityIfNeeded()
        showNoisyCGSiblingsIfNeeded()
        window.toggleFullScreen(nil)
        showNoisyCGSiblingsIfNeeded(after: 2.5)
    }

    func updateWorkflowReadiness(windowTitles: [String]) {
        contentView.updateWorkflowReadiness(windowTitles: windowTitles)
    }

    private func showNoisyCGSiblingsIfNeeded(after delay: TimeInterval = 0) {
        guard let noisyCGSiblings else { return }
        let action = { [weak self] in
            guard let self else { return }
            noisyCGSiblings.show(around: self.window)
        }
        guard delay > 0 else {
            action()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { @MainActor in
                action()
            }
        }
    }

    private func suppressNoisyFullScreenContentAccessibilityIfNeeded() {
        guard plan.noisyCGSiblings, plan.isFullscreenTarget else { return }
        window.suppressAccessibilityExposure()
    }

}

@MainActor
private final class ChromeLikeSpaceFixtureWindow: NSWindow {
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
private final class NoisyCGSiblingWindowSet {
    private enum ChromeLikeLayout {
        static let titlebarHeight: CGFloat = 37
        static let toolbarHeight: CGFloat = 41
        static let tabStripHeight: CGFloat = 80
        static let chromeStackHeight = titlebarHeight + toolbarHeight + tabStripHeight
    }

    private struct Spec {
        let suffix: String
        let title: String?
        let height: CGFloat
        let insetFromTop: CGFloat
        let horizontalInset: CGFloat
        let usesTitledWindow: Bool
        let exposesAccessibilityElement: Bool
        let ignoresCycle: Bool
    }

    private let plan: SpaceFixtureWindowPlan
    private var windows: [NSWindow] = []

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

    private func makeWindows(around hostWindow: NSWindow) -> [NSWindow] {
        noisySiblingSpecs().map { spec in
            let window = NSWindow(
                contentRect: frame(for: spec, hostFrame: hostWindow.frame),
                styleMask: spec.usesTitledWindow ? [.titled] : [.borderless],
                backing: .buffered,
                defer: false
            )
            window.title = spec.title ?? ""
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
        let height = min(spec.height, max(80, normalizedHostFrame.height / 4))
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
                usesTitledWindow: false,
                exposesAccessibilityElement: true,
                ignoresCycle: true
            ),
            Spec(
                suffix: "toolbar",
                title: appNameTitle,
                height: ChromeLikeLayout.toolbarHeight,
                insetFromTop: ChromeLikeLayout.titlebarHeight,
                horizontalInset: 0,
                usesTitledWindow: false,
                exposesAccessibilityElement: true,
                ignoresCycle: true
            ),
            Spec(
                suffix: "omnibox",
                title: appNameTitle,
                height: ChromeLikeLayout.tabStripHeight,
                insetFromTop: ChromeLikeLayout.titlebarHeight + ChromeLikeLayout.toolbarHeight,
                horizontalInset: 0,
                usesTitledWindow: false,
                exposesAccessibilityElement: true,
                ignoresCycle: true
            ),
            Spec(
                suffix: "content-wrapper",
                title: appNameTitle,
                height: 165,
                insetFromTop: ChromeLikeLayout.titlebarHeight,
                horizontalInset: 0,
                usesTitledWindow: true,
                exposesAccessibilityElement: true,
                ignoresCycle: false
            ),
            Spec(
                suffix: "content-plane",
                title: appNameTitle,
                height: 520,
                insetFromTop: ChromeLikeLayout.chromeStackHeight,
                horizontalInset: 0,
                usesTitledWindow: true,
                exposesAccessibilityElement: true,
                ignoresCycle: false
            ),
            Spec(
                suffix: "preview-overlay",
                title: nil,
                height: 418,
                insetFromTop: 63,
                horizontalInset: 96,
                usesTitledWindow: false,
                exposesAccessibilityElement: false,
                ignoresCycle: true
            ),
            Spec(
                suffix: "floating-strip",
                title: nil,
                height: 80,
                insetFromTop: 202,
                horizontalInset: 160,
                usesTitledWindow: false,
                exposesAccessibilityElement: false,
                ignoresCycle: true
            )
        ]
    }
}
