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
final class TabSwitchStressPrewarmOwner {
    static let sharedSettlementNanoseconds: UInt64 =
        250_000_000
    static let sharedTargets: [TabSwitchStressTarget] = [
        .home,
        .logs,
        .settings,
        .home
    ]

    private let runner: any TabSwitchStressRunning
    private let scheduler: any TabSwitchStressScheduling
    private let selectTarget: TabSwitchStressRunner.Selection
    private let targets: [TabSwitchStressTarget]
    private let settlementNanoseconds: UInt64

    private var nextTargetIndex = 0
    private var wakeGeneration: UInt64 = 0
    private var wakeToken: (any TabSwitchStressCancellable)?
    private(set) var didComplete = false
    private(set) var isStarted = false

    init(
        runner: any TabSwitchStressRunning,
        scheduler: any TabSwitchStressScheduling,
        targets: [TabSwitchStressTarget] = sharedTargets,
        settlementNanoseconds: UInt64 =
            sharedSettlementNanoseconds,
        selectTarget:
            @escaping TabSwitchStressRunner.Selection
    ) {
        self.runner = runner
        self.scheduler = scheduler
        self.targets = targets
        self.settlementNanoseconds =
            settlementNanoseconds
        self.selectTarget = selectTarget
    }

    func start() {
        guard !isStarted, !didComplete else { return }
        isStarted = true
        scheduleNextStep()
    }

    func cancel() {
        wakeGeneration &+= 1
        wakeToken?.cancel()
        wakeToken = nil
        isStarted = false
    }

    deinit {
        wakeToken?.cancel()
    }

    private func scheduleNextStep() {
        wakeGeneration &+= 1
        let generation = wakeGeneration
        wakeToken = scheduler.schedule(
            afterNanoseconds: settlementNanoseconds
        ) { [weak self] in
            self?.advance(generation: generation)
        }
    }

    private func advance(generation: UInt64) {
        guard isStarted,
              !didComplete,
              generation == wakeGeneration
        else {
            return
        }
        wakeToken = nil

        guard nextTargetIndex < targets.count else {
            didComplete = true
            isStarted = false
            runner.startIfNeeded()
            return
        }

        _ = selectTarget(targets[nextTargetIndex])
        nextTargetIndex += 1
        scheduleNextStep()
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

    static func selectSharedTarget(
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
