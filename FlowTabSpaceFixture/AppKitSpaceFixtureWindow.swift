import AppKit

@MainActor
final class AppKitSpaceFixtureWindow: SpaceFixtureWindowing {
    let plan: SpaceFixtureWindowPlan

    private let window: NSWindow

    init(plan: SpaceFixtureWindowPlan) {
        self.plan = plan

        let window = NSWindow(
            contentRect: plan.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = plan.title
        window.identifier = NSUserInterfaceItemIdentifier(plan.windowAccessibilityIdentifier)
        window.collectionBehavior = [.fullScreenPrimary]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.setFrame(plan.frame, display: false)
        window.contentView = SpaceFixtureWindowContentView(plan: plan)

        self.window = window
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
    }
}
