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
    private var appLaunchSignals: [(appID: String, pid: pid_t)] = []
    private var appWindowChangeSignals: [(appID: String, pid: pid_t)] = []
    private var appTerminationSignals: [(appID: String, pid: pid_t)] = []
    private var windowFocusVerifiedSignals: [(appID: String, pid: pid_t)] = []
    private var windowFocusVerificationSignals: [RuntimeWindowFocusVerification] = []

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

    func appLaunchSignalsRecorded() -> [(appID: String, pid: pid_t)] {
        lock.lock()
        defer { lock.unlock() }
        return appLaunchSignals
    }

    func appWindowChangeSignalsRecorded() -> [(appID: String, pid: pid_t)] {
        lock.lock()
        defer { lock.unlock() }
        return appWindowChangeSignals
    }

    func appTerminationSignalsRecorded() -> [(appID: String, pid: pid_t)] {
        lock.lock()
        defer { lock.unlock() }
        return appTerminationSignals
    }

    func windowFocusVerifiedSignalsRecorded() -> [(appID: String, pid: pid_t)] {
        lock.lock()
        defer { lock.unlock() }
        return windowFocusVerifiedSignals
    }

    func windowFocusVerificationSignalsRecorded() -> [RuntimeWindowFocusVerification] {
        lock.lock()
        defer { lock.unlock() }
        return windowFocusVerificationSignals
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

    func signalAppLaunched(appID: String, pid: pid_t) {
        lock.lock()
        appLaunchSignals.append((appID, pid))
        lock.unlock()
    }

    func signalAppWindowsChanged(appID: String, pid: pid_t) {
        lock.lock()
        appWindowChangeSignals.append((appID, pid))
        lock.unlock()
    }

    func signalAXWindowDestroyed(appID: String, pid: pid_t, axWindowID: String) {
        signalAppWindowsChanged(appID: appID, pid: pid)
    }

    func signalAppTerminated(appID: String, pid: pid_t) {
        lock.lock()
        appTerminationSignals.append((appID, pid))
        lock.unlock()
    }

    func signalWindowFocusVerified(appID: String, pid: pid_t) {
        signalWindowFocusVerified(
            RuntimeWindowFocusVerification(
                appID: appID,
                windowID: "",
                ownerPID: pid,
                targetCGWindowID: nil,
                focusedCGWindowID: nil,
                title: "",
                frame: nil,
                allowedActions: []
            )
        )
    }

    func signalWindowFocusVerified(_ verification: RuntimeWindowFocusVerification) {
        lock.lock()
        windowFocusVerifiedSignals.append((verification.appID, verification.ownerPID))
        windowFocusVerificationSignals.append(verification)
        lock.unlock()
    }

    func isLikelyTransientAXRebuild(for pid: pid_t) -> Bool {
        false
    }
}

struct FixedRuntimeCGWindowListProvider: RuntimeCGWindowListProviding {
    let rawWindowInfo: [[String: Any]]

    func windowInfo(
        options: CGWindowListOption,
        relativeToWindow windowID: CGWindowID
    ) -> [[String: Any]]? {
        rawWindowInfo
    }
}

struct FixedRuntimeSpaceTopologyProvider: RuntimeSpaceTopologyProviding {
    let snapshot: RuntimeSpaceTopologySnapshot

    func snapshot(for windowIDs: [CGWindowID]) -> RuntimeSpaceTopologySnapshot {
        snapshot
    }
}

func makeRawCGWindowInfo(
    pid: pid_t,
    windowID: CGWindowID,
    title: String,
    bounds: CGRect = CGRect(x: 10, y: 20, width: 640, height: 480),
    isOnscreen: Bool = true,
    layer: Int = 0
) -> [String: Any] {
    [
        kCGWindowOwnerPID as String: pid,
        kCGWindowLayer as String: layer,
        kCGWindowNumber as String: NSNumber(value: windowID),
        kCGWindowName as String: title,
        kCGWindowBounds as String: [
            "X": bounds.origin.x,
            "Y": bounds.origin.y,
            "Width": bounds.width,
            "Height": bounds.height
        ],
        kCGWindowIsOnscreen as String: NSNumber(value: isOnscreen),
        kCGWindowAlpha as String: NSNumber(value: 1.0),
        kCGWindowStoreType as String: NSNumber(value: 1)
    ]
}
