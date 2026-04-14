import AppKit

@MainActor
final class SpaceFixtureAppDelegate: NSObject, NSApplicationDelegate {
    private var windowCoordinator: SpaceFixtureWindowCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApplication.shared.setActivationPolicy(.regular)

        let configuration = SpaceFixtureLaunchConfiguration(
            arguments: ProcessInfo.processInfo.arguments
        )
        let coordinator = SpaceFixtureWindowCoordinator(configuration: configuration)
        coordinator.launch()
        windowCoordinator = coordinator
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
