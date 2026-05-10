import AppKit

@MainActor
final class AppKitSpaceFixtureWindow: SpaceFixtureWindowing {
    let plan: SpaceFixtureWindowPlan

    private let contentView: SpaceFixtureWindowContentView
    private let window: NSWindow
    private let noisyCGSiblings: NoisyCGSiblingWindowSet?

    var applicationAccessibilityElement: Any {
        window
    }

    init(plan: SpaceFixtureWindowPlan) {
        self.plan = plan
        let contentView = SpaceFixtureWindowContentView(plan: plan)

        let window = NSWindow(
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

}

@MainActor
private final class NoisyCGSiblingWindowSet {
    private struct Spec {
        let suffix: String
        let height: CGFloat
        let insetFromTop: CGFloat
        let horizontalInset: CGFloat
        let exposesAccessibilityElement: Bool
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
                styleMask: spec.exposesAccessibilityElement ? [.titled] : [.borderless],
                backing: .buffered,
                defer: false
            )
            window.title = ""
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.identifier = NSUserInterfaceItemIdentifier(
                "\(plan.windowAccessibilityIdentifier).noisy-cg-sibling.\(spec.suffix)"
            )
            window.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
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
        [
            Spec(
                suffix: "titlebar",
                height: 37,
                insetFromTop: 0,
                horizontalInset: 0,
                exposesAccessibilityElement: false
            ),
            Spec(
                suffix: "toolbar",
                height: 41,
                insetFromTop: 37,
                horizontalInset: 0,
                exposesAccessibilityElement: false
            ),
            Spec(
                suffix: "omnibox",
                height: 80,
                insetFromTop: 78,
                horizontalInset: 0,
                exposesAccessibilityElement: false
            ),
            Spec(
                suffix: "content-wrapper",
                height: 165,
                insetFromTop: 37,
                horizontalInset: 0,
                exposesAccessibilityElement: true
            ),
            Spec(
                suffix: "content-plane",
                height: 520,
                insetFromTop: 158,
                horizontalInset: 0,
                exposesAccessibilityElement: false
            ),
            Spec(
                suffix: "preview-overlay",
                height: 418,
                insetFromTop: 63,
                horizontalInset: 96,
                exposesAccessibilityElement: false
            ),
            Spec(
                suffix: "floating-strip",
                height: 80,
                insetFromTop: 202,
                horizontalInset: 160,
                exposesAccessibilityElement: false
            )
        ]
    }
}
