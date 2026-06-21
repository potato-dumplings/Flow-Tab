import CoreGraphics
import Foundation

enum RuntimeWindowListDeduplicator {
    static func suppressUnmatchedEntriesCoveredByStickySpace(
        _ entries: [RuntimeWindowListEntry],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String
    ) -> [RuntimeWindowListEntry] {
        let stickySpaceKeys = Set(entries.compactMap { entry -> String? in
            guard
                entry.hasStickyBinding,
                let cgWindowID = entry.cgWindowID
            else {
                return nil
            }
            let rawSpaceIDs = knownCGWindowsByID[cgWindowID]?.spaceIDs ?? []
            let normalizedSpaceIDs = RuntimeWindowTopologyClassifier.normalizedSpaceIDs(rawSpaceIDs)
            guard !normalizedSpaceIDs.isEmpty else { return nil }
            return spaceKey(for: normalizedSpaceIDs)
        })

        var deduplicatedEntries: [RuntimeWindowListEntry] = []
        deduplicatedEntries.reserveCapacity(entries.count)
        var droppedCount = 0

        for entry in entries {
            guard let cgWindowID = entry.cgWindowID else {
                deduplicatedEntries.append(entry)
                continue
            }
            let rawSpaceIDs = knownCGWindowsByID[cgWindowID]?.spaceIDs ?? []
            let normalizedSpaceIDs = RuntimeWindowTopologyClassifier.normalizedSpaceIDs(rawSpaceIDs)
            guard !normalizedSpaceIDs.isEmpty else {
                deduplicatedEntries.append(entry)
                continue
            }
            if entry.hasStickyBinding {
                deduplicatedEntries.append(entry)
                continue
            }
            if stickySpaceKeys.contains(spaceKey(for: normalizedSpaceIDs)) {
                droppedCount += 1
                continue
            }
            deduplicatedEntries.append(entry)
        }

        if droppedCount > 0 {
            RuntimeLog.debug(
                .axMatch,
                "\(appName) suppress-unmatched-ax-covered-by-sticky-space dropped=\(droppedCount)"
            )
        }

        return deduplicatedEntries
    }

    private static func spaceKey(for spaceIDs: [Int]) -> String {
        spaceIDs.map(String.init).joined(separator: ",")
    }
}
