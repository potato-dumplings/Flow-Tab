import AppKit
import Foundation

final class SystemAppMRUTracker {
    static let shared = SystemAppMRUTracker(stateStore: SystemAppMRUFileStateStore())

    private let lock = NSLock()
    private let stateStore: (any SystemAppMRUStatePersisting)?
    private var state: SystemAppMRUState
    private var hasStarted = false
    private var observers: [NSObjectProtocol] = []

    init(stateStore: (any SystemAppMRUStatePersisting)? = nil) {
        self.stateStore = stateStore

        guard let stateStore else {
            state = SystemAppMRUState()
            return
        }

        do {
            let snapshot = try stateStore.load()
            state = SystemAppMRUState(snapshot: snapshot)
            if let snapshot, snapshot.hasSupportedSchema {
                RuntimeLog.info(
                    .recency,
                    "systemAppMRU event=load generation=\(snapshot.generation) apps=\(snapshot.orderedAppIDs.count) hash=\(snapshot.orderFingerprint)"
                )
            } else if let snapshot {
                RuntimeLog.warning(
                    .recency,
                    "systemAppMRU event=recovery reason=unsupported_schema schema=\(snapshot.schemaVersion)"
                )
            }
        } catch {
            state = SystemAppMRUState()
            RuntimeLog.warning(
                .recency,
                "systemAppMRU event=recovery reason=load_failed error=\(String(describing: error))"
            )
        }
    }

    deinit {
        stopObserving()
    }

    func startIfNeeded() {
        if Thread.isMainThread {
            startOnMainThreadIfNeeded()
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.startOnMainThreadIfNeeded()
        }
    }

    func requiresBootstrapFallback() -> Bool {
        startIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        return state.requiresBootstrapFallback
    }

    func rankByPID(
        for runningApps: [NSRunningApplication],
        fallbackRankByPID: [pid_t: Int]
    ) -> [pid_t: Int] {
        startIfNeeded()

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let runningApplications = runningApps.map { app in
            SystemAppMRURunningApplication(
                appID: RuntimeAppIdentity.appID(for: app),
                pid: app.processIdentifier,
                launchDate: app.launchDate,
                isCurrentProcess: app.processIdentifier == currentPID
            )
        }
        let frontmostAppID: String? = if Thread.isMainThread,
            let frontmostApp = NSWorkspace.shared.frontmostApplication,
            frontmostApp.processIdentifier != currentPID {
            RuntimeAppIdentity.appID(for: frontmostApp)
        } else {
            nil
        }

        lock.lock()
        defer { lock.unlock() }
        if let source = state.prepareForRanking(
            runningApplications: runningApplications,
            frontmostAppID: frontmostAppID,
            fallbackRankByPID: fallbackRankByPID
        ) {
            persistLocked(source: source)
        }
        return state.rankByPID(for: runningApplications)
    }

    static func rankByPID(
        runningPIDs: [pid_t],
        trackedOrder: [pid_t],
        currentPID: pid_t,
        launchRankByPID: [pid_t: Int],
        fallbackRankByPID: [pid_t: Int]
    ) -> [pid_t: Int] {
        var rankByPID: [pid_t: Int] = [:]
        rankByPID.reserveCapacity(runningPIDs.count)

        var nextRank = 0
        for pid in trackedOrder where runningPIDs.contains(pid) && rankByPID[pid] == nil {
            rankByPID[pid] = nextRank
            nextRank += 1
        }

        let fallbackPIDs = runningPIDs
            .filter { rankByPID[$0] == nil }
            .sorted { lhs, rhs in
                let lhsRank = fallbackRank(
                    for: lhs,
                    currentPID: currentPID,
                    launchRankByPID: launchRankByPID,
                    fallbackRankByPID: fallbackRankByPID
                )
                let rhsRank = fallbackRank(
                    for: rhs,
                    currentPID: currentPID,
                    launchRankByPID: launchRankByPID,
                    fallbackRankByPID: fallbackRankByPID
                )
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs < rhs
            }

        for pid in fallbackPIDs {
            rankByPID[pid] = nextRank
            nextRank += 1
        }

        return rankByPID
    }

