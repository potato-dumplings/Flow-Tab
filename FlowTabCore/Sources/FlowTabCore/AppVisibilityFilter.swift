import Foundation

public struct AppVisibilityFilter: Equatable, Sendable {
    public let hiddenAppIDs: Set<String>

    public init(hiddenAppIDs: Set<String>) {
        self.hiddenAppIDs = Set(Self.normalizedHiddenAppIDs(Array(hiddenAppIDs)))
    }

    public init(hiddenAppIDs: [String]) {
        self.hiddenAppIDs = Set(Self.normalizedHiddenAppIDs(hiddenAppIDs))
    }

    public var isEmpty: Bool {
        hiddenAppIDs.isEmpty
    }

    public func includes(appID: String) -> Bool {
        !isHidden(appID: appID)
    }

    public func isHidden(appID: String) -> Bool {
        guard let normalizedID = Self.normalizedAppID(appID) else { return false }
        return hiddenAppIDs.contains(normalizedID)
    }

    public func visibilitySortRank(appID: String) -> Int {
        isHidden(appID: appID) ? 1 : 0
    }

    public func filteredApps(_ apps: [AppSwitchCandidate]) -> [AppSwitchCandidate] {
        guard !hiddenAppIDs.isEmpty else { return apps }
        return apps.filter { includes(appID: $0.id) }
    }

    public static func normalizedHiddenAppIDs(_ rawIDs: [String]) -> [String] {
        Array(Set(rawIDs.compactMap(normalizedAppID))).sorted()
    }

    public static func normalizedAppID(_ rawID: String) -> String? {
        let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
