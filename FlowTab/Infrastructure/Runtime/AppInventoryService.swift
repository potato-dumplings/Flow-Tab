import AppKit
import Foundation
import FlowTabCore

struct InstalledAppRecord: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let bundleIdentifier: String?
    let path: String?
    let isRunning: Bool

    var subtitle: String {
        bundleIdentifier ?? path ?? id
    }

    static func unresolvedHiddenApp(id: String) -> InstalledAppRecord {
        InstalledAppRecord(
            id: id,
            displayName: unresolvedDisplayName(for: id),
            bundleIdentifier: id.hasPrefix("/") || id.hasPrefix("pid:") ? nil : id,
            path: id.hasPrefix("/") ? id : nil,
            isRunning: false
        )
    }

    private static func unresolvedDisplayName(for id: String) -> String {
        guard id.hasPrefix("/") else { return id }
        let filename = URL(fileURLWithPath: id).deletingPathExtension().lastPathComponent
        return filename.isEmpty ? id : filename
    }
}

final class AppInventoryService: @unchecked Sendable {
    private let fileManager: FileManager
    private let workspace: NSWorkspace

    init(
        fileManager: FileManager = .default,
        workspace: NSWorkspace = .shared
    ) {
        self.fileManager = fileManager
        self.workspace = workspace
    }

    func installedApps() -> [InstalledAppRecord] {
        var recordsByID: [String: InstalledAppRecord] = [:]

#if FLOWTAB_TESTING
        for record in uiTestRuntimeRecords() {
            recordsByID[record.id] = record
        }
#endif

        for record in runningAppRecords() {
            recordsByID[record.id] = record
        }

        for directory in applicationSearchDirectories() {
            for record in appRecords(in: directory) {
                recordsByID[record.id] = mergedRecord(existing: recordsByID[record.id], incoming: record)
            }
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
        return dataset.appSwitcherApps.map { app in
            InstalledAppRecord(
                id: app.id,
                displayName: app.displayName,
                bundleIdentifier: app.id.hasPrefix("pid:") ? nil : app.id,
                path: nil,
                isRunning: true
            )
        }
    }
#endif

    private func applicationSearchDirectories() -> [URL] {
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

    private func runningAppRecords() -> [InstalledAppRecord] {
        workspace.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, !app.isTerminated else { return nil }
            return runningAppRecord(for: app)
        }
    }

    private func runningAppRecord(for app: NSRunningApplication) -> InstalledAppRecord? {
        let appID = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        guard AppVisibilityFilter.normalizedAppID(appID) != nil else { return nil }
        let displayName = app.localizedName ?? appID
        return InstalledAppRecord(
            id: appID,
            displayName: displayName,
            bundleIdentifier: app.bundleIdentifier,
            path: app.bundleURL?.standardizedFileURL.path,
            isRunning: true
        )
    }

    private func installedAppRecord(for url: URL) -> InstalledAppRecord? {
        let standardizedURL = url.standardizedFileURL
        let bundle = Bundle(url: standardizedURL)
        let bundleIdentifier = bundle?.bundleIdentifier
        let appID = bundleIdentifier ?? standardizedURL.path
        guard AppVisibilityFilter.normalizedAppID(appID) != nil else { return nil }

        return InstalledAppRecord(
            id: appID,
            displayName: displayName(for: standardizedURL, bundle: bundle, appID: appID),
            bundleIdentifier: bundleIdentifier,
            path: standardizedURL.path,
            isRunning: false
        )
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
            isRunning: existing.isRunning || incoming.isRunning
        )
    }
}
