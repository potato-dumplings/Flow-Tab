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

final class RecordingRuntimeProjectionService: RuntimeProjectionServing, @unchecked Sendable {
    private let lock = NSLock()
    private var appSwitcherProjection: RuntimeAppSwitcherProjection?
    private let homeSummaryProjection: RuntimeHomeSummaryProjection?
    private let homeDetailProjectionsByAppID: [String: RuntimeHomeAppDetailProjection]
    private let currentAppWindowProjectionsByAppID: [String: RuntimeCurrentAppWindowProjection]
    private var committedSearchIndexRead: RuntimeSearchIndexRead?
    private var appSwitcherProjectionReads = 0
    private var homeSummaryProjectionReads = 0
    private var homeDetailProjectionReadsByAppID: [String: Int] = [:]
    private var currentAppWindowProjectionReadsByAppID: [String: Int] = [:]
    private var committedSearchIndexReads = 0
    private var appSwitcherMaintenanceRequests: [RuntimeProjectionMaintenanceReason] = []
    private var searchIndexFreshnessBarrierRequests: [RuntimeProjectionMaintenanceReason] = []
    private var spaceTopologyChangeSignals = 0
    private var appLaunchSignals: [
        (appID: String, pid: pid_t, appDirectoryEntry: RuntimeAppDirectoryEntry?)
    ] = []
    private var appWindowChangeSignals: [(appID: String, pid: pid_t)] = []
    private var selectedCurrentAppWindowChangeSignals: [(appID: String, pid: pid_t)] = []
    private var appTerminationSignals: [(appID: String, pid: pid_t)] = []
    private var windowFocusVerifiedSignals: [(appID: String, pid: pid_t)] = []
    private var windowFocusVerificationSignals: [RuntimeWindowFocusVerification] = []

