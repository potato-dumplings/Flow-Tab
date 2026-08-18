import Foundation

extension Notification.Name {
    static let runtimeAppSwitcherProjectionDidUpdate = Notification.Name(
        "FlowTab.runtimeAppSwitcherProjectionDidUpdate"
    )
    static let runtimeCurrentAppWindowProjectionDidUpdate = Notification.Name(
        "FlowTab.runtimeCurrentAppWindowProjectionDidUpdate"
    )
    static let runtimeCommittedSearchIndexDidUpdate = Notification.Name(
        "FlowTab.runtimeCommittedSearchIndexDidUpdate"
    )
    static let runtimeAppSwitcherProjectionMaintenanceDidFinish = Notification.Name(
        "FlowTab.runtimeAppSwitcherProjectionMaintenanceDidFinish"
    )
}

enum RuntimeProjectionNotificationUserInfoKey {
    static let appID = "appID"
    static let runtimeProjectionMaintenanceReason =
        "runtimeProjectionMaintenanceReason"
    static let currentAppWindowProjectionUpdateEvidence =
        "currentAppWindowProjectionUpdateEvidence"
}

struct RuntimeAppSwitcherProjectionMaintenanceCompletion: Equatable {
    let reason: RuntimeProjectionMaintenanceReason

    init(reason: RuntimeProjectionMaintenanceReason) {
        self.reason = reason
    }

    init?(notification: Notification) {
        guard notification.name
                == .runtimeAppSwitcherProjectionMaintenanceDidFinish,
              let rawReason = notification.userInfo?[
                RuntimeProjectionNotificationUserInfoKey
                    .runtimeProjectionMaintenanceReason
              ] as? String,
              let reason = RuntimeProjectionMaintenanceReason(
                rawValue: rawReason
              )
        else {
            return nil
        }
        self.reason = reason
    }

    var notificationUserInfo: [AnyHashable: Any] {
        [
            RuntimeProjectionNotificationUserInfoKey
                .runtimeProjectionMaintenanceReason: reason.rawValue
        ]
    }
}

struct RuntimeCurrentAppWindowProjectionUpdateEvidence: Equatable {
    let appID: String
    let processIdentifier: pid_t
    let windowIDs: [String]
    let isCompleteForScope: Bool
    let sourceGeneration: RuntimeReadModelGeneration

    init(
        appID: String,
        processIdentifier: pid_t,
        windowIDs: [String],
        isCompleteForScope: Bool,
        sourceGeneration: RuntimeReadModelGeneration
    ) {
        self.appID = appID
        self.processIdentifier = processIdentifier
        self.windowIDs = windowIDs
        self.isCompleteForScope = isCompleteForScope
        self.sourceGeneration = sourceGeneration
    }

    init(projection: RuntimeCurrentAppWindowProjection) {
        appID = projection.appID
        processIdentifier =
            projection.currentAppWindowPayload.summary.pid
        windowIDs =
            projection.currentAppWindowPayload.candidate.windows
                .map(\.id)
        isCompleteForScope =
            projection.freshness.isCompleteForScope
        sourceGeneration =
            projection.freshness.sourceGeneration
    }
}

enum RuntimeProjectionNotificationPublisher {
    static func post(
        name: Notification.Name,
        object: Any,
        userInfo: [AnyHashable: Any]? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        DispatchQueue.main.async {
            notificationCenter.post(
                name: name,
                object: object,
                userInfo: userInfo
            )
        }
    }
}

extension RuntimeProjectionService {
    func publishAppSwitcherProjectionMaintenanceCompletion(
        reason: RuntimeProjectionMaintenanceReason
    ) {
        let completion = RuntimeAppSwitcherProjectionMaintenanceCompletion(
            reason: reason
        )
        RuntimeProjectionNotificationPublisher.post(
            name: .runtimeAppSwitcherProjectionMaintenanceDidFinish,
            object: self,
            userInfo: completion.notificationUserInfo
        )
    }
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
    func scheduleWorkspaceAppTerminated(appID: String, pid: pid_t)
    func signalWindowFocusVerified(_ verification: RuntimeWindowFocusVerification)
    func signalWindowFocusVerified(appID: String, pid: pid_t)
    func signalWindowFocusReadbackMismatch(_ diagnostic: WindowBindingReadbackDiagnostic)
}

extension RuntimeProjectionServing {
    func scheduleWorkspaceAppTerminated(appID: String, pid: pid_t) {
        signalAppTerminated(appID: appID, pid: pid)
    }
}
