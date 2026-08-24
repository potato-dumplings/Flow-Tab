public enum ApplicationRuntimeActivationPolicy: Equatable, Hashable, Sendable {
    case regular
    case accessory
    case prohibited
}

public enum ApplicationBundleSource: Equatable, Sendable {
    case none
    case standardApplicationsDirectory
}

public enum AppVisibilityUnavailableReason: Equatable, Sendable {
    case staticBundleDeclaration
}

public enum AppVisibilityCapability: Equatable, Sendable {
    case configurable
    case systemManaged(reason: AppVisibilityUnavailableReason)

    public var isConfigurable: Bool {
        self == .configurable
    }

    public var unavailableReason: AppVisibilityUnavailableReason? {
        guard case let .systemManaged(reason) = self else { return nil }
        return reason
    }
}

public enum ApplicationDirectoryDecision: Equatable, Sendable {
    case excluded
    case included(visibilityCapability: AppVisibilityCapability)

    public var visibilityCapability: AppVisibilityCapability? {
        guard case let .included(visibilityCapability) = self else { return nil }
        return visibilityCapability
    }

    public var isIncluded: Bool {
        visibilityCapability != nil
    }
}

public struct ApplicationIdentityFacts: Equatable, Sendable {
    public let isCurrentProcess: Bool
    public let isTerminated: Bool
    public let runtimeActivationPolicy: ApplicationRuntimeActivationPolicy?
    public let bundleSource: ApplicationBundleSource
    public let isUIElement: Bool
    public let isBackgroundOnly: Bool

    public init(
        isCurrentProcess: Bool,
        isTerminated: Bool,
        runtimeActivationPolicy: ApplicationRuntimeActivationPolicy?,
        bundleSource: ApplicationBundleSource,
        isUIElement: Bool,
        isBackgroundOnly: Bool
    ) {
        self.isCurrentProcess = isCurrentProcess
        self.isTerminated = isTerminated
        self.runtimeActivationPolicy = runtimeActivationPolicy
        self.bundleSource = bundleSource
        self.isUIElement = isUIElement
        self.isBackgroundOnly = isBackgroundOnly
    }
}

public enum ApplicationIdentityPolicy {
    public static func decision(
        for facts: ApplicationIdentityFacts
    ) -> ApplicationDirectoryDecision {
        guard !facts.isTerminated else { return .excluded }

        if facts.isCurrentProcess {
            return .included(visibilityCapability: .configurable)
        }

        if facts.bundleSource == .standardApplicationsDirectory {
            if facts.isUIElement || facts.isBackgroundOnly {
                return .included(
                    visibilityCapability: .systemManaged(
                        reason: .staticBundleDeclaration
                    )
                )
            }
            return .included(visibilityCapability: .configurable)
        }

        guard facts.runtimeActivationPolicy == .regular else {
            return .excluded
        }
        return .included(visibilityCapability: .configurable)
    }
}
