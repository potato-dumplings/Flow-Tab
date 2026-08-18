import Foundation

enum HotkeyMonitoringBackendPolicy {
    static func requiresCoordinatedChordEventMonitoring(
        mainConfiguration: SwitcherHotkeyConfiguration,
        inAppWindowConfiguration: SwitcherHotkeyConfiguration
    ) -> Bool {
        !mainConfiguration.supportsCarbonRegistration
            || !inAppWindowConfiguration.supportsCarbonRegistration
    }
}

enum HotkeyRouteRegistrationState: String, Equatable, Sendable {
    case carbon
    case accessibilityChord
    case pausedAccessibility
    case skippedConflict

    var isActive: Bool {
        self == .carbon || self == .accessibilityChord
    }

    var requiresChordEventMonitoring: Bool {
        self == .accessibilityChord
    }
}

struct HotkeyMonitoringAccessPlan: Equatable, Sendable {
    let mainRouteState: HotkeyRouteRegistrationState
    let inAppWindowRouteState: HotkeyRouteRegistrationState
}

enum HotkeyMonitoringAccessPolicy {
    static func plan(
        mainConfiguration: SwitcherHotkeyConfiguration,
        inAppWindowConfiguration: SwitcherHotkeyConfiguration,
        accessibilityTrusted: Bool
    ) -> HotkeyMonitoringAccessPlan {
        guard accessibilityTrusted else {
            return HotkeyMonitoringAccessPlan(
                mainRouteState:
                    mainConfiguration
                        .supportsPermissionlessGlobalSwitching
                    ? .carbon : .pausedAccessibility,
                inAppWindowRouteState: .pausedAccessibility
            )
        }

        let coordinatedChordMonitoring = HotkeyMonitoringBackendPolicy
            .requiresCoordinatedChordEventMonitoring(
                mainConfiguration: mainConfiguration,
                inAppWindowConfiguration: inAppWindowConfiguration
            )
        let activeState: HotkeyRouteRegistrationState =
            coordinatedChordMonitoring ? .accessibilityChord : .carbon
        return HotkeyMonitoringAccessPlan(
            mainRouteState: activeState,
            inAppWindowRouteState: activeState
        )
    }
}

extension Notification.Name {
    static let flowTabHotkeyRegistrationEvidenceDidChange = Notification.Name(
        "FlowTab.HotkeyRegistrationEvidenceDidChange"
    )
}

struct HotkeyRegistrationEvidence: Equatable, Sendable {
    private enum NotificationUserInfoKey {
        static let evidence = "evidence"
    }

    static let applicationLaunchSource = "application_launch"

    let generation: UInt64
    let requestID: UUID
    let mainConfiguration: SwitcherHotkeyConfiguration
    let inAppWindowConfiguration: SwitcherHotkeyConfiguration
    let commandTabTakeoverActive: Bool
    let mainRouteState: HotkeyRouteRegistrationState
    let inAppWindowRouteState: HotkeyRouteRegistrationState
    let source: String

    init(
        generation: UInt64,
        request: HotkeyRegistrationRequest,
        commandTabTakeoverActive: Bool,
        mainRouteState: HotkeyRouteRegistrationState = .carbon,
        inAppWindowRouteState: HotkeyRouteRegistrationState = .carbon,
        source: String = "unspecified"
    ) {
        self.generation = generation
        self.requestID = request.requestID
        self.mainConfiguration = request.mainConfiguration
        self.inAppWindowConfiguration = request.inAppWindowConfiguration
        self.commandTabTakeoverActive = commandTabTakeoverActive
        self.mainRouteState = mainRouteState
        self.inAppWindowRouteState = inAppWindowRouteState
        self.source = source
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
