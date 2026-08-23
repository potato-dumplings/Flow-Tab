public enum AppVisibilityHiddenReason: Equatable, Sendable {
    case userPreference
    case runtimeMode
}

public enum AppVisibilityPresentationState: Equatable, Sendable {
    case visible
    case hidden(reason: AppVisibilityHiddenReason)
    case unavailable(reason: AppVisibilityUnavailableReason)

    public var isEffectivelyHidden: Bool {
        guard case .hidden = self else { return false }
        return true
    }
}

public enum AppVisibilityControlMode: Equatable, Sendable {
    case standard
    case regularModeOnly
    case unavailable
}

public struct AppVisibilityPresentation: Equatable, Sendable {
    public let state: AppVisibilityPresentationState
    public let controlMode: AppVisibilityControlMode

    public init(
        state: AppVisibilityPresentationState,
        controlMode: AppVisibilityControlMode
    ) {
        self.state = state
        self.controlMode = controlMode
    }
}

public struct AppVisibilityPresentationFacts: Equatable, Sendable {
    public let visibilityCapability: AppVisibilityCapability
    public let runtimeActivationPolicy: ApplicationRuntimeActivationPolicy?
    public let isCurrentProcess: Bool
    public let isHiddenByUserPreference: Bool

    public init(
        visibilityCapability: AppVisibilityCapability,
        runtimeActivationPolicy: ApplicationRuntimeActivationPolicy?,
        isCurrentProcess: Bool,
        isHiddenByUserPreference: Bool
    ) {
        self.visibilityCapability = visibilityCapability
        self.runtimeActivationPolicy = runtimeActivationPolicy
        self.isCurrentProcess = isCurrentProcess
        self.isHiddenByUserPreference = isHiddenByUserPreference
    }
}

public enum AppVisibilityPresentationPolicy {
    public static func presentation(
        for facts: AppVisibilityPresentationFacts
    ) -> AppVisibilityPresentation {
        if let reason = facts.visibilityCapability.unavailableReason {
            return AppVisibilityPresentation(
                state: .unavailable(reason: reason),
                controlMode: .unavailable
            )
        }

        if !facts.isCurrentProcess,
           facts.runtimeActivationPolicy == .accessory
            || facts.runtimeActivationPolicy == .prohibited {
            return AppVisibilityPresentation(
                state: .hidden(reason: .runtimeMode),
                controlMode: .regularModeOnly
            )
        }

        return AppVisibilityPresentation(
            state: facts.isHiddenByUserPreference
                ? .hidden(reason: .userPreference)
                : .visible,
            controlMode: .standard
        )
    }
}

public enum ApplicationRuntimeActivationPolicyAggregation {
    public static func aggregate(
        _ policies: [ApplicationRuntimeActivationPolicy]
    ) -> ApplicationRuntimeActivationPolicy? {
        if policies.contains(.regular) {
            return .regular
        }
        if policies.contains(.accessory) {
            return .accessory
        }
        if policies.contains(.prohibited) {
            return .prohibited
        }
        return nil
    }
}