    func handleApplicationNotification(_ notification: Notification, removeOnly: Bool) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else {
            return
        }
        if removeOnly {
            recordTermination(of: app)
        } else {
            recordActivation(of: app)
        }
    }

    func recordActivation(of pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        let appID = NSRunningApplication(processIdentifier: pid)
            .map(RuntimeAppIdentity.appID(for:))
            ?? "pid:\(pid)"
        recordActivation(appID: appID, isCurrentProcess: false)
    }

    func remove(pid: pid_t) {
        let appID = NSRunningApplication(processIdentifier: pid)
            .map(RuntimeAppIdentity.appID(for:))
            ?? "pid:\(pid)"
        mutateState { state in
            state.recordTermination(
                appID: appID,
                isCurrentProcess: pid == ProcessInfo.processInfo.processIdentifier,
                hasRemainingProcess: false
            )
        }
    }

    func trackedMRUOrder(for runningPIDs: Set<pid_t>) -> [pid_t] {
        let appIDByPID = Dictionary(uniqueKeysWithValues: runningPIDs.map { pid in
            let appID = NSRunningApplication(processIdentifier: pid)
                .map(RuntimeAppIdentity.appID(for:))
                ?? "pid:\(pid)"
            return (pid, appID)
        })

        lock.lock()
        defer { lock.unlock() }
        let rankByAppID = Dictionary(
            uniqueKeysWithValues: state.orderedAppIDs.enumerated().map { ($0.element, $0.offset) }
        )
        return runningPIDs
            .filter { rankByAppID[appIDByPID[$0] ?? ""] != nil }
            .sorted { lhs, rhs in
                let lhsRank = rankByAppID[appIDByPID[lhs] ?? ""] ?? Int.max
                let rhsRank = rankByAppID[appIDByPID[rhs] ?? ""] ?? Int.max
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs < rhs
            }
    }

    func trackedAppIDOrder() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return state.orderedAppIDs
    }

    func recordActivation(appID: String, isCurrentProcess: Bool = false) {
        mutateState { state in
            state.recordActivation(appID: appID, isCurrentProcess: isCurrentProcess)
        }
    }

    private func startOnMainThreadIfNeeded() {
        lock.lock()
        if hasStarted {
            lock.unlock()
            return
        }
        hasStarted = true
        lock.unlock()

        let notificationCenter = NSWorkspace.shared.notificationCenter
        let didLaunchObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleLaunchNotification(notification)
        }
        let didActivateObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleApplicationNotification(notification, removeOnly: false)
        }
        let didTerminateObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleApplicationNotification(notification, removeOnly: true)
        }

        lock.lock()
        observers.append(contentsOf: [didLaunchObserver, didActivateObserver, didTerminateObserver])
        lock.unlock()

        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            recordActivation(of: frontmostApp)
        }
    }

    private func handleLaunchNotification(_ notification: Notification) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else {
            return
        }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let appID = RuntimeAppIdentity.appID(for: app)
        mutateState { state in
            state.recordLaunch(
                appID: appID,
                isCurrentProcess: app.processIdentifier == currentPID
            )
        }
    }

    private func recordActivation(of app: NSRunningApplication) {
        recordActivation(
            appID: RuntimeAppIdentity.appID(for: app),
            isCurrentProcess: app.processIdentifier == ProcessInfo.processInfo.processIdentifier
        )
    }

    private func recordTermination(of app: NSRunningApplication) {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let appID = RuntimeAppIdentity.appID(for: app)
        let hasRemainingProcess = NSWorkspace.shared.runningApplications.contains { candidate in
            candidate.processIdentifier != app.processIdentifier
                && !candidate.isTerminated
                && RuntimeAppIdentity.appID(for: candidate) == appID
        }
        mutateState { state in
            state.recordTermination(
                appID: appID,
                isCurrentProcess: app.processIdentifier == currentPID,
                hasRemainingProcess: hasRemainingProcess
            )
        }
    }

    private func mutateState(
        _ mutation: (inout SystemAppMRUState) -> SystemAppMRUMutationSource?
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard let source = mutation(&state) else { return }
        persistLocked(source: source)
    }

    private func persistLocked(source: SystemAppMRUMutationSource) {
        guard let stateStore else { return }
        let snapshot = state.snapshot(source: source)
        do {
            try stateStore.save(snapshot)
            RuntimeLog.info(
                .recency,
                "systemAppMRU event=\(source.rawValue) generation=\(snapshot.generation) apps=\(snapshot.orderedAppIDs.count) hash=\(snapshot.orderFingerprint)"
            )
        } catch {
            RuntimeLog.warning(
                .recency,
                "systemAppMRU event=persist_failed source=\(source.rawValue) generation=\(snapshot.generation) error=\(String(describing: error))"
            )
        }
    }

    private static func fallbackRank(
        for pid: pid_t,
        currentPID: pid_t,
        launchRankByPID: [pid_t: Int],
        fallbackRankByPID: [pid_t: Int]
    ) -> Int {
        if pid == currentPID {
            return launchRankByPID[pid] ?? Int.max
        }
        return fallbackRankByPID[pid] ?? Int.max
    }

    private func stopObserving() {
        lock.lock()
        hasStarted = false
        let existingObservers = observers
        observers.removeAll()
        lock.unlock()

        let notificationCenter = NSWorkspace.shared.notificationCenter
        for observer in existingObservers {
            notificationCenter.removeObserver(observer)
        }
    }
}
