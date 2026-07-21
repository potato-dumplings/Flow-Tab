#if FLOWTAB_TESTING
import AppKit
import Foundation

struct RuntimeUITestFrontmostAppTarget: Equatable, Sendable {
    let appID: String
    let pid: pid_t
    let bundleIdentifier: String

    static func resolve(bundleIdentifier: String) -> Self? {
        guard let runningApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter({ !$0.isTerminated })
            .sorted(by: { lhs, rhs in
                let lhsLaunchDate = lhs.launchDate ?? .distantPast
                let rhsLaunchDate = rhs.launchDate ?? .distantPast
                if lhsLaunchDate != rhsLaunchDate {
                    return lhsLaunchDate > rhsLaunchDate
                }
                return lhs.processIdentifier < rhs.processIdentifier
            })
            .first
        else {
            return nil
        }
        return RuntimeUITestFrontmostAppTarget(
            appID: RuntimeAppIdentity.appID(for: runningApp),
            pid: runningApp.processIdentifier,
            bundleIdentifier: bundleIdentifier
        )
    }
}

final class RuntimeUITestFrontmostProjectionService: RuntimeProjectionServing, @unchecked Sendable {
    private let baseService: any RuntimeProjectionServing
    private let targetProvider: () -> RuntimeUITestFrontmostAppTarget?

    init(
        baseService: any RuntimeProjectionServing,
        bundleIdentifier: String
    ) {
        self.baseService = baseService
        targetProvider = {
            RuntimeUITestFrontmostAppTarget.resolve(bundleIdentifier: bundleIdentifier)
        }
    }

    init(
        baseService: any RuntimeProjectionServing,
        targetProvider: @escaping () -> RuntimeUITestFrontmostAppTarget?
    ) {
        self.baseService = baseService
        self.targetProvider = targetProvider
    }

    func resolvedTarget() -> RuntimeUITestFrontmostAppTarget? {
        targetProvider()
    }

    func waitForMaintenanceQueueForTesting() {
        (baseService as? RuntimeProjectionService)?.waitForMaintenanceQueueForTesting()
    }

    func readAppSwitcherProjection() -> RuntimeAppSwitcherProjection? {
        baseService.readAppSwitcherProjection()
    }

    func readHomeSummaryProjection() -> RuntimeHomeSummaryProjection? {
        baseService.readHomeSummaryProjection()
    }

    func readHomeAppDetailProjection(appID: String) -> RuntimeHomeAppDetailProjection? {
        baseService.readHomeAppDetailProjection(appID: appID)
    }

    func readCurrentAppWindowProjection(appID: String) -> RuntimeCurrentAppWindowProjection? {
        baseService.readCurrentAppWindowProjection(appID: appID)
    }

    func readFocusedCurrentAppWindowProjection() -> RuntimeFocusedCurrentAppWindowProjectionRead? {
        guard let target = resolvedTarget() else {
            return baseService.readFocusedCurrentAppWindowProjection()
        }
        let projection = baseService.readCurrentAppWindowProjection(appID: target.appID).flatMap {
            $0.currentAppWindowPayload.summary.pid == target.pid ? $0 : nil
        }
        return RuntimeFocusedCurrentAppWindowProjectionRead(
            appID: target.appID,
            pid: target.pid,
            projection: projection
        )
    }

    func readActivationTargetProjection() -> RuntimeActivationTargetProjection? {
        baseService.readActivationTargetProjection()
    }

    func readSpaceTopologyProjection() -> RuntimeSpaceTopologyProjection? {
        baseService.readSpaceTopologyProjection()
    }

    func readCommittedSearchIndexForSearch() -> RuntimeSearchIndexRead {
        baseService.readCommittedSearchIndexForSearch()
    }

    func runtimeReadModelDiagnostics() -> RuntimeReadModelDiagnostics {
        baseService.runtimeReadModelDiagnostics()
    }

    func requestAppSwitcherProjectionMaintenance(reason: RuntimeProjectionMaintenanceReason) {
        baseService.requestAppSwitcherProjectionMaintenance(reason: reason)
    }

    func requestSearchIndexFreshnessBarrier(reason: RuntimeProjectionMaintenanceReason) {
        baseService.requestSearchIndexFreshnessBarrier(reason: reason)
    }

    func signalSpaceTopologyChanged() {
        baseService.signalSpaceTopologyChanged()
    }

    func signalAppLaunched(
        appID: String,
        pid: pid_t,
        appDirectoryEntry: RuntimeAppDirectoryEntry?
    ) {
        baseService.signalAppLaunched(
            appID: appID,
            pid: pid,
            appDirectoryEntry: appDirectoryEntry
        )
    }

    func signalAppWindowsChanged(appID: String, pid: pid_t) {
        baseService.signalAppWindowsChanged(appID: appID, pid: pid)
    }

    func signalSelectedCurrentAppWindowsChanged(appID: String, pid: pid_t) {
        baseService.signalSelectedCurrentAppWindowsChanged(appID: appID, pid: pid)
    }

    func signalFocusedCurrentAppWindowsChanged() {
        guard let target = resolvedTarget() else {
            baseService.signalFocusedCurrentAppWindowsChanged()
            return
        }
        baseService.signalSelectedCurrentAppWindowsChanged(
            appID: target.appID,
            pid: target.pid
        )
    }

    func signalAXWindowDestroyed(appID: String, pid: pid_t, axWindowID: String) {
        baseService.signalAXWindowDestroyed(appID: appID, pid: pid, axWindowID: axWindowID)
    }

    func signalAppTerminated(appID: String, pid: pid_t) {
        baseService.signalAppTerminated(appID: appID, pid: pid)
    }

    func signalWindowFocusVerified(_ verification: RuntimeWindowFocusVerification) {
        baseService.signalWindowFocusVerified(verification)
    }

    func signalWindowFocusVerified(appID: String, pid: pid_t) {
        baseService.signalWindowFocusVerified(appID: appID, pid: pid)
    }

    func signalWindowFocusReadbackMismatch(_ diagnostic: WindowBindingReadbackDiagnostic) {
        baseService.signalWindowFocusReadbackMismatch(diagnostic)
    }
}
#endif
