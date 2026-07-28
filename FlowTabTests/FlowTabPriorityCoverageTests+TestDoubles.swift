import AppKit
import Carbon
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

func makeRuntimeSearchIndexPayloadForTesting(
    apps: [AppSwitchCandidate],
    hasCompleteWindowCoverage: Bool = true
) -> RuntimeSearchIndexPayload {
    let appEntries = apps.map { app in
        RuntimeSearchAppIndexEntry(
            appID: app.id,
            appDisplayName: app.displayName,
            appGroupID: app.groupID,
            appLastActiveAt: app.lastActiveAt,
            searchIndex: SearchTextMatcher.buildIndex(for: app.displayName, identifier: app.id)
        )
    }
    let appSearchIndexes = Dictionary(uniqueKeysWithValues: appEntries.map { ($0.appID, $0.searchIndex) })
    let windowEntries = apps.flatMap { app -> [RuntimeSearchWindowIndexEntry] in
        let appSearchIndex = appSearchIndexes[app.id]
            ?? SearchTextMatcher.buildIndex(for: app.displayName, identifier: app.id)
        return app.windows.map { window in
            RuntimeSearchWindowIndexEntry(
                appID: app.id,
                appDisplayName: app.displayName,
                windowID: window.id,
                windowTitle: window.title.trimmingCharacters(in: .whitespacesAndNewlines),
                windowIsMinimized: window.isMinimized,
                windowLastActiveAt: window.lastActiveAt,
                windowSearchIndex: SearchTextMatcher.buildIndex(for: window.title),
                appSearchIndex: appSearchIndex
            )
        }
    }
    return RuntimeSearchIndexPayload(
        appEntries: appEntries,
        windowEntries: windowEntries,
        hasCompleteWindowCoverage: hasCompleteWindowCoverage
    )
}