    init(
        appSwitcherProjection: RuntimeAppSwitcherProjection? = nil,
        homeSummaryProjection: RuntimeHomeSummaryProjection? = nil,
        homeDetailProjectionsByAppID: [String: RuntimeHomeAppDetailProjection]? = nil,
        currentAppWindowProjectionsByAppID: [String: RuntimeCurrentAppWindowProjection] = [:],
        committedSearchIndexRead: RuntimeSearchIndexRead? = nil
    ) {
        self.appSwitcherProjection = appSwitcherProjection
        self.homeSummaryProjection = homeSummaryProjection
        self.homeDetailProjectionsByAppID = homeDetailProjectionsByAppID
            ?? Self.homeDetailProjections(
                appSwitcherProjection: appSwitcherProjection,
                currentAppWindowProjectionsByAppID: currentAppWindowProjectionsByAppID
            )
        self.currentAppWindowProjectionsByAppID = currentAppWindowProjectionsByAppID
        self.committedSearchIndexRead = committedSearchIndexRead
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
            spaceTopologySignatureSummary: nil,
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        self.init(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: apps,
                contextsByID: contextsByID,
                freshness: freshness
            ),
            committedSearchIndexRead: RuntimeSearchIndexRead(
                projection: Self.committedSearchIndexProjection(
                    for: committedSearchApps ?? apps,
                    generatedAt: generatedAt
                ),
                readiness: .committedGenerationValidated
            )
        )
    }

    func appSwitcherProjectionReadCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return appSwitcherProjectionReads
    }

    func homeSummaryProjectionReadCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return homeSummaryProjectionReads
    }

    func homeDetailProjectionReadCount(appID: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return homeDetailProjectionReadsByAppID[appID] ?? 0
    }

    func currentAppWindowProjectionReadCount(appID: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return currentAppWindowProjectionReadsByAppID[appID] ?? 0
    }

    func committedSearchIndexReadCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return committedSearchIndexReads
    }

    func installAppSwitcherProjection(
        apps: [AppSwitchCandidate],
        contextsByID: [String: RuntimeAppContext] = [:],
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
        lock.lock()
        defer { lock.unlock() }
        appSwitcherProjection = RuntimeAppSwitcherProjection(
            apps: apps,
            contextsByID: contextsByID,
            freshness: freshness
        )
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

    func appLaunchSignalsRecorded() -> [
        (appID: String, pid: pid_t, appDirectoryEntry: RuntimeAppDirectoryEntry?)
    ] {
        lock.lock()
        defer { lock.unlock() }
        return appLaunchSignals
    }

    func appWindowChangeSignalsRecorded() -> [(appID: String, pid: pid_t)] {
        lock.lock()
        defer { lock.unlock() }
        return appWindowChangeSignals
    }

    func selectedCurrentAppWindowChangeSignalsRecorded() -> [(appID: String, pid: pid_t)] {
        lock.lock()
        defer { lock.unlock() }
        return selectedCurrentAppWindowChangeSignals
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
        committedSearchIndexRead = RuntimeSearchIndexRead(
            projection: Self.committedSearchIndexProjection(
                for: apps,
                generatedAt: generatedAt
            ),
            readiness: .committedGenerationValidated
        )
        lock.unlock()
    }

    func readAppSwitcherProjection() -> RuntimeAppSwitcherProjection? {
        lock.lock()
        defer { lock.unlock() }
        appSwitcherProjectionReads += 1
        return appSwitcherProjection
    }

    func readHomeSummaryProjection() -> RuntimeHomeSummaryProjection? {
        lock.lock()
        homeSummaryProjectionReads += 1
        lock.unlock()
        return homeSummaryProjection
    }

    func readHomeAppDetailProjection(appID: String) -> RuntimeHomeAppDetailProjection? {
        lock.lock()
        homeDetailProjectionReadsByAppID[appID, default: 0] += 1
        lock.unlock()
        return homeDetailProjectionsByAppID[appID]
    }

    func readCurrentAppWindowProjection(appID: String) -> RuntimeCurrentAppWindowProjection? {
        lock.lock()
        currentAppWindowProjectionReadsByAppID[appID, default: 0] += 1
        lock.unlock()
        return currentAppWindowProjectionsByAppID[appID]
    }

    func readCommittedSearchIndexForSearch() -> RuntimeSearchIndexRead {
        lock.lock()
        defer { lock.unlock() }
        committedSearchIndexReads += 1
        guard let committedSearchIndexRead else {
            return RuntimeSearchIndexRead(projection: nil, readiness: .missingCommittedIndex)
        }
        return committedSearchIndexRead
    }

    func runtimeReadModelDiagnostics() -> RuntimeReadModelDiagnostics {
        lock.lock()
        let hasCommittedSearchIndex = committedSearchIndexRead?.projection != nil
        lock.unlock()
        return RuntimeReadModelDiagnostics(
            generation: RuntimeReadModelGeneration(),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            spaceTopologySignatureSummary: nil,
            pendingRepairScopes: [],
            hasAppSwitcherProjection: false,
            hasHomeSummaryProjection: false,
            hasAppDirectoryProjection: false,
            hasCommittedSearchIndex: hasCommittedSearchIndex,
            hasStagingSearchIndex: false,
            currentAppWindowProjectionAppIDs: [],
            appDirectoryEntryPIDs: []
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

    func signalSpaceTopologyChanged() {
        lock.lock()
        spaceTopologyChangeSignals += 1
        lock.unlock()
    }

    func signalAppLaunched(
        appID: String,
        pid: pid_t,
        appDirectoryEntry: RuntimeAppDirectoryEntry?
    ) {
        lock.lock()
        appLaunchSignals.append((appID, pid, appDirectoryEntry))
        lock.unlock()
    }

    func signalAppWindowsChanged(appID: String, pid: pid_t) {
        lock.lock()
        appWindowChangeSignals.append((appID, pid))
        lock.unlock()
    }

    func signalSelectedCurrentAppWindowsChanged(appID: String, pid: pid_t) {
        lock.lock()
        selectedCurrentAppWindowChangeSignals.append((appID, pid))
        lock.unlock()
    }

    func signalAXWindowDestroyed(appID: String, pid: pid_t, axWindowID: String) {
        signalAppWindowsChanged(appID: appID, pid: pid)
    }

    func signalAppTerminated(appID: String, pid: pid_t) {
        lock.lock()
        appTerminationSignals.append((appID, pid))
        guard shouldRemoveTerminatedApp(appID: appID, pid: pid) else {
            lock.unlock()
            return
        }
        if let projection = appSwitcherProjection {
            appSwitcherProjection = RuntimeAppSwitcherProjection(
                apps: projection.apps.filter { $0.id != appID },
                contextsByID: projection.contextsByID.filter { $0.key != appID },
                freshness: projection.freshness
            )
        }
        if let searchIndexRead = committedSearchIndexRead,
           let projection = searchIndexRead.projection {
            committedSearchIndexRead = RuntimeSearchIndexRead(
                projection: projection.removingApp(
                    appID,
                    freshness: projection.freshness
                ),
                readiness: searchIndexRead.readiness
            )
        }
        lock.unlock()
    }

    private func shouldRemoveTerminatedApp(appID: String, pid: pid_t) -> Bool {
        var knownPIDs = Set<pid_t>()
        if let context = appSwitcherProjection?.contextsByID[appID] {
            knownPIDs.insert(context.runningApp.processIdentifier)
        }
        if let context = currentAppWindowProjectionsByAppID[appID]?.currentAppWindowPayload.context {
            knownPIDs.insert(context.runningApp.processIdentifier)
        }
        if let summary = homeSummaryProjection?.summary(for: appID) {
            knownPIDs.insert(summary.pid)
        }
        return knownPIDs.isEmpty || knownPIDs.contains(pid)
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

    private static func committedSearchIndexProjection(
        for apps: [AppSwitchCandidate],
        generatedAt: TimeInterval
    ) -> RuntimeSearchIndexProjection {
        let store = RuntimeReadModelStore()
        store.commitAppSwitcherProjection(
            apps: apps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: generatedAt
        )
        return store.readCommittedSearchIndexForSearch().projection!
    }

    private static func homeDetailProjections(
        appSwitcherProjection: RuntimeAppSwitcherProjection?,
        currentAppWindowProjectionsByAppID: [String: RuntimeCurrentAppWindowProjection]
    ) -> [String: RuntimeHomeAppDetailProjection] {
        var projections = Dictionary(
            uniqueKeysWithValues: currentAppWindowProjectionsByAppID.map { appID, projection in
                (
                    appID,
                    RuntimeHomeAppDetailProjection(
                        currentAppWindowPayload: projection.currentAppWindowPayload
                    )
                )
            }
        )
        guard let appSwitcherProjection else { return projections }
        for app in appSwitcherProjection.apps where projections[app.id] == nil {
            guard let context = appSwitcherProjection.contextsByID[app.id] else { continue }
            projections[app.id] = RuntimeHomeAppDetailProjection(
                summary: RuntimeHomeAppSummary(
                    appID: app.id,
                    displayName: app.displayName,
                    groupID: app.groupID,
                    lastActiveAt: app.lastActiveAt,
                    windowCount: app.windows.count,
                    pid: context.runningApp.processIdentifier
                ),
                candidate: app,
                context: context
            )
        }
        return projections
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
