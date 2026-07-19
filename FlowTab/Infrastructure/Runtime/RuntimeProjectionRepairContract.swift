import CoreGraphics
import Foundation

struct RuntimeCurrentAppRepairEvidence: Equatable, Sendable {
    let appID: String
    let pid: pid_t
    let appDirectoryEntries: [RuntimeAppDirectoryEntry]
    let currentAppWindowPayloadWasEmpty: Bool
    let authoritativeCGWindowIDs: Set<CGWindowID>?

    init(
        appID: String,
        pid: pid_t,
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        currentAppWindowPayloadWasEmpty: Bool,
        authoritativeCGWindowIDs: Set<CGWindowID>? = nil
    ) {
        self.appID = appID
        self.pid = pid
        self.appDirectoryEntries = appDirectoryEntries
        self.currentAppWindowPayloadWasEmpty = currentAppWindowPayloadWasEmpty
        self.authoritativeCGWindowIDs = authoritativeCGWindowIDs
    }
}

struct RuntimeFullRepairEvidence: Equatable, Sendable {
    let appDirectoryEntries: [RuntimeAppDirectoryEntry]
    let windowRecordRefresh: RuntimeFullRepairWindowRecordRefreshEvidence?

    init(
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        windowRecordRefresh: RuntimeFullRepairWindowRecordRefreshEvidence? = nil
    ) {
        self.appDirectoryEntries = appDirectoryEntries
        self.windowRecordRefresh = windowRecordRefresh
    }
}

struct RuntimeFullRepairWindowRecordRefreshEvidence: Equatable, Sendable {
    let runningAppCount: Int
    let projectedWindowPIDCount: Int
    let projectedWindowCount: Int
}

struct RuntimeAppWindowReconciliationResult {
    let pid: pid_t
    let affectedCGWindowIDs: Set<CGWindowID>
    let knownAffectedCGWindowIDs: Set<CGWindowID>
    let exactAffectedCGWindowIDs: Set<CGWindowID>
    let currentAppRepairEvidence: RuntimeCurrentAppRepairEvidence?
    let isTransientEmptyCurrentAppWindowPayload: Bool
}

protocol RuntimeProjectionRepairProviding: AnyObject {
    func reconcileAppWindows(
        processIdentifier pid: pid_t,
        affectedCGWindowIDs: Set<CGWindowID>
    ) -> RuntimeAppWindowReconciliationResult
    func reconcileSpaceTopology(
        affectedCGWindowIDs: Set<CGWindowID>
    ) -> [RuntimeAppWindowReconciliationResult]
    func fullRepairEvidence() -> RuntimeFullRepairEvidence
    func recordSpaceTopologyChanged(now: TimeInterval) -> RuntimeSpaceTopologySignalFacts
    func signalAXWindowDestroyed(
        appID: String,
        processIdentifier pid: pid_t,
        axWindowID: String,
        now: TimeInterval
    ) -> CGWindowID?
    func recordAppTerminated(processIdentifier pid: pid_t)
    func recordWindowFocusVerification(
        _ verification: RuntimeWindowFocusVerification,
        now: TimeInterval
    ) -> Set<CGWindowID>
    func recordWindowFocusReadbackMismatch(
        _ diagnostic: WindowBindingReadbackDiagnostic,
        now: TimeInterval
    ) -> Set<CGWindowID>
    func recordSearchWindowCoverageNeeded(appID: String, pid: pid_t, now: TimeInterval)
    func recordAppLaunched(appID: String, pid: pid_t, now: TimeInterval)
    func recordAppWindowsChanged(appID: String, pid: pid_t, now: TimeInterval)
    func recordSelectedCurrentAppWindowsChanged(appID: String, pid: pid_t, now: TimeInterval)
    func hasPendingReconciliationRequests(includeFullRepair: Bool) -> Bool
    func pendingScopedReconciliationAffectedCGWindowIDs() -> Set<CGWindowID>
    func scheduleFullRepairFallback(now: TimeInterval)
    func promoteSearchFreshnessBarrierRequests(now: TimeInterval) -> [RuntimeReconciliationRequest]
    func recordSpaceTopologyRepairNeeded(
        affectedCGWindowIDs: Set<CGWindowID>,
        now: TimeInterval
    )
    func readyReconciliationRequests(
        now: TimeInterval,
        includeFullRepair: Bool
    ) -> [RuntimeReconciliationRequest]
    func startReconciliationRequest(id: UInt64) -> RuntimeReconciliationRequest?
    func completeReconciliationRequest(id: UInt64)
    func deferReconciliationRequestAfterTransientEmptyCurrentAppWindowPayload(
        id: UInt64,
        now: TimeInterval
    )
}
