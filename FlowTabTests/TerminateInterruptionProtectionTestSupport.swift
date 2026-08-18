import AppKit
import FlowTabCore
import XCTest
@testable import FlowTab

@MainActor
final class ManualTerminateInterruptionProtectionScheduler:
    TerminateInterruptionProtectionScheduling
{
    private struct ScheduledAction {
        let token: ManualTerminateInterruptionProtectionToken
        let action: @MainActor @Sendable () -> Void
    }

    private var scheduled: [ScheduledAction] = []

    var pendingCount: Int {
        scheduled.filter(\.token.isAvailable).count
    }

    func scheduleWatchdog(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any TerminateInterruptionProtectionCancellable {
        XCTAssertEqual(interval, 5.0)
        let token = ManualTerminateInterruptionProtectionToken()
        scheduled.append(
            ScheduledAction(token: token, action: action)
        )
        return token
    }

    func fireNextAvailable() {
        guard let item = scheduled.first(where: {
            $0.token.isAvailable
        }) else {
            return XCTFail("Expected a pending termination watchdog.")
        }
        item.token.markFired()
        item.action()
    }

    func fireEveryRetainedAction() {
        for item in scheduled {
            item.token.markFired()
            item.action()
        }
    }
}

@MainActor
private final class ManualTerminateInterruptionProtectionToken:
    TerminateInterruptionProtectionCancellable
{
    private(set) var isCancelled = false
    private(set) var didFire = false

    var isAvailable: Bool {
        !isCancelled && !didFire
    }

    func markFired() {
        didFire = true
    }

    func cancel() {
        isCancelled = true
    }
}

final class RetainingTerminatedAppRuntimeProjectionService:
    RuntimeProjectionServing,
    @unchecked Sendable
{
    private let recording: RecordingRuntimeProjectionService
    private let lock = NSLock()
    private var terminationSignals: [(appID: String, pid: pid_t)] = []

    init(recording: RecordingRuntimeProjectionService) {
        self.recording = recording
    }

    func appTerminationSignalsRecorded() -> [(appID: String, pid: pid_t)] {
        lock.lock()
        defer { lock.unlock() }
        return terminationSignals
    }

    func readAppSwitcherProjection() -> RuntimeAppSwitcherProjection? {
        recording.readAppSwitcherProjection()
    }

    func readHomeSummaryProjection() -> RuntimeHomeSummaryProjection? {
        recording.readHomeSummaryProjection()
    }

    func readHomeAppDetailProjection(appID: String)
        -> RuntimeHomeAppDetailProjection?
    {
        recording.readHomeAppDetailProjection(appID: appID)
    }

    func readCurrentAppWindowProjection(appID: String)
        -> RuntimeCurrentAppWindowProjection?
    {
        recording.readCurrentAppWindowProjection(appID: appID)
    }

    func readFocusedCurrentAppWindowProjection()
        -> RuntimeFocusedCurrentAppWindowProjectionRead?
    {
        recording.readFocusedCurrentAppWindowProjection()
    }

    func readActivationTargetProjection()
        -> RuntimeActivationTargetProjection?
    {
        recording.readActivationTargetProjection()
    }

    func readSpaceTopologyProjection() -> RuntimeSpaceTopologyProjection? {
        recording.readSpaceTopologyProjection()
    }

    func readCommittedSearchIndexForSearch() -> RuntimeSearchIndexRead {
        recording.readCommittedSearchIndexForSearch()
    }

    func runtimeReadModelDiagnostics() -> RuntimeReadModelDiagnostics {
        recording.runtimeReadModelDiagnostics()
    }

    func requestAppSwitcherProjectionMaintenance(
        reason: RuntimeProjectionMaintenanceReason
    ) {
        recording.requestAppSwitcherProjectionMaintenance(reason: reason)
    }

    func requestSearchIndexFreshnessBarrier(
        reason: RuntimeProjectionMaintenanceReason
    ) {
        recording.requestSearchIndexFreshnessBarrier(reason: reason)
    }

    func signalSpaceTopologyChanged() {
        recording.signalSpaceTopologyChanged()
    }

    func signalAppLaunched(
        appID: String,
        pid: pid_t,
        appDirectoryEntry: RuntimeAppDirectoryEntry?
    ) {
        recording.signalAppLaunched(
            appID: appID,
            pid: pid,
            appDirectoryEntry: appDirectoryEntry
        )
    }

    func signalAppWindowsChanged(appID: String, pid: pid_t) {
        recording.signalAppWindowsChanged(appID: appID, pid: pid)
    }

    func signalSelectedCurrentAppWindowsChanged(
        appID: String,
        pid: pid_t
    ) {
        recording.signalSelectedCurrentAppWindowsChanged(
            appID: appID,
            pid: pid
        )
    }

    func signalFocusedCurrentAppWindowsChanged() {
        recording.signalFocusedCurrentAppWindowsChanged()
    }

    func signalAXWindowDestroyed(
        appID: String,
        pid: pid_t,
        axWindowID: String
    ) {
        recording.signalAXWindowDestroyed(
            appID: appID,
            pid: pid,
            axWindowID: axWindowID
        )
    }

    func signalAppTerminated(appID: String, pid: pid_t) {
        lock.lock()
        terminationSignals.append((appID, pid))
        lock.unlock()
    }

    func signalWindowFocusVerified(
        _ verification: RuntimeWindowFocusVerification
    ) {
        recording.signalWindowFocusVerified(verification)
    }

    func signalWindowFocusVerified(appID: String, pid: pid_t) {
        recording.signalWindowFocusVerified(appID: appID, pid: pid)
    }

    func signalWindowFocusReadbackMismatch(
        _ diagnostic: WindowBindingReadbackDiagnostic
    ) {
        recording.signalWindowFocusReadbackMismatch(diagnostic)
    }
}

@MainActor
final class MutableTerminateTargetProcessStateReader:
    TerminateTargetProcessStateReading
{
    var resolvedState: TerminateTargetProcessState = .running

    func state(forPID _: pid_t) -> TerminateTargetProcessState {
        resolvedState
    }
}

extension FlowTabTests {
    static func terminateTarget()
        -> TerminateInterruptionTargetIdentity
    {
        TerminateInterruptionTargetIdentity(
            appID: "com.example.target",
            pid: 42_500,
            requestGeneration: 9
        )
    }

    static func terminateBaseline(
        appID: String = "com.example.target",
        generation: UInt64
    ) -> TerminateInterruptionProtectionBaseline {
        TerminateInterruptionProtectionBaseline(
            appID: appID,
            projectionGeneration: generation,
            projectionContainsAppID: true,
            panelVisibility: terminatePanelVisibility()
        )
    }

    static func terminateSnapshot(
        generation: UInt64,
        projectionState: TerminateTargetProjectionState,
        processState: TerminateTargetProcessState,
        pendingRequestMatches: Bool,
        activeSpaceTransitionPending: Bool = false,
        panelKey: Bool = true,
        appActive: Bool = true
    ) -> TerminateInterruptionProtectionSnapshot {
        TerminateInterruptionProtectionSnapshot(
            projectionGeneration: generation,
            projectionState: projectionState,
            processState: processState,
            sessionContainsAppID: projectionState
                == .exactInstancePresent,
            pendingRequestMatches: pendingRequestMatches,
            activeSpaceTransitionPending: activeSpaceTransitionPending,
            panelVisibility: terminatePanelVisibility(
                panelKey: panelKey,
                appActive: appActive
            )
        )
    }

    static func terminatePanelVisibility(
        panelKey: Bool = true,
        appActive: Bool = true
    ) -> PanelVisibilitySnapshot {
        PanelVisibilitySnapshot(
            panelPresented: true,
            userVisible: true,
            occlusionVisible: true,
            panelKey: panelKey,
            appActive: appActive,
            searchActive: false,
            inputFocused: false,
            firstResponder: "nil"
        )
    }
}
