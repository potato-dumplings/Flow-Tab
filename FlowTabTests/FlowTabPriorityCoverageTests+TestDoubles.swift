import AppKit
import Carbon
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

final class SpyHotkeyMonitor: HotkeyMonitoring {
    var onHotkeyPressed: ((Bool) -> Void)?
    var onHotkeyReleased: ((Bool) -> Void)?

    private(set) var stopCallCount = 0

    func stop() {
        stopCallCount += 1
    }
}

struct SpyHotkeyMonitorRecord {
    let configuration: SwitcherHotkeyConfiguration
    let signature: OSType
    let forwardHotkeyID: UInt32
    let backwardHotkeyID: UInt32
    let monitor: SpyHotkeyMonitor
}

final class SpyHotkeyMonitorFactory {
    private(set) var records: [SpyHotkeyMonitorRecord] = []

    func make(
        configuration: SwitcherHotkeyConfiguration,
        signature: OSType,
        forwardHotkeyID: UInt32,
        backwardHotkeyID: UInt32
    ) -> any HotkeyMonitoring {
        let monitor = SpyHotkeyMonitor()
        records.append(
            SpyHotkeyMonitorRecord(
                configuration: configuration,
                signature: signature,
                forwardHotkeyID: forwardHotkeyID,
                backwardHotkeyID: backwardHotkeyID,
                monitor: monitor
            )
        )
        return monitor
    }
}

final class SpyCommandTabTakeoverController: CommandTabTakeoverControlling {
    private(set) var reconcileCalls: [Bool] = []
    private(set) var restoreCallCount = 0
    var reconcileResult = true

    func reconcileIfNeeded(shouldTakeOver: Bool) -> Bool {
        reconcileCalls.append(shouldTakeOver)
        return reconcileResult
    }

    func restoreSystemShortcutsIfNeeded() {
        restoreCallCount += 1
    }
}

@MainActor
final class SpyStressRunner: TabSwitchStressRunning {
    private(set) var startCallCount = 0

    func startIfNeeded() {
        startCallCount += 1
    }
}

final class SpyMRUTracker: MRUTracking {
    private(set) var startCallCount = 0

    func startIfNeeded() {
        startCallCount += 1
    }
}

final class RecordingRuntimeSnapshotService: RuntimeSnapshotServing, @unchecked Sendable {
    private let lock = NSLock()
    private let homeSnapshotsByAppID: [String: RuntimeHomeAppSnapshot]
    private let focusedSnapshotsByPID: [pid_t: RuntimeHomeAppSnapshot]
    private var requestedHomeAppIDs: [String] = []
    private var requestedFocusedPIDs: [pid_t] = []
    private var snapshotRequests = 0
    private var spaceTopologyChangeSignals = 0

    init(
        homeSnapshotsByAppID: [String: RuntimeHomeAppSnapshot] = [:],
        focusedSnapshotsByPID: [pid_t: RuntimeHomeAppSnapshot] = [:]
    ) {
        self.homeSnapshotsByAppID = homeSnapshotsByAppID
        self.focusedSnapshotsByPID = focusedSnapshotsByPID
    }

    func recordedHomeAppIDs() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return requestedHomeAppIDs
    }

    func recordedFocusedPIDs() -> [pid_t] {
        lock.lock()
        defer { lock.unlock() }
        return requestedFocusedPIDs
    }

    func snapshotRequestCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return snapshotRequests
    }

    func spaceTopologyChangeSignalCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return spaceTopologyChangeSignals
    }

    func snapshot() -> RuntimeSnapshot {
        lock.lock()
        snapshotRequests += 1
        lock.unlock()
        return RuntimeSnapshot(apps: [], contextsByID: [:])
    }

    func lightweightAppSnapshot() -> RuntimeSnapshot {
        RuntimeSnapshot(apps: [], contextsByID: [:])
    }

    func homeAppSummaries() async -> [RuntimeHomeAppSummary] {
        homeSnapshotsByAppID.values.map(\.summary)
    }

    func homeAppSummary(for appID: String) async -> RuntimeHomeAppSummary? {
        homeSnapshotsByAppID[appID]?.summary
    }

    func homeAppSnapshot(for appID: String) async -> RuntimeHomeAppSnapshot? {
        homeAppSnapshotSynchronously(for: appID)
    }

    func homeAppSnapshotSynchronously(for appID: String) -> RuntimeHomeAppSnapshot? {
        lock.lock()
        requestedHomeAppIDs.append(appID)
        lock.unlock()
        return homeSnapshotsByAppID[appID]
    }

    func focusedAppSnapshot(processIdentifier pid: pid_t) -> RuntimeHomeAppSnapshot? {
        lock.lock()
        requestedFocusedPIDs.append(pid)
        lock.unlock()
        return focusedSnapshotsByPID[pid]
    }

    func currentCGWindowsByPID() -> [pid_t: [RuntimeSnapshotProvider.CGWindowEntry]] {
        [:]
    }

    func signalSpaceTopologyChanged() {
        lock.lock()
        spaceTopologyChangeSignals += 1
        lock.unlock()
    }

    func isLikelyTransientAXRebuild(for pid: pid_t) -> Bool {
        false
    }
}
