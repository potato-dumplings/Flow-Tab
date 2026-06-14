import Foundation

enum SpaceFixtureWindowMode: String, Codable, Equatable {
    case standard
    case fullscreen
}

enum SpaceFixtureLaunchConfigurationError: LocalizedError, Equatable {
    case missingWorkflowConfigPath
    case missingWorkflowAppID
    case workflowFileNotFound(String)
    case workflowFileUnreadable(String)
    case workflowFileInvalid(String)
    case workflowAppNotFound(String)
    case workflowAppHasNoWindows(String)

    var errorDescription: String? {
        switch self {
        case .missingWorkflowConfigPath:
            return "Missing --workflow-config when selecting a workflow app."
        case .missingWorkflowAppID:
            return "Missing --workflow-app-id when selecting a workflow configuration."
        case let .workflowFileNotFound(path):
            return "Workflow configuration file was not found: \(path)"
        case let .workflowFileUnreadable(path):
            return "Workflow configuration file could not be read: \(path)"
        case let .workflowFileInvalid(path):
            return "Workflow configuration file is invalid JSON: \(path)"
        case let .workflowAppNotFound(appID):
            return "Workflow configuration does not contain appID: \(appID)"
        case let .workflowAppHasNoWindows(appID):
            return "Workflow app \(appID) does not define any windows."
        }
    }
}

struct SpaceFixtureWorkflowConfiguration: Codable, Equatable {
    let workflowName: String
    let settleTimeoutMilliseconds: Int?
    let apps: [SpaceFixtureWorkflowAppConfiguration]

    enum CodingKeys: String, CodingKey {
        case workflowName
        case settleTimeoutMilliseconds = "settleTimeoutMs"
        case apps
    }

    static func load(from url: URL) throws -> SpaceFixtureWorkflowConfiguration {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(SpaceFixtureWorkflowConfiguration.self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw SpaceFixtureLaunchConfigurationError.workflowFileNotFound(url.path)
        } catch is CocoaError {
            throw SpaceFixtureLaunchConfigurationError.workflowFileUnreadable(url.path)
        } catch is DecodingError {
            throw SpaceFixtureLaunchConfigurationError.workflowFileInvalid(url.path)
        } catch {
            throw SpaceFixtureLaunchConfigurationError.workflowFileUnreadable(url.path)
        }
    }

    func appConfiguration(for appID: String) -> SpaceFixtureWorkflowAppConfiguration? {
        let normalizedID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        return apps.first {
            $0.appID.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedID
        }
    }
}

struct SpaceFixtureWorkflowAppConfiguration: Codable, Equatable {
    let appID: String
    let appName: String
    let bundleIdentifier: String
    let appPath: String?
    let launchOrder: Int
    let windows: [SpaceFixtureWorkflowWindowConfiguration]

    enum CodingKeys: String, CodingKey {
        case appID
        case appName
        case bundleId
        case appPath
        case launchOrder
        case windows
    }

    init(
        appID: String,
        appName: String,
        bundleIdentifier: String,
        appPath: String?,
        launchOrder: Int,
        windows: [SpaceFixtureWorkflowWindowConfiguration]
    ) {
        self.appID = appID
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.appPath = appPath
        self.launchOrder = launchOrder
        self.windows = windows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            appID: try container.decode(String.self, forKey: .appID),
            appName: try container.decode(String.self, forKey: .appName),
            bundleIdentifier: try container.decode(String.self, forKey: .bundleId),
            appPath: try container.decodeIfPresent(String.self, forKey: .appPath),
            launchOrder: try container.decodeIfPresent(Int.self, forKey: .launchOrder) ?? 0,
            windows: try container.decode([SpaceFixtureWorkflowWindowConfiguration].self, forKey: .windows)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appID, forKey: .appID)
        try container.encode(appName, forKey: .appName)
        try container.encode(bundleIdentifier, forKey: .bundleId)
        try container.encodeIfPresent(appPath, forKey: .appPath)
        try container.encode(launchOrder, forKey: .launchOrder)
        try container.encode(windows, forKey: .windows)
    }
}

struct SpaceFixtureWorkflowWindowConfiguration: Codable, Equatable {
    let title: String
    let mode: SpaceFixtureWindowMode
    let tabs: [SpaceFixtureWorkflowTabConfiguration]
    let noisyCGSiblings: Bool
    let publishesApplicationAXWindow: Bool
    let suppressesWindowAccessibilityExposure: Bool

    enum CodingKeys: String, CodingKey {
        case title
        case mode
        case tabs
        case noisyCGSiblings
        case publishesApplicationAXWindow
        case suppressesWindowAccessibilityExposure
    }

    init(
        title: String,
        mode: SpaceFixtureWindowMode,
        tabs: [SpaceFixtureWorkflowTabConfiguration],
        noisyCGSiblings: Bool = false,
        publishesApplicationAXWindow: Bool = true,
        suppressesWindowAccessibilityExposure: Bool = false
    ) {
        self.title = title
        self.mode = mode
        self.tabs = tabs
        self.noisyCGSiblings = noisyCGSiblings
        self.publishesApplicationAXWindow = publishesApplicationAXWindow
        self.suppressesWindowAccessibilityExposure = suppressesWindowAccessibilityExposure
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
            mode: try container.decodeIfPresent(SpaceFixtureWindowMode.self, forKey: .mode) ?? .standard,
            tabs: try container.decodeIfPresent([SpaceFixtureWorkflowTabConfiguration].self, forKey: .tabs) ?? [],
            noisyCGSiblings: try container.decodeIfPresent(Bool.self, forKey: .noisyCGSiblings) ?? false,
            publishesApplicationAXWindow: try container.decodeIfPresent(
                Bool.self,
                forKey: .publishesApplicationAXWindow
            ) ?? true,
            suppressesWindowAccessibilityExposure: try container.decodeIfPresent(
                Bool.self,
                forKey: .suppressesWindowAccessibilityExposure
            ) ?? false
        )
    }
}

struct SpaceFixtureWorkflowTabConfiguration: Codable, Equatable {
    let title: String
    let isSelected: Bool
    let identifier: String?

    enum CodingKeys: String, CodingKey {
        case title
        case isSelected
        case identifier
    }

    init(
        title: String,
        isSelected: Bool,
        identifier: String?
    ) {
        self.title = title
        self.isSelected = isSelected
        self.identifier = identifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
            isSelected: try container.decodeIfPresent(Bool.self, forKey: .isSelected) ?? false,
            identifier: try container.decodeIfPresent(String.self, forKey: .identifier)
        )
    }
}
