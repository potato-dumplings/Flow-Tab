import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable

    init(serviceStatus: SMAppService.Status) {
        switch serviceStatus {
        case .enabled:
            self = .enabled
        case .notRegistered:
            self = .disabled
        case .requiresApproval:
            self = .requiresApproval
        case .notFound:
            self = .unavailable
        @unknown default:
            self = .unavailable
        }
    }

    var preferenceAllowedValue: Bool {
        switch self {
        case .enabled, .requiresApproval:
            return true
        case .disabled, .unavailable:
            return false
        }
    }

    var logValue: String {
        switch self {
        case .enabled:
            return "enabled"
        case .disabled:
            return "disabled"
        case .requiresApproval:
            return "requiresApproval"
        case .unavailable:
            return "unavailable"
        }
    }
}

protocol LaunchAtLoginManaging: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func setEnabled(_ enabled: Bool) throws
}

extension LaunchAtLoginManaging {
    func reconcile(allowed: Bool) throws {
        if allowed {
            guard status != .enabled && status != .requiresApproval else { return }
            try setEnabled(true)
        } else {
            guard status != .disabled && status != .unavailable else { return }
            try setEnabled(false)
        }
    }
}

final class LaunchAtLoginController: LaunchAtLoginManaging {
    static let shared = LaunchAtLoginController()

    static var statusOverrideForTesting: (() -> LaunchAtLoginStatus)?
    static var setEnabledOverrideForTesting: ((Bool) throws -> Void)?

    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: LaunchAtLoginStatus {
        if let statusOverrideForTesting = Self.statusOverrideForTesting {
            return statusOverrideForTesting()
        }
        if FlowTabTestLaunchOptions.usesMockLaunchAtLoginService {
            return LaunchAtLoginPreferencesStore.loadAllowLaunchAtLogin()
                ? .enabled
                : .disabled
        }
        return LaunchAtLoginStatus(serviceStatus: service.status)
    }

    func setEnabled(_ enabled: Bool) throws {
        if let setEnabledOverrideForTesting = Self.setEnabledOverrideForTesting {
            try setEnabledOverrideForTesting(enabled)
            return
        }
        if FlowTabTestLaunchOptions.usesMockLaunchAtLoginService {
            return
        }

        if enabled {
            guard status != .enabled && status != .requiresApproval else { return }
            try service.register()
        } else {
            guard status != .disabled && status != .unavailable else { return }
            try service.unregister()
        }
    }
}
