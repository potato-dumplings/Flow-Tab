import Foundation
import FlowTabCore

enum AppVisibilityInventoryReadiness: String, Equatable {
    case idle
    case loading
    case ready

    var accessibilityIdentifier: String {
        "flowtab.settings.app-visibility.inventory.\(rawValue)"
    }
}

enum AppVisibilityQueryProjectionAccessibility {
    static let identifierPrefix =
        "flowtab.settings.app-visibility.list.query-generation."

    static func identifier(generation: UInt64) -> String {
        "\(identifierPrefix)\(generation)"
    }
}

enum AppVisibilityFilterProjectionAccessibility {
    static let identifierPrefix =
        "flowtab.settings.app-visibility.filter-projection."

    static func identifier(
        filterRawValue: String,
        generation: UInt64
    ) -> String {
        "\(identifierPrefix)\(filterRawValue).generation.\(generation)"
    }
}

enum AppVisibilityDetailProjectionAccessibility {
    static let identifierPrefix =
        "flowtab.settings.app-visibility.detail."

    static func identifierPrefix(appID: String) -> String {
        "\(identifierPrefix)\(appID.flowTabAccessibilityIdentifierComponent).generation."
    }

    static func identifier(appID: String, generation: UInt64) -> String {
        "\(identifierPrefix(appID: appID))\(generation)"
    }
}

@MainActor
final class AppVisibilityManagerModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all
        case hidden
        case running

        var id: String { rawValue }

        func title(language: AppLanguage) -> String {
            switch self {
            case .all:
                return AppStrings.text(.appVisibilityFilterAll, language: language)
            case .hidden:
                return AppStrings.text(.appVisibilityFilterHidden, language: language)
            case .running:
                return AppStrings.text(.appVisibilityFilterRunning, language: language)
            }
        }
    }

    @Published private(set) var apps: [InstalledAppRecord] = []
    @Published private(set) var hiddenAppIDs: Set<String>
    @Published private(set) var isLoading = false
    @Published private(set) var inventoryReadiness:
        AppVisibilityInventoryReadiness = .idle
    @Published private(set) var query = ""
    @Published private(set) var queryProjectionGeneration: UInt64 = 0
    @Published private(set) var filter: Filter = .all
    @Published private(set) var filterProjectionGeneration: UInt64 = 0
    @Published private(set) var selectedAppID: String?
    @Published private(set) var selectionProjectionGeneration: UInt64 = 0

    private let inventoryService: AppInventoryService
    private let userDefaults: UserDefaults
    private var reloadTask: Task<Void, Never>?

    init(
        inventoryService: AppInventoryService = AppInventoryService(),
        userDefaults: UserDefaults = .standard
    ) {
        self.inventoryService = inventoryService
        self.userDefaults = userDefaults
        hiddenAppIDs = AppVisibilityPreferencesStore.loadHiddenAppIDs(userDefaults: userDefaults)
    }

    var visibleApps: [InstalledAppRecord] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredApps = managedApps.enumerated().filter { _, app in
            matchesFilter(app)
        }
        guard !trimmedQuery.isEmpty else {
            return filteredApps.map(\.element)
        }

        let searchKey = SearchTextMatcher.buildKey(from: trimmedQuery)
        return filteredApps.compactMap { offset, app -> (app: InstalledAppRecord, score: Int, order: Int)? in
            guard let score = matchScore(query: searchKey, rawQuery: trimmedQuery, app: app) else {
                return nil
            }
            return (app, score, offset)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score < rhs.score
            }
            return lhs.order < rhs.order
        }
        .map(\.app)
    }

    var hiddenCount: Int {
        hiddenAppIDs.count
    }

    var selectedApp: InstalledAppRecord? {
        guard let selectedAppID else { return nil }
        return managedApps.first { $0.id == selectedAppID }
    }

    func reload() {
        guard reloadTask == nil else { return }
        inventoryReadiness = .loading
        isLoading = true
        let service = inventoryService
        reloadTask = Task { [weak self] in
            let records = await Task.detached(priority: .utility) {
                service.installedApps()
            }.value

            await MainActor.run {
                guard let self else { return }
                self.apps = records
                self.hiddenAppIDs = AppVisibilityPreferencesStore.loadHiddenAppIDs(
                    userDefaults: self.userDefaults
                )
                self.resolveSelectionAfterReload()
                self.isLoading = false
                self.inventoryReadiness = .ready
                self.reloadTask = nil
            }
        }
    }

    func updateQuery(_ query: String) {
        guard self.query != query else { return }
        self.query = query
        queryProjectionGeneration &+= 1
    }

    func updateFilter(_ filter: Filter) {
        guard self.filter != filter else { return }
        self.filter = filter
        filterProjectionGeneration &+= 1
    }

    func selectApp(_ appID: String?) {
        guard selectedAppID != appID else { return }
        selectedAppID = appID
        selectionProjectionGeneration &+= 1
    }

    func setHidden(_ hidden: Bool, for appID: String) {
        AppVisibilityPreferencesStore.setAppHidden(
            hidden,
            appID: appID,
            userDefaults: userDefaults
        )
        hiddenAppIDs = AppVisibilityPreferencesStore.loadHiddenAppIDs(userDefaults: userDefaults)
        resolveSelectionAfterReload()
        NotificationCenter.default.post(name: .flowTabAppVisibilityPreferenceChanged, object: nil)
    }

    func isHidden(_ app: InstalledAppRecord) -> Bool {
        hiddenAppIDs.contains(app.id)
    }

    private var managedApps: [InstalledAppRecord] {
        guard !hiddenAppIDs.isEmpty else { return apps }

        let appIDs = Set(apps.map(\.id))
        let unresolvedHiddenApps = hiddenAppIDs
            .filter { !appIDs.contains($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map(InstalledAppRecord.unresolvedHiddenApp)
        return apps + unresolvedHiddenApps
    }

    private func resolveSelectionAfterReload() {
        let visible = visibleApps
        if let selectedAppID, visible.contains(where: { $0.id == selectedAppID }) {
            return
        }
        selectApp(visible.first?.id)
    }

    private func matchesFilter(_ app: InstalledAppRecord) -> Bool {
        switch filter {
        case .all:
            return true
        case .hidden:
            return isHidden(app)
        case .running:
            return app.isRunning
        }
    }

    private func matchScore(
        query: SearchTextMatcher.Key,
        rawQuery: String,
        app: InstalledAppRecord
    ) -> Int? {
        let identifier = app.bundleIdentifier ?? app.id
        let index = SearchTextMatcher.buildIndex(for: app.displayName, identifier: identifier)
        let appScore = SearchTextMatcher.matchScore(query: query, in: index)
        return SearchTextMatcher.bestScore(appScore, pathMatchScore(rawQuery, app: app))
    }

    private func pathMatchScore(_ query: String, app: InstalledAppRecord) -> Int? {
        guard let path = app.path else { return nil }
        guard let range = path.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }
        let distance = path.distance(from: path.startIndex, to: range.lowerBound)
        return 200 + distance
    }
}
