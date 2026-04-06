import AppKit
import ApplicationServices
import Foundation

extension RuntimeSnapshotProvider {
    private static let offSpaceSupplementMinimumArea: CGFloat = 450_000
    private static let offSpaceSupplementAreaRatio: CGFloat = 0.55
    private static let offSpaceSupplementMaxCount: Int = 8
    private static let offSpaceSupplementAlphaThreshold: Double = 0.001
    private static let standardBufferedStoreType: Int = 1

    static func makeCGWindowID(pid: pid_t, cgWindowID: CGWindowID) -> String {
        "cg:\(pid):\(cgWindowID)"
    }

    func appendOffSpaceCGWindows(
        to entries: [WindowListEntry],
        appName: String,
        pid: pid_t,
        allCGWindows: [CGWindowEntry]
    ) -> [WindowListEntry] {
        let supplementalWindows = selectSupplementalOffSpaceCGWindows(
            existingCGWindowIDs: Set(entries.compactMap(\.cgWindowID)),
            allCGWindows: allCGWindows
        )
        guard !supplementalWindows.isEmpty else { return entries }

        var mergedEntries = entries
        var remainingSupplementalWindows = supplementalWindows
        var backfilledEntryCount = 0
        let backfillTargetIndexes = supplementalBackfillTargetIndexes(
            in: mergedEntries,
            appName: appName
        )
        if !backfillTargetIndexes.isEmpty {
            let backfillCount = min(backfillTargetIndexes.count, remainingSupplementalWindows.count)
            for offset in 0..<backfillCount {
                let entryIndex = backfillTargetIndexes[offset]
                let supplementalWindow = remainingSupplementalWindows[offset]
                var title = mergedEntries[entryIndex].title
                if isAppNameFallbackTitle(title, appName: appName),
                    let supplementalTitle = normalizedWindowTitle(supplementalWindow.title)
                {
                    title = supplementalTitle
                }
                mergedEntries[entryIndex] = WindowListEntry(
                    windowID: mergedEntries[entryIndex].windowID,
                    title: title,
                    isMinimized: mergedEntries[entryIndex].isMinimized,
                    cgWindowID: supplementalWindow.id,
                    axWindow: mergedEntries[entryIndex].axWindow
                )
                backfilledEntryCount += 1
            }
            remainingSupplementalWindows.removeFirst(backfillCount)
        }

        var explicitTitleCount = 0
        var appNameFallbackCount = 0
        let supplementalEntries: [WindowListEntry] = remainingSupplementalWindows.map { cgWindow in
            let title = resolvedTitleForSupplementalCGWindow(
                appName: appName,
                cgWindow: cgWindow
            )
            if normalizedWindowTitle(cgWindow.title) == nil {
                appNameFallbackCount += 1
            } else {
                explicitTitleCount += 1
            }
            return WindowListEntry(
                windowID: Self.makeCGWindowID(pid: pid, cgWindowID: cgWindow.id),
                title: title,
                isMinimized: false,
                cgWindowID: cgWindow.id,
                axWindow: nil
            )
        }
        RuntimeLog.info(
            "AX",
            "\(appName) supplementalCGWindows=\(supplementalEntries.count) explicitTitles=\(explicitTitleCount) appNameFallbacks=\(appNameFallbackCount) backfilledAXEntries=\(backfilledEntryCount)"
        )
        return mergedEntries + supplementalEntries
    }

    func selectSupplementalOffSpaceCGWindows(
        existingCGWindowIDs: Set<CGWindowID>,
        allCGWindows: [CGWindowEntry]
    ) -> [CGWindowEntry] {
        guard !allCGWindows.isEmpty else { return [] }

        let referenceArea = allCGWindows
            .filter(\.isOnscreen)
            .compactMap { Self.windowArea($0.bounds) }
            .max() ?? 0
        let minimumArea = max(
            Self.offSpaceSupplementMinimumArea,
            referenceArea * Self.offSpaceSupplementAreaRatio
        )

        let candidates = allCGWindows.filter { window in
            // AX can miss large top-level windows that remain in the current space,
            // so supplement from unmatched CG windows whether they are on-screen or off-space.
            guard !existingCGWindowIDs.contains(window.id) else { return false }
            guard window.alpha > Self.offSpaceSupplementAlphaThreshold else { return false }
            guard window.storeType == Self.standardBufferedStoreType else { return false }
            guard let area = Self.windowArea(window.bounds) else { return false }
            return area >= minimumArea
        }
        guard !candidates.isEmpty else { return [] }

        let sorted = candidates.sorted { lhs, rhs in
            let lhsArea = Self.windowArea(lhs.bounds) ?? 0
            let rhsArea = Self.windowArea(rhs.bounds) ?? 0
            if lhsArea == rhsArea {
                return lhs.id > rhs.id
            }
            return lhsArea > rhsArea
        }
        return Array(sorted.prefix(Self.offSpaceSupplementMaxCount))
    }

