import Foundation

struct SystemAppMRURunningApplication: Equatable {
    let appID: String
    let pid: pid_t
    let launchDate: Date?
    let isCurrentProcess: Bool
}

enum SystemAppMRUMutationSource: String {
    case bootstrap
    case systemOrder = "system_order"
    case activation
    case launch
    case termination
    case discovery
}

enum SystemAppMRULegacyPersistence {
    private static let relativeDirectoryPathIntent = "FlowTab/runtime"

    static func removePersistedState(
        fileManager: FileManager = .default,
        applicationSupportDirectoryURL: URL? = nil,
        installationURL: URL = Bundle.main.bundleURL
    ) throws {
        let fallbackURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let resourceBoundary = applicationSupportDirectoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fallbackURL
        let directoryURL = resourceBoundary.appendingPathComponent(
            Self.relativeDirectoryPathIntent,
            isDirectory: true
        )
        let installationName = Self.fileNameComponent(
            installationURL.deletingPathExtension().lastPathComponent
        )
        let fileURL = directoryURL.appendingPathComponent(
            "system-app-mru-\(installationName).json",
            isDirectory: false
        )
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private static func fileNameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(String(scalar)) : "_"
        }
        let resolved = String(scalars)
        return resolved.isEmpty ? "FlowTab" : resolved
    }
}

struct SystemAppMRUState {
    private(set) var orderedAppIDs: [String]
    private(set) var generation: UInt64
    private(set) var isInitialized: Bool

    init() {
        orderedAppIDs = []
        generation = 0
        isInitialized = false
    }

    var requiresBootstrapFallback: Bool {
        !isInitialized
    }

    mutating func prepareForRanking(
        runningApplications: [SystemAppMRURunningApplication],
        frontmostAppID: String?,
        fallbackRankByPID: [pid_t: Int]
    ) -> SystemAppMRUMutationSource? {
        let eligibleApplications = runningApplications.filter { !$0.isCurrentProcess }
        let groupedApplications = Dictionary(grouping: eligibleApplications, by: \.appID)
        let runningAppIDs = Set(groupedApplications.keys)

        if !isInitialized {
            var seed: [String] = []
            if let frontmostAppID, runningAppIDs.contains(frontmostAppID) {
                seed.append(frontmostAppID)
            }
            seed.append(contentsOf: orderedAppIDs.filter(runningAppIDs.contains))
            seed.append(
                contentsOf: Self.sortedAppIDs(
                    groupedApplications,
                    fallbackRankByPID: fallbackRankByPID
                )
            )
            orderedAppIDs = Self.normalizedAppIDs(seed)
            isInitialized = true
            advanceGeneration()
            return .bootstrap
        }

        let knownAppIDs = Set(orderedAppIDs)
        let discoveredAppIDs = Self.sortedAppIDs(groupedApplications)
            .filter { !knownAppIDs.contains($0) }
        guard !discoveredAppIDs.isEmpty else { return nil }
        orderedAppIDs.append(contentsOf: discoveredAppIDs)
        advanceGeneration()
        return .discovery
    }

    mutating func reconcileSystemOrder(
        _ systemOrderedAppIDs: [String],
        runningApplications: [SystemAppMRURunningApplication]
    ) -> SystemAppMRUMutationSource? {
        let eligibleApplications = runningApplications.filter { !$0.isCurrentProcess }
        let groupedApplications = Dictionary(grouping: eligibleApplications, by: \.appID)
        let runningAppIDs = Set(groupedApplications.keys)
        var reconciled = Self.normalizedAppIDs(systemOrderedAppIDs)
            .filter { runningAppIDs.contains($0) }
        guard !reconciled.isEmpty else { return nil }

        var knownAppIDs = Set(reconciled)
        reconciled.append(
            contentsOf: orderedAppIDs.filter {
                runningAppIDs.contains($0) && knownAppIDs.insert($0).inserted
            }
        )
        reconciled.append(
            contentsOf: Self.sortedAppIDs(groupedApplications)
                .filter { knownAppIDs.insert($0).inserted }
        )

        let previousOrder = orderedAppIDs
        orderedAppIDs = reconciled
        isInitialized = true
        guard orderedAppIDs != previousOrder else { return nil }
        advanceGeneration()
        return .systemOrder
    }

