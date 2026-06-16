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
    private let appSwitcherProjection: RuntimeAppSwitcherProjection?
    private let homeSummaryProjection: RuntimeHomeSummaryProjection?
    private let currentAppWindowProjectionsByAppID: [String: RuntimeCurrentAppWindowProjection]
    private var committedSearchIndexProjection: RuntimeSearchIndexProjection?
    private var requestedHomeAppIDs: [String] = []
    private var requestedFocusedPIDs: [pid_t] = []
    private var snapshotRequests = 0
    private var lightweightSnapshotRequests = 0
    private var homeSummaryRequests = 0
    private var homeSummariesRequests = 0
    private var appSwitcherMaintenanceRequests: [RuntimeProjectionMaintenanceReason] = []
    private var searchIndexFreshnessBarrierRequests: [RuntimeProjectionMaintenanceReason] = []
    private var spaceTopologyChangeSignals = 0
    private var appLaunchSignals: [(appID: String, pid: pid_t)] = []
    private var appWindowChangeSignals: [(appID: String, pid: pid_t)] = []
    private var appTerminationSignals: [(appID: String, pid: pid_t)] = []
    private var windowFocusVerifiedSignals: [(appID: String, pid: pid_t)] = []
    private var windowFocusVerificationSignals: [RuntimeWindowFocusVerification] = []

    init(
        homeSnapshotsByAppID: [String: RuntimeHomeAppSnapshot] = [:],
        focusedSnapshotsByPID: [pid_t: RuntimeHomeAppSnapshot] = [:],
        appSwitcherProjection: RuntimeAppSwitcherProjection? = nil,
        homeSummaryProjection: RuntimeHomeSummaryProjection? = nil,
        currentAppWindowProjectionsByAppID: [String: RuntimeCurrentAppWindowProjection] = [:],
        committedSearchIndexProjection: RuntimeSearchIndexProjection? = nil
    ) {
        self.homeSnapshotsByAppID = homeSnapshotsByAppID
        self.focusedSnapshotsByPID = focusedSnapshotsByPID
        self.appSwitcherProjection = appSwitcherProjection
        self.homeSummaryProjection = homeSummaryProjection
        self.currentAppWindowProjectionsByAppID = currentAppWindowProjectionsByAppID
        self.committedSearchIndexProjection = committedSearchIndexProjection
    }

    convenience init(
        appSwitcherApps apps: [AppSwitchCandidate],
        contextsByID: [String: RuntimeAppContext] = [:],
        committedSearchApps: [AppSwitchCandidate]? = nil,
        generatedAt: TimeInterval = 10
    ) {
        let freshness = RuntimeProjectionFreshness(
            generatedAt: generatedAt,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        self.init(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: apps,
                contextsByID: contextsByID,
                freshness: freshness
            ),
            committedSearchIndexProjection: Self.committedSearchIndexProjection(
                for: committedSearchApps ?? apps,
                generatedAt: generatedAt
            )
        )
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

    func lightweightSnapshotRequestCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return lightweightSnapshotRequests
    }

    func homeSummariesRequestCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return homeSummariesRequests
    }

    func homeSummaryRequestCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return homeSummaryRequests
    }

    func appSwitcherMaintenanceRequestsRecorded() -> [RuntimeProjectionMaintenanceReason] {
        lock.lock()
        defer { lock.unlock() }
        return appSwitcherMaintenanceRequests
    }

    func searchIndexFreshnessBarrierRequestsRecorded() -> [RuntimeProjectionMaintenanceReason] {
        lock.lock()
        defer { lock.unlock() }
        return searchIndexFreshnessBarrierRequests
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

    func installCommittedSearchIndex(
        for apps: [AppSwitchCandidate],
        generatedAt: TimeInterval = 10
    ) {
        lock.lock()
        committedSearchIndexProjection = Self.committedSearchIndexProjection(
            for: apps,
            generatedAt: generatedAt
        )
        lock.unlock()
    }

    func snapshot() -> RuntimeSnapshot {
        lock.lock()
        snapshotRequests += 1
        lock.unlock()
        return RuntimeSnapshot(apps: [], contextsByID: [:])
    }

    func lightweightAppSnapshot() -> RuntimeSnapshot {
        lock.lock()
        lightweightSnapshotRequests += 1
        lock.unlock()
        return RuntimeSnapshot(apps: [], contextsByID: [:])
    }

    func homeAppSummaries() async -> [RuntimeHomeAppSummary] {
        lock.lock()
        homeSummariesRequests += 1
        lock.unlock()
        return homeSnapshotsByAppID.values.map(\.summary)
    }

    func homeAppSummary(for appID: String) async -> RuntimeHomeAppSummary? {
        lock.lock()
        homeSummaryRequests += 1
        lock.unlock()
        return homeSnapshotsByAppID[appID]?.summary
    }

    func homeAppSnapshot(for appID: String) async -> RuntimeHomeAppSnapshot? {
        return homeAppSnapshotSynchronously(for: appID)
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

    func readAppSwitcherProjection() -> RuntimeAppSwitcherProjection? {
        return appSwitcherProjection
    }

    func readHomeSummaryProjection() -> RuntimeHomeSummaryProjection? {
        return homeSummaryProjection
    }

    func readCurrentAppWindowProjection(appID: String) -> RuntimeCurrentAppWindowProjection? {
        return currentAppWindowProjectionsByAppID[appID]
    }

    func readCommittedSearchIndexProjection() -> RuntimeSearchIndexProjection? {
        lock.lock()
        defer { lock.unlock() }
        return committedSearchIndexProjection
    }

    func readCommittedSearchIndexForSearch() -> RuntimeSearchIndexRead {
        lock.lock()
        defer { lock.unlock() }
        guard let projection = committedSearchIndexProjection else {
            return RuntimeSearchIndexRead(projection: nil, readiness: .missing)
        }
        return RuntimeSearchIndexRead(
            projection: projection,
            readiness: projection.freshness.isCompleteForScope ? .ready : .stale
        )
    }

    func runtimeReadModelDiagnostics() -> RuntimeReadModelDiagnostics {
        lock.lock()
        let hasCommittedSearchIndex = committedSearchIndexProjection != nil
        lock.unlock()
        return RuntimeReadModelDiagnostics(
            generation: RuntimeReadModelGeneration(),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            hasAppSwitcherProjection: false,
            hasHomeSummaryProjection: false,
            hasCommittedSearchIndex: hasCommittedSearchIndex,
            hasStagingSearchIndex: false,
            currentAppWindowProjectionAppIDs: []
        )
    }

    func requestAppSwitcherProjectionMaintenance(reason: RuntimeProjectionMaintenanceReason) {
        lock.lock()
        appSwitcherMaintenanceRequests.append(reason)
        lock.unlock()
    }

    func requestSearchIndexFreshnessBarrier(reason: RuntimeProjectionMaintenanceReason) {
        lock.lock()
        searchIndexFreshnessBarrierRequests.append(reason)
        lock.unlock()
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
                focusedAXWindow: nil,
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

    private static func committedSearchIndexProjection(
        for apps: [AppSwitchCandidate],
        generatedAt: TimeInterval
    ) -> RuntimeSearchIndexProjection {
        let store = RuntimeReadModelStore()
        store.commitAppSwitcherSnapshot(
            RuntimeSnapshot(apps: apps, contextsByID: [:]),
            generatedAt: generatedAt
        )
        return store.readCommittedSearchIndexProjection()!
    }
}

@MainActor
extension LiveSwitcherModel {
    func installSnapshotProviderOverrideForTesting(
        _ provider: @escaping () -> RuntimeSnapshot,
        committedSearchApps: [AppSwitchCandidate]? = nil
    ) {
        snapshotProviderOverride = provider
        guard let recordingService = runtimeSnapshotService as? RecordingRuntimeSnapshotService else {
            return
        }
        recordingService.installCommittedSearchIndex(
            for: committedSearchApps ?? provider().apps
        )
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
