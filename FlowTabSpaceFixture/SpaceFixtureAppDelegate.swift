import AppKit
import Darwin

@MainActor
final class SpaceFixtureAppDelegate: NSObject, NSApplicationDelegate {
    private var windowCoordinator: SpaceFixtureWindowCoordinator?
    private var terminationFaultOwner:
        SpaceFixtureTerminationFaultOwner?
    private var terminationSignalSource: DispatchSourceSignal?
    private var allowsImmediateTerminationAfterSignalFault =
        false

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
        configurePublishedDockIcon(arguments: ProcessInfo.processInfo.arguments)
        let coordinator = SpaceFixtureWindowCoordinator(configuration: configuration)
        coordinator.launch()
        windowCoordinator = coordinator
        configureTerminationFaultIfNeeded(
            configuration: configuration
        )
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let terminationFaultOwner else {
            return .terminateNow
        }
        if allowsImmediateTerminationAfterSignalFault {
            allowsImmediateTerminationAfterSignalFault = false
            return .terminateNow
        }
        terminationFaultOwner.request(
            source: .applicationShouldTerminate
        ) { [weak sender] in
            sender?.reply(
                toApplicationShouldTerminate: true
            )
        }
        return .terminateLater
    }

    private func configureTerminationFaultIfNeeded(
        configuration: SpaceFixtureLaunchConfiguration
    ) {
        guard let policy = SpaceFixtureTerminationFaultPolicy(
            delayMilliseconds:
                configuration.terminationDelayMilliseconds
        ) else {
            return
        }
        guard let bundleIdentifier =
                Bundle.main.bundleIdentifier,
              !bundleIdentifier.isEmpty
        else {
            fatalError(
                "FlowTabSpaceFixture requires a bundle identifier."
            )
        }
        let identity = SpaceFixtureTerminationFaultIdentity(
            bundleIdentifier: bundleIdentifier,
            processIdentifier:
                ProcessInfo.processInfo.processIdentifier
        )
        let route =
            configuration.terminationFaultEvidenceRoute
        terminationFaultOwner =
            SpaceFixtureTerminationFaultOwner(
                policy: policy,
                identity: identity,
                evidencePublisher: { evidence in
                    SpaceFixtureTerminationFaultEvidenceTransport
                        .publish(
                            evidence,
                            route: route
                        )
                }
            )
        installTerminationSignalHandler()
    }

    private func installTerminationSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            self?.requestTerminationFromSignal()
        }
        source.resume()
        terminationSignalSource = source
    }

    private func requestTerminationFromSignal() {
        terminationFaultOwner?.request(
            source: .terminationSignal
        ) { [weak self] in
            guard let self else { return }
            allowsImmediateTerminationAfterSignalFault = true
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(
        _ notification: Notification
    ) {
        terminationFaultOwner?.cancel()
        terminationFaultOwner = nil
        terminationSignalSource?.setEventHandler {}
        terminationSignalSource?.cancel()
        terminationSignalSource = nil
        signal(SIGTERM, SIG_DFL)
        windowCoordinator?.cancel()
        windowCoordinator = nil
    }

    func application(_ app: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ app: NSApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        false
    }

    private func configurePublishedDockIcon(arguments: [String]) {
        let preferenceKey = "DockIconResourceName"
        let argument = "--dock-icon-resource-name"
        let defaults = UserDefaults.standard
        guard let argumentIndex = arguments.firstIndex(of: argument) else {
            defaults.removeObject(forKey: preferenceKey)
            defaults.synchronize()
            return
        }

        let resourceNameIndex = arguments.index(after: argumentIndex)
        guard resourceNameIndex < arguments.endIndex else {
            defaults.removeObject(forKey: preferenceKey)
            defaults.synchronize()
            return
        }

        let resourceName = arguments[resourceNameIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resourceName.isEmpty else {
            defaults.removeObject(forKey: preferenceKey)
            defaults.synchronize()
            return
        }

        defaults.set(resourceName, forKey: preferenceKey)
        defaults.synchronize()

        guard let resourceBoundary = Bundle.main.resourceURL else { return }
        let resourceURL = resourceBoundary.appendingPathComponent(resourceName).standardizedFileURL
        guard let image = NSImage(contentsOf: resourceURL) else { return }
        NSApplication.shared.applicationIconImage = image
    }
}
