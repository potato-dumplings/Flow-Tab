#if FLOWTAB_TESTING
import AppKit
import Foundation

@MainActor
final class TabSwitchStressStartCommandOwner {
    private let notificationName: Notification.Name
    private let runner: any TabSwitchStressRunning
    private let center: DistributedNotificationCenter
    private var token: NSObjectProtocol?
    private(set) var didReceiveStartCommand = false

    init(
        notificationName: Notification.Name,
        runner: any TabSwitchStressRunning,
        center: DistributedNotificationCenter = .default()
    ) {
        self.notificationName = notificationName
        self.runner = runner
        self.center = center
    }

    func start() {
        guard token == nil, !didReceiveStartCommand else { return }
        token = center.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.receiveStartCommand()
            }
        }
    }

    func receiveStartCommand() {
        guard !didReceiveStartCommand else { return }
        didReceiveStartCommand = true
        cancel()
        runner.startIfNeeded()
    }

    func cancel() {
        guard let token else { return }
        center.removeObserver(token)
        self.token = nil
    }

    deinit {
        if let token {
            center.removeObserver(token)
        }
    }
}

@MainActor
extension TabSwitchStressRunner {
    static func makeShared()
        -> TabSwitchStressRunner
    {
        TabSwitchStressRunner(
            policyProvider: {
                guard FlowTabTestLaunchOptions
                        .runsTabSwitchStressTest
                else {
                    return nil
                }
                return .launchPolicy
            },
            clock:
                TabSwitchStressSystemMonotonicClock(),
            scheduler:
                TabSwitchStressTaskScheduler(),
            selectTarget: selectSharedTarget,
            terminate: {
                Task { @MainActor in
                    _ = await RuntimeDiagnostics.shared
                        .makeReadSnapshot()
                    NSApp.terminate(nil)
                }
            },
            onEvidence: reportSharedEvidence
        )
    }

    private static func selectSharedTarget(
        _ target: TabSwitchStressTarget
    ) -> TabSwitchStressTarget? {
        switch target {
        case .home:
            HomeTabState.shared.selectedTab = .home
        case .logs:
            HomeTabState.shared.selectedTab = .logs
        case .settings:
            HomeTabState.shared.selectedTab = .settings
        }

        switch HomeTabState.shared.selectedTab {
        case .home:
            return .home
        case .logs:
            return .logs
        case .settings:
            return .settings
        }
    }

    private static func reportSharedEvidence(
        _ evidence: TabSwitchStressEvidence
    ) {
        let selectionMatched =
            evidence.requestedTarget
                == evidence.observedTarget
        guard evidence.phase
                != .selectionObserved
                || !selectionMatched
        else {
            return
        }
        let runtimeLogLevel =
            RuntimeLogPreferencesStore.loadMinimumLevel().rawValue
        let line =
            "FlowTabTabSwitchStressEvidence "
            + evidence.logFields
            + " runtimeLogLevel=\(runtimeLogLevel)"
        TabSwitchStressEvidenceTransport.publish(
            evidence
        )
        RuntimeLog.info(.uiTest, line)
        guard let data = "\(line)\n".data(
            using: .utf8
        ) else {
            return
        }
        FileHandle.standardOutput.write(data)
    }
}
#endif
