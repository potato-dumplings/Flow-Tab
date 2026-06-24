import CoreGraphics
import Foundation

struct RuntimeCurrentAppRepairEvidence: Equatable, Sendable {
    let appID: String
    let pid: pid_t
    let appDirectoryEntries: [RuntimeAppDirectoryEntry]
    let currentAppWindowPayloadWasEmpty: Bool

    init(
        appID: String,
        pid: pid_t,
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        currentAppWindowPayloadWasEmpty: Bool
    ) {
        self.appID = appID
        self.pid = pid
        self.appDirectoryEntries = appDirectoryEntries
        self.currentAppWindowPayloadWasEmpty = currentAppWindowPayloadWasEmpty
    }

    init(
        currentAppWindowPayload payload: RuntimeCurrentAppWindowPayload,
        currentAppWindowPayloadWasEmpty: Bool
    ) {
        self.init(
            appID: payload.summary.appID,
            pid: payload.summary.pid,
            appDirectoryEntries: payload.appDirectoryEntries,
            currentAppWindowPayloadWasEmpty: currentAppWindowPayloadWasEmpty
        )
    }
}

struct RuntimeAppWindowReconciliationResult {
    let pid: pid_t
    let affectedCGWindowIDs: Set<CGWindowID>
    let knownAffectedCGWindowIDs: Set<CGWindowID>
    let exactAffectedCGWindowIDs: Set<CGWindowID>
    let currentAppWindowPayload: RuntimeCurrentAppWindowPayload?
    let currentAppWindowPayloadWasEmpty: Bool
    let isTransientEmptyCurrentAppWindowPayload: Bool

    var currentAppRepairEvidence: RuntimeCurrentAppRepairEvidence? {
        guard let currentAppWindowPayload else { return nil }
        return RuntimeCurrentAppRepairEvidence(
            currentAppWindowPayload: currentAppWindowPayload,
            currentAppWindowPayloadWasEmpty: currentAppWindowPayloadWasEmpty
        )
    }
}

protocol RuntimeProjectionRepairProviding: AnyObject {
    func reconcileAppWindows(
        processIdentifier pid: pid_t,
        affectedCGWindowIDs: Set<CGWindowID>
    ) -> RuntimeAppWindowReconciliationResult
    func reconcileSpaceTopology(
        affectedCGWindowIDs: Set<CGWindowID>
    ) -> [RuntimeAppWindowReconciliationResult]
    func currentAppWindowPayloadFromMainTables(
        appID: String,
        pid: pid_t,
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeCurrentAppWindowPayload?
    func fullAppSwitcherProjectionPayloadFromMainTables(
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeFullRepairProjectionPayload?
    func fullRepairProjectionPayload() -> RuntimeFullRepairProjectionPayload
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
    func recordAppLaunched(appID: String, pid: pid_t, now: TimeInterval)
    func recordAppWindowsChanged(appID: String, pid: pid_t, now: TimeInterval)
    func recordSelectedCurrentAppWindowsChanged(appID: String, pid: pid_t, now: TimeInterval)
    func hasPendingReconciliationRequests() -> Bool
    func scheduleFullRepairFallback(now: TimeInterval)
    func promoteSearchFreshnessBarrierRequests(now: TimeInterval) -> [RuntimeReconciliationRequest]
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
