import AppKit
import Foundation

final class SystemAppMRUTracker {
    static let shared = SystemAppMRUTracker()

    private let lock = NSLock()
    private var hasStarted = false
    private var observers: [NSObjectProtocol] = []
    private var mruPIDs: [pid_t] = []

    private init() {}

    func startIfNeeded() {
        if Thread.isMainThread {
            startOnMainThreadIfNeeded()
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.startOnMainThreadIfNeeded()
        }
    }

    func rankByPID(
        for runningApps: [NSRunningApplication],
        fallbackRankByPID: [pid_t: Int]
    ) -> [pid_t: Int] {
        startIfNeeded()

        let runningPIDs = Set(runningApps.map(\.processIdentifier))
        let trackedOrder = trackedMRUOrder(for: runningPIDs)
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return Self.rankByPID(
            runningPIDs: runningApps.map(\.processIdentifier),
            trackedOrder: trackedOrder,
            currentPID: currentPID,
            launchRankByPID: Self.launchRankByPID(for: runningApps),
            fallbackRankByPID: fallbackRankByPID
        )
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

    private func startOnMainThreadIfNeeded() {
        lock.lock()
        if hasStarted {
            lock.unlock()
            return
        }
        hasStarted = true
        lock.unlock()

        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter

        let didActivateObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleApplicationNotification(notification, removeOnly: false)
        }

        let didTerminateObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleApplicationNotification(notification, removeOnly: true)
        }

        lock.lock()
        observers.append(contentsOf: [didActivateObserver, didTerminateObserver])
        lock.unlock()

        if let frontmost = NSWorkspace.shared.frontmostApplication {
            recordActivation(of: frontmost.processIdentifier)
        }
    }

    private func handleApplicationNotification(_ notification: Notification, removeOnly: Bool) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else {
            return
        }
        if removeOnly {
            remove(pid: app.processIdentifier)
            return
        }
        recordActivation(of: app.processIdentifier)
    }

    private func recordActivation(of pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        lock.lock()
        defer { lock.unlock() }
        mruPIDs.removeAll { $0 == pid }
        mruPIDs.insert(pid, at: 0)
    }

    private func remove(pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        mruPIDs.removeAll { $0 == pid }
    }

    private func trackedMRUOrder(for runningPIDs: Set<pid_t>) -> [pid_t] {
        lock.lock()
        defer { lock.unlock() }
        mruPIDs.removeAll { !runningPIDs.contains($0) }
        return mruPIDs
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

    private static func launchRankByPID(for runningApps: [NSRunningApplication]) -> [pid_t: Int] {
        let sorted = runningApps.sorted { lhs, rhs in
            let lhsLaunchDate = lhs.launchDate ?? Date.distantPast
            let rhsLaunchDate = rhs.launchDate ?? Date.distantPast
            if lhsLaunchDate != rhsLaunchDate {
                return lhsLaunchDate > rhsLaunchDate
            }
            return lhs.processIdentifier < rhs.processIdentifier
        }

        var rankByPID: [pid_t: Int] = [:]
        rankByPID.reserveCapacity(sorted.count)
        for (rank, app) in sorted.enumerated() {
            rankByPID[app.processIdentifier] = rank
        }
        return rankByPID
    }

    func resetStateForTesting() {
        lock.lock()
        hasStarted = false
        mruPIDs.removeAll()
        let existingObservers = observers
        observers.removeAll()
        lock.unlock()

        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        for observer in existingObservers {
            workspaceNotificationCenter.removeObserver(observer)
        }
    }

    func recordActivationForTesting(pid: pid_t) {
        recordActivation(of: pid)
    }

    func removeForTesting(pid: pid_t) {
        remove(pid: pid)
    }

    func trackedMRUOrderForTesting(runningPIDs: [pid_t]) -> [pid_t] {
        trackedMRUOrder(for: Set(runningPIDs))
    }

    func handleApplicationNotificationForTesting(
        app: NSRunningApplication?,
        removeOnly: Bool
    ) {
        let name =
            removeOnly
            ? NSWorkspace.didTerminateApplicationNotification
            : NSWorkspace.didActivateApplicationNotification
        let userInfo: [AnyHashable: Any]? = app.map {
            [NSWorkspace.applicationUserInfoKey: $0]
        }
        let notification = Notification(name: name, object: nil, userInfo: userInfo)
        handleApplicationNotification(notification, removeOnly: removeOnly)
    }
}
