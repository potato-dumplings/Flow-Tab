import AppKit
import Foundation

final class SystemAppMRUTracker {
    static let shared: SystemAppMRUTracker = {
        do {
            try SystemAppMRULegacyPersistence.removePersistedState()
        } catch {
            RuntimeLog.warning(
                .recency,
                "systemAppMRU event=legacy_cleanup_failed error=\(String(describing: error))"
            )
        }
        return SystemAppMRUTracker()
    }()

    private let lock = NSLock()
    private var state = SystemAppMRUState()
    private var hasStarted = false
    private var observers: [NSObjectProtocol] = []

    init() {}

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
        fallbackRankByPID: [pid_t: Int],
        systemOrderedPIDs: [pid_t]? = nil
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
        let appIDByPID = Dictionary(
            uniqueKeysWithValues: runningApplications.map { ($0.pid, $0.appID) }
        )
        let systemOrderedAppIDs = systemOrderedPIDs?.compactMap { appIDByPID[$0] }
        let frontmostAppID: String? = if systemOrderedAppIDs == nil,
            Thread.isMainThread,
            let frontmostApp = NSWorkspace.shared.frontmostApplication,
            frontmostApp.processIdentifier != currentPID {
            RuntimeAppIdentity.appID(for: frontmostApp)
        } else {
            nil
        }

        lock.lock()
        defer { lock.unlock() }
        let mutationSource = if let systemOrderedAppIDs {
            state.reconcileSystemOrder(
                systemOrderedAppIDs,
                runningApplications: runningApplications
            )
        } else {
            state.prepareForRanking(
                runningApplications: runningApplications,
                frontmostAppID: frontmostAppID,
                fallbackRankByPID: fallbackRankByPID
            )
        }
        if let source = mutationSource {
            logMutationLocked(source: source)
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
        logMutationLocked(source: source)
    }

    private func logMutationLocked(source: SystemAppMRUMutationSource) {
        RuntimeLog.info(
            .recency,
            "systemAppMRU event=\(source.rawValue) generation=\(state.generation) apps=\(state.orderedAppIDs.count) hash=\(state.orderFingerprint)"
        )
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
