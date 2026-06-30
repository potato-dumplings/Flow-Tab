import Foundation

extension Notification.Name {
    static let runtimeCommittedSearchIndexDidUpdate = Notification.Name(
        "FlowTab.runtimeCommittedSearchIndexDidUpdate"
    )
}

protocol RuntimeProjectionServing: Sendable {
    func readAppSwitcherProjection() -> RuntimeAppSwitcherProjection?
    func readHomeSummaryProjection() -> RuntimeHomeSummaryProjection?
    func readHomeAppDetailProjection(appID: String) -> RuntimeHomeAppDetailProjection?
    func readCurrentAppWindowProjection(appID: String) -> RuntimeCurrentAppWindowProjection?
    func readFocusedCurrentAppWindowProjection() -> RuntimeFocusedCurrentAppWindowProjectionRead?
    func readActivationTargetProjection() -> RuntimeActivationTargetProjection?
    func readSpaceTopologyProjection() -> RuntimeSpaceTopologyProjection?
    func readCommittedSearchIndexForSearch() -> RuntimeSearchIndexRead
    func runtimeReadModelDiagnostics() -> RuntimeReadModelDiagnostics
    func requestAppSwitcherProjectionMaintenance(reason: RuntimeProjectionMaintenanceReason)
    func requestSearchIndexFreshnessBarrier(reason: RuntimeProjectionMaintenanceReason)
    func signalSpaceTopologyChanged()
    func signalAppLaunched(
        appID: String,
        pid: pid_t,
        appDirectoryEntry: RuntimeAppDirectoryEntry?
    )
    func signalAppWindowsChanged(appID: String, pid: pid_t)
    func signalSelectedCurrentAppWindowsChanged(appID: String, pid: pid_t)
    func signalFocusedCurrentAppWindowsChanged()
    func signalAXWindowDestroyed(appID: String, pid: pid_t, axWindowID: String)
    func signalAppTerminated(appID: String, pid: pid_t)
    func signalWindowFocusVerified(_ verification: RuntimeWindowFocusVerification)
    func signalWindowFocusVerified(appID: String, pid: pid_t)
}
