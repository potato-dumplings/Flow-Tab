import AppKit
import Darwin

@MainActor
final class SpaceFixtureAppDelegate: NSObject, NSApplicationDelegate {
    private var windowCoordinator: SpaceFixtureWindowCoordinator?
    private var terminationDelayMilliseconds = 0
    private var isTerminationReplyPending = false
    private var terminationSignalSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApplication.shared.setActivationPolicy(.regular)

        let configuration: SpaceFixtureLaunchConfiguration
        do {
            configuration = try SpaceFixtureLaunchConfiguration.load(
                arguments: ProcessInfo.processInfo.arguments
            )
        } catch {
            fatalError("Failed to load FlowTabSpaceFixture launch configuration: \(error.localizedDescription)")
        }
        let coordinator = SpaceFixtureWindowCoordinator(configuration: configuration)
        coordinator.launch()
        windowCoordinator = coordinator
        terminationDelayMilliseconds = configuration.terminationDelayMilliseconds
        installDelayedTerminationSignalHandlerIfNeeded()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationDelayMilliseconds > 0 else { return .terminateNow }
        guard !isTerminationReplyPending else { return .terminateNow }

        isTerminationReplyPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(terminationDelayMilliseconds)) {
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func installDelayedTerminationSignalHandlerIfNeeded() {
        guard terminationDelayMilliseconds > 0 else { return }

        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            guard !self.isTerminationReplyPending else { return }
            self.isTerminationReplyPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(self.terminationDelayMilliseconds)) {
                NSApp.terminate(nil)
            }
        }
        source.resume()
        terminationSignalSource = source
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ app: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ app: NSApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        false
    }
}