final class SpyHotkeyMonitor: HotkeyMonitoring {
    let inputSourceID = HotkeyInputSourceID()
    var onHotkeyEvent: ((HotkeyInputEvent) -> Void)?

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private var inputSequence: UInt64 = 0

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    @discardableResult
    func emit(
        phase: HotkeyInputEvent.Phase,
        isBackward: Bool
    ) -> HotkeyInputEvent {
        inputSequence &+= 1
        let event = HotkeyInputEvent(
            identity: HotkeyInputEventIdentity(
                sourceID: inputSourceID,
                sequence: inputSequence
            ),
            phase: phase,
            isBackward: isBackward
        )
        onHotkeyEvent?(event)
        return event
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
    private var homeSummaryProjection: RuntimeHomeSummaryProjection?
    private var homeDetailProjectionsByAppID: [String: RuntimeHomeAppDetailProjection]
    private var currentAppWindowProjectionsByAppID: [String: RuntimeCurrentAppWindowProjection]
    private let focusedCurrentAppWindowProjectionRead: RuntimeFocusedCurrentAppWindowProjectionRead?
    private let activationTargetProjection: RuntimeActivationTargetProjection?
    private let spaceTopologyProjection: RuntimeSpaceTopologyProjection?
    private var committedSearchIndexRead: RuntimeSearchIndexRead?
    private var appSwitcherProjectionReads = 0
    private var homeSummaryProjectionReads = 0
    private var homeDetailProjectionReadsByAppID: [String: Int] = [:]
    private var currentAppWindowProjectionReadsByAppID: [String: Int] = [:]
    private var focusedCurrentAppWindowProjectionReads = 0
    private var spaceTopologyProjectionReads = 0
    private var committedSearchIndexReads = 0
    private var appSwitcherMaintenanceRequests: [RuntimeProjectionMaintenanceReason] = []
    private var appSwitcherMaintenanceRequestHandler:
        ((RuntimeProjectionMaintenanceReason) -> Void)?
    private var searchIndexFreshnessBarrierRequests: [RuntimeProjectionMaintenanceReason] = []
    private var spaceTopologyChangeSignals = 0
    private var appLaunchSignals: [
        (appID: String, pid: pid_t, appDirectoryEntry: RuntimeAppDirectoryEntry?)
    ] = []
    private var appWindowChangeSignals: [(appID: String, pid: pid_t)] = []
    private var selectedCurrentAppWindowChangeSignals: [(appID: String, pid: pid_t)] = []
    private var selectedCurrentAppWindowChangeSignalHandler:
        ((String, pid_t) -> Void)?
    private var appTerminationSignals: [(appID: String, pid: pid_t)] = []
    private var windowFocusVerifiedSignals: [(appID: String, pid: pid_t)] = []
    private var windowFocusVerificationSignals: [RuntimeWindowFocusVerification] = []
    private var windowFocusReadbackMismatchSignals: [WindowBindingReadbackDiagnostic] = []

    init(
        appSwitcherProjection: RuntimeAppSwitcherProjection? = nil,
        homeSummaryProjection: RuntimeHomeSummaryProjection? = nil,
        homeDetailProjectionsByAppID: [String: RuntimeHomeAppDetailProjection]? = nil,
        currentAppWindowProjectionsByAppID: [String: RuntimeCurrentAppWindowProjection] = [:],
        focusedCurrentAppWindowProjectionRead: RuntimeFocusedCurrentAppWindowProjectionRead? = nil,
        activationTargetProjection: RuntimeActivationTargetProjection? = nil,
        spaceTopologyProjection: RuntimeSpaceTopologyProjection? = nil,
        committedSearchIndexRead: RuntimeSearchIndexRead? = nil
    ) {
        self.appSwitcherProjection = appSwitcherProjection
        self.homeSummaryProjection = homeSummaryProjection
        self.homeDetailProjectionsByAppID = homeDetailProjectionsByAppID
            ?? Self.homeDetailProjections(
                currentAppWindowProjectionsByAppID: currentAppWindowProjectionsByAppID
            )
        self.currentAppWindowProjectionsByAppID = currentAppWindowProjectionsByAppID
        if let focusedCurrentAppWindowProjectionRead {
            self.focusedCurrentAppWindowProjectionRead = focusedCurrentAppWindowProjectionRead
        } else if currentAppWindowProjectionsByAppID.count == 1,
                  let projection = currentAppWindowProjectionsByAppID.values.first {
            self.focusedCurrentAppWindowProjectionRead = RuntimeFocusedCurrentAppWindowProjectionRead(
                appID: projection.appID,
                pid: projection.currentAppWindowPayload.summary.pid,
                projection: projection
            )
        } else {
            self.focusedCurrentAppWindowProjectionRead = nil
        }
        self.activationTargetProjection = activationTargetProjection
        self.spaceTopologyProjection = spaceTopologyProjection
        self.committedSearchIndexRead = committedSearchIndexRead
    }

    convenience init(
        appSwitcherApps apps: [AppSwitchCandidate],
        contextsByID: [String: RuntimeAppContext] = [:],
        committedSearchApps: [AppSwitchCandidate]? = nil,
        committedSearchReadiness: RuntimeSearchIndexReadiness = .degradedStaleCommitted,
        spaceTopologyProjection: RuntimeSpaceTopologyProjection? = nil,
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
            spaceTopologyProjection: spaceTopologyProjection,
            committedSearchIndexRead: RuntimeSearchIndexRead(
                projection: committedSearchReadiness == .missingCommittedIndex
                    ? nil
                    : Self.committedSearchIndexProjection(
                        for: committedSearchApps ?? apps,
                        generatedAt: generatedAt,
                        isCompleteForScope: committedSearchReadiness == .committedGenerationValidated
                    ),
                readiness: committedSearchReadiness
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

    func setHomeSummaryProjection(
        _ projection: RuntimeHomeSummaryProjection?
    ) {
        lock.lock()
        homeSummaryProjection = projection
        lock.unlock()
    }

    func setAppSwitcherMaintenanceRequestHandler(
        _ handler:
            ((RuntimeProjectionMaintenanceReason) -> Void)?
    ) {
        lock.lock()
        appSwitcherMaintenanceRequestHandler = handler
        lock.unlock()
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

    func setCurrentAppWindowProjection(
        _ projection: RuntimeCurrentAppWindowProjection,
        appID: String
    ) {
        lock.lock()
        currentAppWindowProjectionsByAppID[appID] = projection
        lock.unlock()
    }

    func focusedCurrentAppWindowProjectionReadCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return focusedCurrentAppWindowProjectionReads
    }

    func spaceTopologyProjectionReadCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return spaceTopologyProjectionReads
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

    func setSelectedCurrentAppWindowChangeSignalHandler(
        _ handler: ((String, pid_t) -> Void)?
    ) {
        lock.lock()
        selectedCurrentAppWindowChangeSignalHandler = handler
        lock.unlock()
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

    func clearCommittedSearchIndex() {
        lock.lock()
        committedSearchIndexRead = nil
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
        defer { lock.unlock() }
        homeDetailProjectionReadsByAppID[appID, default: 0] += 1
        return homeDetailProjectionsByAppID[appID]
    }

    func setHomeDetailProjection(
        _ projection: RuntimeHomeAppDetailProjection?,
        appID: String
    ) {
        lock.lock()
        if let projection {
            homeDetailProjectionsByAppID[appID] = projection
        } else {
            homeDetailProjectionsByAppID.removeValue(forKey: appID)
        }
        lock.unlock()
    }

    func readCurrentAppWindowProjection(appID: String) -> RuntimeCurrentAppWindowProjection? {
        lock.lock()
        currentAppWindowProjectionReadsByAppID[appID, default: 0] += 1
        lock.unlock()
        return currentAppWindowProjectionsByAppID[appID]
    }

    func readFocusedCurrentAppWindowProjection() -> RuntimeFocusedCurrentAppWindowProjectionRead? {
        lock.lock()
        focusedCurrentAppWindowProjectionReads += 1
        if let focusedCurrentAppWindowProjectionRead {
            currentAppWindowProjectionReadsByAppID[
                focusedCurrentAppWindowProjectionRead.appID,
                default: 0
            ] += 1
        }
        lock.unlock()
        return focusedCurrentAppWindowProjectionRead
    }

    func readActivationTargetProjection() -> RuntimeActivationTargetProjection? {
        activationTargetProjection
    }

    func readSpaceTopologyProjection() -> RuntimeSpaceTopologyProjection? {
        lock.lock()
        defer { lock.unlock() }
        spaceTopologyProjectionReads += 1
        return spaceTopologyProjection
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
            hasCompleteAppSwitcherProjection: false,
            hasCompleteHomeSummaryProjection: false,
            hasAppDirectoryProjection: false,
            hasCompleteAppDirectoryProjection: false,
            hasSpaceTopologyProjection: false,
            spaceTopologyTrackedSpaceCount: 0,
            spaceTopologyTrackedWindowCount: 0,
            spaceTopologyFullscreenWindowCount: 0,
            hasActivationTargetProjection: activationTargetProjection != nil,
            hasCommittedSearchIndex: hasCommittedSearchIndex,
            currentAppWindowProjectionAppIDs: [],
            appDirectoryEntryPIDs: []
        )
    }

    func requestAppSwitcherProjectionMaintenance(reason: RuntimeProjectionMaintenanceReason) {
        lock.lock()
        appSwitcherMaintenanceRequests.append(reason)
        let handler = appSwitcherMaintenanceRequestHandler
        lock.unlock()
        handler?(reason)
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
        let handler = selectedCurrentAppWindowChangeSignalHandler
        lock.unlock()
        handler?(appID, pid)
    }

    func signalFocusedCurrentAppWindowsChanged() {
        lock.lock()
        if let focusedCurrentAppWindowProjectionRead {
            selectedCurrentAppWindowChangeSignals.append((
                focusedCurrentAppWindowProjectionRead.appID,
                focusedCurrentAppWindowProjectionRead.pid
            ))
        }
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

    func signalWindowFocusReadbackMismatch(_ diagnostic: WindowBindingReadbackDiagnostic) {
        lock.lock()
        windowFocusReadbackMismatchSignals.append(diagnostic)
        lock.unlock()
    }

    private static func committedSearchIndexProjection(
        for apps: [AppSwitchCandidate],
        generatedAt: TimeInterval,
        isCompleteForScope: Bool = true
    ) -> RuntimeSearchIndexProjection {
        let store = RuntimeReadModelStore()
        store.seedAppSwitcherProjectionForTesting(
            apps: apps,
            contextsByID: [:],
            appDirectoryEntries: nil,
            generatedAt: generatedAt
        )
        store.commitSearchFreshnessBarrierFromMainTablePayload(
            makeRuntimeSearchIndexPayloadForTesting(apps: apps),
            deferredRequestCount: 0,
            hasPendingRequests: false,
            generatedAt: generatedAt
        )
        var projection = store.readCommittedSearchIndexForSearch().projection!
        projection.freshness = RuntimeProjectionFreshness(
            generatedAt: projection.freshness.generatedAt,
            sourceGeneration: projection.freshness.sourceGeneration,
            dirtyAppIDs: projection.freshness.dirtyAppIDs,
            dirtyPIDs: projection.freshness.dirtyPIDs,
            dirtyCGWindowIDs: projection.freshness.dirtyCGWindowIDs,
            spaceTopologySignatureSummary: projection.freshness.spaceTopologySignatureSummary,
            pendingRepairScopes: projection.freshness.pendingRepairScopes,
            isCompleteForScope: isCompleteForScope
        )
        return projection
    }

    private static func homeDetailProjections(
        currentAppWindowProjectionsByAppID: [String: RuntimeCurrentAppWindowProjection]
    ) -> [String: RuntimeHomeAppDetailProjection] {
        Dictionary(
            uniqueKeysWithValues: currentAppWindowProjectionsByAppID.map { appID, projection in
                (
                    appID,
                    RuntimeHomeAppDetailProjection(
                        currentAppWindowPayload: projection.currentAppWindowPayload,
                        freshness: projection.freshness
                    )
                )
            }
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
