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
    @Published private(set) var preferenceHiddenAppIDs: Set<String>
    @Published private(set) var effectiveHiddenAppIDs: Set<String>
    @Published private(set) var isLoading = false
    @Published private(set) var inventoryReadiness:
        AppVisibilityInventoryReadiness = .idle
    @Published private(set) var query = ""
    @Published private(set) var queryProjectionGeneration: UInt64 = 0
    @Published private(set) var filter: Filter = .all
    @Published private(set) var filterProjectionGeneration: UInt64 = 0
    @Published private(set) var selectedAppID: String?
    @Published private(set) var selectionProjectionGeneration: UInt64 = 0
    @Published private(set) var homeContentRevision: UInt64 = 0

    private let inventoryService: any AppInventoryProviding
    private let userDefaults: UserDefaults
    private var reloadTask: Task<Void, Never>?
    private var requestedReloadGeneration: UInt64 = 0

    init(
        inventoryService: any AppInventoryProviding = AppInventoryService(),
        userDefaults: UserDefaults = .standard
    ) {
        self.inventoryService = inventoryService
        self.userDefaults = userDefaults
        let storedHiddenAppIDs = AppVisibilityPreferencesStore.loadHiddenAppIDs(
            userDefaults: userDefaults
        )
        preferenceHiddenAppIDs = storedHiddenAppIDs
        effectiveHiddenAppIDs = storedHiddenAppIDs
    }

    var hiddenAppIDs: Set<String> {
        preferenceHiddenAppIDs
    }

    var visibleApps: [InstalledAppRecord] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredApps = apps.enumerated().filter { _, app in
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
        effectiveHiddenAppIDs.count
    }

    var selectedApp: InstalledAppRecord? {
        guard let selectedAppID else { return nil }
        return apps.first { $0.id == selectedAppID }
    }

    func reload() {
        requestedReloadGeneration &+= 1
        inventoryReadiness = .loading
        isLoading = true
        startLatestReloadIfNeeded()
    }

    func refreshStoredPreferences() {
        let nextPreferenceHiddenAppIDs =
            AppVisibilityPreferencesStore.loadHiddenAppIDs(
                userDefaults: userDefaults
            )
        guard nextPreferenceHiddenAppIDs != preferenceHiddenAppIDs else { return }
        let previousEffectiveHiddenAppIDs = effectiveHiddenAppIDs
        preferenceHiddenAppIDs = nextPreferenceHiddenAppIDs
        recomputeEffectiveHiddenAppIDs()
        advanceHomeContentRevisionIfNeeded(
            inventoryChanged: false,
            previousEffectiveHiddenAppIDs: previousEffectiveHiddenAppIDs
        )
        resolveSelectionAfterReload()
    }

    func presentation(for app: InstalledAppRecord) -> AppVisibilityPresentation {
        app.visibilityPresentation(
            preferenceIsHidden: preferenceHiddenAppIDs.contains(app.id)
        )
    }

    private func startLatestReloadIfNeeded() {
        guard reloadTask == nil else { return }
        let reloadGeneration = requestedReloadGeneration
        let service = inventoryService
        reloadTask = Task { [weak self] in
            let records = await Task.detached(priority: .utility) {
                service.installedApps()
            }.value
            guard let self else { return }
            self.completeReload(records, generation: reloadGeneration)
        }
    }

    private func completeReload(
        _ records: [InstalledAppRecord],
        generation: UInt64
    ) {
        reloadTask = nil
        guard generation == requestedReloadGeneration else {
            startLatestReloadIfNeeded()
            return
        }

        let previousApps = apps
        let previousEffectiveHiddenAppIDs = effectiveHiddenAppIDs
        let preferenceConfigurableAppIDs = Set(
            records
                .filter { $0.visibilityCapability.isConfigurable }
                .map(\.id)
        )
        let reconciliation = AppVisibilityPreferencesStore.reconcileHiddenAppIDs(
            preferenceConfigurableAppIDs: preferenceConfigurableAppIDs,
            userDefaults: userDefaults
        )
        apps = records
        preferenceHiddenAppIDs = reconciliation.hiddenAppIDs
        recomputeEffectiveHiddenAppIDs()
        advanceHomeContentRevisionIfNeeded(
            inventoryChanged: previousApps != apps,
            previousEffectiveHiddenAppIDs: previousEffectiveHiddenAppIDs
        )
        resolveSelectionAfterReload()
        isLoading = false
        inventoryReadiness = .ready
        if reconciliation.didChange {
            NotificationCenter.default.post(
                name: .flowTabAppVisibilityPreferenceChanged,
                object: nil
            )
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
        guard let app = apps.first(where: { $0.id == appID }) else { return }
        guard app.visibilityCapability.isConfigurable else { return }
        let previousHiddenAppIDs = preferenceHiddenAppIDs
        AppVisibilityPreferencesStore.setAppHidden(
            hidden,
            appID: appID,
            userDefaults: userDefaults
        )
        preferenceHiddenAppIDs = AppVisibilityPreferencesStore.loadHiddenAppIDs(
            userDefaults: userDefaults
        )
        guard preferenceHiddenAppIDs != previousHiddenAppIDs else { return }
        let previousEffectiveHiddenAppIDs = effectiveHiddenAppIDs
        recomputeEffectiveHiddenAppIDs()
        advanceHomeContentRevisionIfNeeded(
            inventoryChanged: false,
            previousEffectiveHiddenAppIDs: previousEffectiveHiddenAppIDs
        )
        resolveSelectionAfterReload()
        NotificationCenter.default.post(name: .flowTabAppVisibilityPreferenceChanged, object: nil)
    }

    func isHidden(_ app: InstalledAppRecord) -> Bool {
        effectiveHiddenAppIDs.contains(app.id)
    }

    func isPreferenceHidden(_ app: InstalledAppRecord) -> Bool {
        preferenceHiddenAppIDs.contains(app.id)
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

    private func recomputeEffectiveHiddenAppIDs() {
        guard inventoryReadiness != .idle || !apps.isEmpty else {
            effectiveHiddenAppIDs = preferenceHiddenAppIDs
            return
        }
        let nextEffectiveHiddenAppIDs = Set(
            apps.compactMap { app in
                presentation(for: app).state.isEffectivelyHidden ? app.id : nil
            }
        )
        if effectiveHiddenAppIDs != nextEffectiveHiddenAppIDs {
            effectiveHiddenAppIDs = nextEffectiveHiddenAppIDs
        }
    }

    private func advanceHomeContentRevisionIfNeeded(
        inventoryChanged: Bool,
        previousEffectiveHiddenAppIDs: Set<String>
    ) {
        guard inventoryChanged
                || previousEffectiveHiddenAppIDs != effectiveHiddenAppIDs
        else {
            return
        }
        homeContentRevision &+= 1
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
