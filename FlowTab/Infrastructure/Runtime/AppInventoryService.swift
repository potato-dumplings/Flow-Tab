import AppKit
import Foundation
import FlowTabCore

struct InstalledAppRecord: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let bundleIdentifier: String?
    let path: String?
    let isRunning: Bool
    let visibilityCapability: AppVisibilityCapability

    init(
        id: String,
        displayName: String,
        bundleIdentifier: String?,
        path: String?,
        isRunning: Bool,
        visibilityCapability: AppVisibilityCapability = .configurable
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.isRunning = isRunning
        self.visibilityCapability = visibilityCapability
    }

    var subtitle: String {
        bundleIdentifier ?? path ?? id
    }

}

protocol AppInventoryProviding: Sendable {
    func installedApps() -> [InstalledAppRecord]
}

final class AppInventoryService: AppInventoryProviding, @unchecked Sendable {
    private let fileManager: FileManager
    private let workspace: NSWorkspace
    private let searchDirectoriesOverride: [URL]?

    init(
        fileManager: FileManager = .default,
        workspace: NSWorkspace = .shared,
        searchDirectories: [URL]? = nil
    ) {
        self.fileManager = fileManager
        self.workspace = workspace
        searchDirectoriesOverride = searchDirectories
    }

    func installedApps() -> [InstalledAppRecord] {
        var recordsByID: [String: InstalledAppRecord] = [:]

        for directory in applicationSearchDirectories() {
            for record in appRecords(in: directory) {
                recordsByID[record.id] = mergedRecord(existing: recordsByID[record.id], incoming: record)
            }
        }

#if FLOWTAB_TESTING
        for record in uiTestRuntimeRecords() {
            recordsByID[record.id] = mergedRecord(existing: recordsByID[record.id], incoming: record)
        }
#endif

        for app in workspace.runningApplications {
            let appID = RuntimeAppIdentity.appID(for: app)
            let bundleSource: ApplicationBundleSource = recordsByID[appID] == nil
                ? .none
                : .standardApplicationsDirectory
            guard let record = runningAppRecord(for: app, bundleSource: bundleSource) else {
                continue
            }
            recordsByID[record.id] = mergedRecord(
                existing: recordsByID[record.id],
                incoming: record
            )
        }

        return recordsByID.values.sorted { lhs, rhs in
            let nameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
    }

#if FLOWTAB_TESTING
    private func uiTestRuntimeRecords() -> [InstalledAppRecord] {
        guard let dataset = FlowTabUITestRuntimeProjectionDataset.current() else { return [] }
        var records = dataset.appSwitcherApps.map { app in
            InstalledAppRecord(
                id: app.id,
                displayName: app.displayName,
                bundleIdentifier: app.id.hasPrefix("pid:") ? nil : app.id,
                path: nil,
                isRunning: true
            )
        }
        if FlowTabTestLaunchOptions.mockRuntimeVariant
            == FlowTabUITestAppVisibilityIdentityFixture.variant {
            records.append(
                InstalledAppRecord(
                    id: FlowTabUITestAppVisibilityIdentityFixture.systemManagedAppID,
                    displayName: "Identity Menu Bar",
                    bundleIdentifier: FlowTabUITestAppVisibilityIdentityFixture.systemManagedAppID,
                    path: "/Applications/Identity Menu Bar.app",
                    isRunning: true,
                    visibilityCapability: .systemManaged(reason: .macOSRuntimeMode)
                )
            )
        }
        return records
    }
#endif

    private func applicationSearchDirectories() -> [URL] {
        if let searchDirectoriesOverride {
            return uniqueDirectories(searchDirectoriesOverride)
        }
        var directories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true)
        ]

        if let userApplications = fileManager.urls(
            for: .applicationDirectory,
            in: .userDomainMask
        ).first {
            directories.append(userApplications)
        }