    static func supplementalCGWindowIDsForTesting(
        existingCGWindowIDs: Set<CGWindowID>,
        allCGWindows: [CGWindowEntryForTesting]
    ) -> [CGWindowID] {
        let provider = RuntimeSnapshotProvider()
        let windows = allCGWindows.map {
            CGWindowEntry(
                id: $0.id,
                title: $0.title,
                bounds: $0.bounds,
                isOnscreen: $0.isOnscreen,
                alpha: $0.alpha,
                storeType: $0.storeType
            )
        }
        return provider.selectSupplementalOffSpaceCGWindows(
            existingCGWindowIDs: existingCGWindowIDs,
            allCGWindows: windows
        ).map(\.id)
    }

    static func supplementalCGWindowTitleForTesting(
        appName: String,
        cgWindow: CGWindowEntryForTesting,
        cachedAXTitlesByCGWindowID: [CGWindowID: String] = [:]
    ) -> String {
        _ = cachedAXTitlesByCGWindowID
        return RuntimeSnapshotProvider().resolvedTitleForSupplementalCGWindow(
            appName: appName,
            cgWindow: CGWindowEntry(
                id: cgWindow.id,
                title: cgWindow.title,
                bounds: cgWindow.bounds,
                isOnscreen: cgWindow.isOnscreen,
                alpha: cgWindow.alpha,
                storeType: cgWindow.storeType
            )
        )
    }

    struct SupplementalMergeEntryForTesting {
        let windowID: String
        let title: String
        let isMinimized: Bool
        let cgWindowID: CGWindowID?
    }

    static func appendOffSpaceCGWindowsForTesting(
        entries: [SupplementalMergeEntryForTesting],
        appName: String,
        pid: pid_t,
        allCGWindows: [CGWindowEntryForTesting]
    ) -> [SupplementalMergeEntryForTesting] {
        let provider = RuntimeSnapshotProvider()
        let mergedEntries = provider.appendOffSpaceCGWindows(
            to: entries.map {
                WindowListEntry(
                    windowID: $0.windowID,
                    title: $0.title,
                    isMinimized: $0.isMinimized,
                    cgWindowID: $0.cgWindowID,
                    axWindow: nil
                )
            },
            appName: appName,
            pid: pid,
            allCGWindows: allCGWindows.map {
                CGWindowEntry(
                    id: $0.id,
                    title: $0.title,
                    bounds: $0.bounds,
                    isOnscreen: $0.isOnscreen,
                    alpha: $0.alpha,
                    storeType: $0.storeType
                )
            }
        )
        return mergedEntries.map {
            SupplementalMergeEntryForTesting(
                windowID: $0.windowID,
                title: $0.title,
                isMinimized: $0.isMinimized,
                cgWindowID: $0.cgWindowID
            )
        }
    }

    private static func windowArea(_ bounds: CGRect?) -> CGFloat? {
        guard let bounds else { return nil }
        let standardized = bounds.standardized
        guard standardized.width > 0, standardized.height > 0 else { return nil }
        return standardized.width * standardized.height
    }

    private func resolvedTitleForSupplementalCGWindow(
        appName: String,
        cgWindow: CGWindowEntry
    ) -> String {
        normalizedWindowTitle(cgWindow.title)
            ?? normalizedWindowTitle(appName)
            ?? appName
    }

    private func normalizedWindowTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isAppNameFallbackTitle(_ title: String, appName: String) -> Bool {
        guard let normalizedTitle = normalizedWindowTitle(title) else { return false }
        guard let normalizedAppName = normalizedWindowTitle(appName) else { return false }
        return normalizedTitle.caseInsensitiveCompare(normalizedAppName) == .orderedSame
    }

    private func supplementalBackfillTargetIndexes(
        in entries: [WindowListEntry],
        appName: String
    ) -> [Int] {
        let unresolvedIndexes = entries.indices.filter { entries[$0].cgWindowID == nil }
        let fallbackTitleIndexes = entries.indices.filter { index in
            guard entries[index].cgWindowID != nil else { return false }
            return isAppNameFallbackTitle(entries[index].title, appName: appName)
        }
        return unresolvedIndexes + fallbackTitleIndexes
    }
}
