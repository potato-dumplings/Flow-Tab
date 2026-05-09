import AppKit
import ApplicationServices
import Foundation

extension RuntimeSnapshotProvider {
    private static let minimumValidCGWindowWidth: CGFloat = 80
    private static let minimumValidCGWindowHeight: CGFloat = 60
    private static let minimumValidCGWindowArea: CGFloat = 20_000
    private static let validCGWindowAlphaThreshold: Double = 0.001
    private static let standardBufferedStoreType: Int = 1

    static func makeCGWindowID(pid: pid_t, cgWindowID: CGWindowID) -> String {
        "cg:\(pid):\(cgWindowID)"
    }

    func appendOffSpaceCGWindows(
        to entries: [WindowListEntry],
        appName: String,
        pid: pid_t,
        allCGWindows: [CGWindowEntry],
        matchedCGWindowIDs: Set<CGWindowID> = []
    ) -> [WindowListEntry] {
        let unmatchedCGWindows = selectSupplementalOffSpaceCGWindows(
            existingCGWindowIDs: matchedCGWindowIDs,
            allCGWindows: allCGWindows
        )
        guard !unmatchedCGWindows.isEmpty else { return entries }

        let cgOnlyEntries = unmatchedCGWindows.map { cgWindow in
            WindowListEntry(
                windowID: Self.makeCGWindowID(pid: pid, cgWindowID: cgWindow.id),
                title: resolvedTitleForSupplementalCGWindow(
                    appName: appName,
                    cgWindow: cgWindow
                ),
                isMinimized: false,
                ownerPID: pid,
                cgWindowID: cgWindow.id,
                axWindow: nil,
                frame: cgWindow.bounds,
                spaceIDs: cgWindow.spaceIDs,
                allowsPublicAXRecovery: true,
                hasStickyBinding: false,
                lastConfirmationSource: nil
            )
        }
        RuntimeLog.info(
            "AX",
            "\(appName) unmatched-cg windows=\(cgOnlyEntries.count)"
        )
        return entries + cgOnlyEntries
    }

    func selectSupplementalOffSpaceCGWindows(
        existingCGWindowIDs: Set<CGWindowID>,
        allCGWindows: [CGWindowEntry]
    ) -> [CGWindowEntry] {
        allCGWindows.filter { window in
            !existingCGWindowIDs.contains(window.id) && Self.cgWindowPassesValidityConstraints(window)
        }
    }

    static func validCGWindowIDsForTesting(
        existingCGWindowIDs: Set<CGWindowID>,
        allCGWindows: [CGWindowEntryForTesting]
    ) -> [CGWindowID] {
        let provider = RuntimeSnapshotProvider()
        return provider.selectSupplementalOffSpaceCGWindows(
            existingCGWindowIDs: existingCGWindowIDs,
            allCGWindows: allCGWindows.map {
                CGWindowEntry(
                    id: $0.id,
                    title: $0.title,
                    bounds: $0.bounds,
                    isOnscreen: $0.isOnscreen,
                    alpha: $0.alpha,
                    storeType: $0.storeType,
                    spaceIDs: $0.spaceIDs
                )
            }
        ).map(\.id)
    }

    static func supplementalCGWindowIDsForTesting(
        existingCGWindowIDs: Set<CGWindowID>,
        allCGWindows: [CGWindowEntryForTesting]
    ) -> [CGWindowID] {
        validCGWindowIDsForTesting(
            existingCGWindowIDs: existingCGWindowIDs,
            allCGWindows: allCGWindows
        )
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
                storeType: cgWindow.storeType,
                spaceIDs: cgWindow.spaceIDs
            )
        )
    }

    struct SupplementalMergeEntryForTesting {
        let windowID: String
        let title: String
        let isMinimized: Bool
        let cgWindowID: CGWindowID?
        let frame: CGRect?
        let spaceIDs: [Int]
        let hasActivationHandle: Bool
        let lastConfirmationSource: WindowBindingConfirmationSource?

        init(
            windowID: String,
            title: String,
            isMinimized: Bool,
            cgWindowID: CGWindowID?,
            frame: CGRect? = nil,
            spaceIDs: [Int] = [],
            hasActivationHandle: Bool = false,
            lastConfirmationSource: WindowBindingConfirmationSource? = nil
        ) {
            self.windowID = windowID
            self.title = title
            self.isMinimized = isMinimized
            self.cgWindowID = cgWindowID
            self.frame = frame
            self.spaceIDs = RuntimeWindowTopologyClassifier.normalizedSpaceIDs(spaceIDs)
            self.hasActivationHandle = hasActivationHandle
            self.lastConfirmationSource = lastConfirmationSource
        }
    }

    static func appendOffSpaceCGWindowsForTesting(
        entries: [SupplementalMergeEntryForTesting],
        appName: String,
        pid: pid_t,
        allCGWindows: [CGWindowEntryForTesting],
        matchedCGWindowIDs: Set<CGWindowID> = []
    ) -> [SupplementalMergeEntryForTesting] {
        let provider = RuntimeSnapshotProvider()
        return provider.appendOffSpaceCGWindows(
            to: entries.map {
                WindowListEntry(
                    windowID: $0.windowID,
                    title: $0.title,
                    isMinimized: $0.isMinimized,
                    cgWindowID: $0.cgWindowID,
                    axWindow: nil,
                    frame: $0.frame,
                    spaceIDs: $0.spaceIDs,
                    lastConfirmationSource: $0.lastConfirmationSource
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
                    storeType: $0.storeType,
                    spaceIDs: $0.spaceIDs
                )
            },
            matchedCGWindowIDs: matchedCGWindowIDs
        ).map {
            SupplementalMergeEntryForTesting(
                windowID: $0.windowID,
                title: $0.title,
                isMinimized: $0.isMinimized,
                cgWindowID: $0.cgWindowID,
                frame: $0.frame,
                spaceIDs: $0.spaceIDs,
                hasActivationHandle: $0.activationHandleID != nil || $0.axWindow != nil,
                lastConfirmationSource: $0.lastConfirmationSource
            )
        }
    }

    static func cgWindowPassesValidityConstraints(_ window: CGWindowEntry) -> Bool {
        guard window.alpha > validCGWindowAlphaThreshold else { return false }
        guard window.storeType == standardBufferedStoreType else { return false }
        guard let bounds = window.bounds?.standardized else { return false }
        guard bounds.width >= minimumValidCGWindowWidth else { return false }
        guard bounds.height >= minimumValidCGWindowHeight else { return false }
        return bounds.width * bounds.height >= minimumValidCGWindowArea
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
}
