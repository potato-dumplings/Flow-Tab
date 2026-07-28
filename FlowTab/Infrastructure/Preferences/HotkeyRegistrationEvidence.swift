import Foundation

extension Notification.Name {
    static let flowTabHotkeyRegistrationEvidenceDidChange = Notification.Name(
        "FlowTab.HotkeyRegistrationEvidenceDidChange"
    )
}

struct HotkeyRegistrationEvidence: Equatable, Sendable {
    private enum NotificationUserInfoKey {
        static let evidence = "evidence"
    }

    let generation: UInt64
    let requestID: UUID
    let mainConfiguration: SwitcherHotkeyConfiguration
    let inAppWindowConfiguration: SwitcherHotkeyConfiguration
    let commandTabTakeoverActive: Bool

    init(
        generation: UInt64,
        request: HotkeyRegistrationRequest,
        commandTabTakeoverActive: Bool
    ) {
        self.generation = generation
        self.requestID = request.requestID
        self.mainConfiguration = request.mainConfiguration
        self.inAppWindowConfiguration = request.inAppWindowConfiguration
        self.commandTabTakeoverActive = commandTabTakeoverActive
    }

    init?(notification: Notification) {
        guard
            let evidence = notification.userInfo?[NotificationUserInfoKey.evidence]
                as? HotkeyRegistrationEvidence
        else {
            return nil
        }
        self = evidence
    }

    var notificationUserInfo: [AnyHashable: Any] {
        [NotificationUserInfoKey.evidence: self]
    }

    func matchesConfiguration(of request: HotkeyRegistrationRequest) -> Bool {
        mainConfiguration == request.mainConfiguration
            && inAppWindowConfiguration == request.inAppWindowConfiguration
    }
}