    mutating func recordActivation(
        appID: String,
        isCurrentProcess: Bool
    ) -> SystemAppMRUMutationSource? {
        guard !isCurrentProcess, !appID.isEmpty else { return nil }
        let previousOrder = orderedAppIDs
        orderedAppIDs.removeAll { $0 == appID }
        orderedAppIDs.insert(appID, at: 0)
        guard isInitialized, orderedAppIDs != previousOrder else { return nil }
        advanceGeneration()
        return .activation
    }

    mutating func recordLaunch(
        appID: String,
        isCurrentProcess: Bool
    ) -> SystemAppMRUMutationSource? {
        guard !isCurrentProcess, !appID.isEmpty, !orderedAppIDs.contains(appID) else { return nil }
        orderedAppIDs.append(appID)
        guard isInitialized else { return nil }
        advanceGeneration()
        return .launch
    }

    mutating func recordTermination(
        appID: String,
        isCurrentProcess: Bool,
        hasRemainingProcess: Bool
    ) -> SystemAppMRUMutationSource? {
        guard !isCurrentProcess, !hasRemainingProcess else { return nil }
        let previousCount = orderedAppIDs.count
        orderedAppIDs.removeAll { $0 == appID }
        guard isInitialized, orderedAppIDs.count != previousCount else { return nil }
        advanceGeneration()
        return .termination
    }

    func rankByPID(
        for runningApplications: [SystemAppMRURunningApplication]
    ) -> [pid_t: Int] {
        let groupedApplications = Dictionary(grouping: runningApplications, by: \.appID)
        let runningAppIDs = Set(groupedApplications.keys)
        var activeOrder = orderedAppIDs.filter(runningAppIDs.contains)
        let orderedAppIDSet = Set(activeOrder)
        activeOrder.append(
            contentsOf: Self.sortedAppIDs(groupedApplications)
                .filter { !orderedAppIDSet.contains($0) }
        )
        let rankByAppID = Dictionary(
            uniqueKeysWithValues: activeOrder.enumerated().map { ($0.element, $0.offset) }
        )

        var rankByPID: [pid_t: Int] = [:]
        rankByPID.reserveCapacity(runningApplications.count)
        for app in runningApplications {
            rankByPID[app.pid] = rankByAppID[app.appID]
        }
        return rankByPID
    }

    var orderFingerprint: String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in orderedAppIDs.joined(separator: "\u{1f}").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private mutating func advanceGeneration() {
        generation &+= 1
    }

    private static func sortedAppIDs(
        _ groupedApplications: [String: [SystemAppMRURunningApplication]],
        fallbackRankByPID: [pid_t: Int] = [:]
    ) -> [String] {
        groupedApplications.keys.sorted { lhs, rhs in
            let lhsApps = groupedApplications[lhs] ?? []
            let rhsApps = groupedApplications[rhs] ?? []
            let lhsFallbackRank = lhsApps.compactMap { fallbackRankByPID[$0.pid] }.min() ?? Int.max
            let rhsFallbackRank = rhsApps.compactMap { fallbackRankByPID[$0.pid] }.min() ?? Int.max
            if lhsFallbackRank != rhsFallbackRank {
                return lhsFallbackRank < rhsFallbackRank
            }
            let lhsLaunchDate = lhsApps.compactMap(\.launchDate).max() ?? Date.distantPast
            let rhsLaunchDate = rhsApps.compactMap(\.launchDate).max() ?? Date.distantPast
            if lhsLaunchDate != rhsLaunchDate {
                return lhsLaunchDate > rhsLaunchDate
            }
            return lhs < rhs
        }
    }

    private static func normalizedAppIDs(_ appIDs: [String]) -> [String] {
        var seen: Set<String> = []
        return appIDs.compactMap { rawAppID in
            let appID = rawAppID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !appID.isEmpty, seen.insert(appID).inserted else { return nil }
            return appID
        }
    }
}