        return uniqueDirectories(directories)
    }

    private func uniqueDirectories(_ directories: [URL]) -> [URL] {
        var seenPaths: Set<String> = []
        return directories.filter { directory in
            let path = directory.standardizedFileURL.path
            guard !seenPaths.contains(path) else { return false }
            seenPaths.insert(path)
            return true
        }
    }

    private func appRecords(in directory: URL) -> [InstalledAppRecord] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .localizedNameKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var records: [InstalledAppRecord] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
            if let record = installedAppRecord(for: url) {
                records.append(record)
            }
        }
        return records
    }

    private func runningAppRecord(
        for app: NSRunningApplication,
        bundleSource: ApplicationBundleSource
    ) -> InstalledAppRecord? {
        let appID = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        guard AppVisibilityFilter.normalizedAppID(appID) != nil else { return nil }
        let bundle = app.bundleURL.flatMap(Bundle.init(url:))
        let decision = ApplicationIdentityPolicy.decision(
            for: ApplicationIdentityFacts(
                isCurrentProcess:
                    app.processIdentifier == ProcessInfo.processInfo.processIdentifier,
                isTerminated: app.isTerminated,
                runtimeActivationPolicy: app.activationPolicy.flowTabCorePolicy,
                bundleSource: bundleSource,
                isUIElement: bundleFlag("LSUIElement", bundle: bundle),
                isBackgroundOnly: bundleFlag("LSBackgroundOnly", bundle: bundle)
            )
        )
        guard let visibilityCapability = decision.visibilityCapability else { return nil }
        let displayName = app.localizedName ?? appID
        return InstalledAppRecord(
            id: appID,
            displayName: displayName,
            bundleIdentifier: app.bundleIdentifier,
            path: app.bundleURL?.standardizedFileURL.path,
            isRunning: true,
            visibilityCapability: visibilityCapability
        )
    }

    private func installedAppRecord(for url: URL) -> InstalledAppRecord? {
        let standardizedURL = url.standardizedFileURL
        let bundle = Bundle(url: standardizedURL)
        let bundleIdentifier = bundle?.bundleIdentifier
        let appID = bundleIdentifier ?? standardizedURL.path
        guard AppVisibilityFilter.normalizedAppID(appID) != nil else { return nil }
        let decision = ApplicationIdentityPolicy.decision(
            for: ApplicationIdentityFacts(
                isCurrentProcess: false,
                isTerminated: false,
                runtimeActivationPolicy: nil,
                bundleSource: .standardApplicationsDirectory,
                isUIElement: bundleFlag("LSUIElement", bundle: bundle),
                isBackgroundOnly: bundleFlag("LSBackgroundOnly", bundle: bundle)
            )
        )
        guard let visibilityCapability = decision.visibilityCapability else { return nil }

        return InstalledAppRecord(
            id: appID,
            displayName: displayName(for: standardizedURL, bundle: bundle, appID: appID),
            bundleIdentifier: bundleIdentifier,
            path: standardizedURL.path,
            isRunning: false,
            visibilityCapability: visibilityCapability
        )
    }

    private func bundleFlag(_ key: String, bundle: Bundle?) -> Bool {
        let value = bundle?.infoDictionary?[key]
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.boolValue
        }
        if let stringValue = value as? String {
            return NSString(string: stringValue).boolValue
        }
        return false
    }

    private func displayName(for url: URL, bundle: Bundle?, appID: String) -> String {
        let infoDictionary = bundle?.localizedInfoDictionary ?? bundle?.infoDictionary
        if let displayName = infoDictionary?["CFBundleDisplayName"] as? String, !displayName.isEmpty {
            return displayName
        }
        if let bundleName = infoDictionary?["CFBundleName"] as? String, !bundleName.isEmpty {
            return bundleName
        }
        let filename = url.deletingPathExtension().lastPathComponent
        return filename.isEmpty ? appID : filename
    }

    private func mergedRecord(
        existing: InstalledAppRecord?,
        incoming: InstalledAppRecord
    ) -> InstalledAppRecord {
        guard let existing else { return incoming }
        return InstalledAppRecord(
            id: existing.id,
            displayName: existing.displayName.isEmpty ? incoming.displayName : existing.displayName,
            bundleIdentifier: existing.bundleIdentifier ?? incoming.bundleIdentifier,
            path: existing.path ?? incoming.path,
            isRunning: existing.isRunning || incoming.isRunning,
            visibilityCapability: incoming.visibilityCapability
        )
    }
}
