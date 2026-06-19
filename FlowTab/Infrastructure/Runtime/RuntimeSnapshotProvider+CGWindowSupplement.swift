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
        allCGWindows: [RuntimeCGWindowEntry],
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
                isOnscreen: cgWindow.isOnscreen,
                allowsPublicAXRecovery: true,
                hasStickyBinding: false,
                lastConfirmationSource: nil
            )
        }
        RuntimeLog.debug(
            .ax,
            "\(appName) unmatched-cg windows=\(cgOnlyEntries.count)"
        )
        return entries + cgOnlyEntries
    }

    func selectSupplementalOffSpaceCGWindows(
        existingCGWindowIDs: Set<CGWindowID>,
        allCGWindows: [RuntimeCGWindowEntry]
    ) -> [RuntimeCGWindowEntry] {
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
                RuntimeCGWindowEntry(
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
            cgWindow: RuntimeCGWindowEntry(
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
                RuntimeCGWindowEntry(
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

    static func cgWindowPassesValidityConstraints(_ window: RuntimeCGWindowEntry) -> Bool {
        guard window.alpha > validCGWindowAlphaThreshold else { return false }
        guard window.storeType == standardBufferedStoreType else { return false }
        guard let bounds = window.bounds?.standardized else { return false }
        guard bounds.width >= minimumValidCGWindowWidth else { return false }
        guard bounds.height >= minimumValidCGWindowHeight else { return false }
        return bounds.width * bounds.height >= minimumValidCGWindowArea
    }

    private func resolvedTitleForSupplementalCGWindow(
        appName: String,
        cgWindow: RuntimeCGWindowEntry
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

    func logChromeLikeTopologySnapshot(
        appName: String,
        pid: pid_t,
        publicWindowsFetchResult: AXWindowInspector.WindowsFetchResult,
        finalWindowsFetchResult: AXWindowInspector.WindowsFetchResult,
        includeRemoteAXWindows: Bool,
        publicSwitchableWindowCount: Int,
        axWindows: [AXWindowEntry],
        cgWindows: [RuntimeCGWindowEntry]
    ) {
        RuntimeLog.debug(
            .snapshot,
            "chrome-topology app=\(runtimeSnapshotLogValue(appName)) pid=\(pid) publicSwitchableAX=\(publicSwitchableWindowCount) publicFetch=[\(publicWindowsFetchResult.logDetails)] includeRemoteAX=\(includeRemoteAXWindows ? 1 : 0) finalFetch=[\(finalWindowsFetchResult.logDetails)] ax=[\(runtimeSnapshotAXWindowSummary(axWindows))] cg=[\(runtimeSnapshotCGWindowSummary(cgWindows))]"
        )
    }

    func logResolvedWindowEntrySummary(
        appName: String,
        pid: pid_t,
        axWindowCount: Int,
        entries: [WindowListEntry]
    ) {
        guard !entries.isEmpty else { return }

        let cgOnlyCount = entries.filter { $0.activationHandleID == nil && $0.axWindow == nil }.count
        let stickyCount = entries.filter(\.hasStickyBinding).count
        RuntimeLog.debug(
            .snapshot,
            "window-entries app=\(runtimeSnapshotLogValue(appName)) pid=\(pid) ax=\(axWindowCount) entries=\(entries.count) cgOnly=\(cgOnlyCount) sticky=\(stickyCount) detail=[\(runtimeSnapshotWindowEntrySummary(entries))]"
        )
    }
}

private func runtimeSnapshotAXWindowSummary(
    _ windows: [RuntimeSnapshotProvider.AXWindowEntry],
    limit: Int = 12
) -> String {
    guard !windows.isEmpty else { return "empty" }
    let sample = windows.prefix(limit).map { window in
        let bridgeCG = AXWindowInspector.cgWindowID(for: window.window).map(String.init) ?? "nil"
        let publicState = "min=\(window.isMinimized ? 1 : 0):focused=\(window.isFocused ? 1 : 0):main=\(window.isMain ? 1 : 0)"
        return "\(window.id):\(runtimeSnapshotLogValue(window.sourceTitle ?? window.title)):frame=\(runtimeSnapshotFrameDescription(window.frame)):bridgeCG=\(bridgeCG):\(publicState)"
    }.joined(separator: ",")
    return runtimeSnapshotSampleDescription(sample: sample, count: windows.count, limit: limit)
}

private func runtimeSnapshotCGWindowSummary(
    _ windows: [RuntimeCGWindowEntry],
    limit: Int = 16
) -> String {
    guard !windows.isEmpty else { return "empty" }
    let sample = windows.prefix(limit).map { window in
        let onscreen = window.isOnscreen ? "on" : "off"
        let spaces = window.spaceIDs.isEmpty ? "[]" : "[\(window.spaceIDs.map(String.init).joined(separator: ","))]"
        return "\(window.id):\(runtimeSnapshotLogValue(window.title ?? "nil")):\(onscreen):spaces=\(spaces):frame=\(runtimeSnapshotFrameDescription(window.bounds))"
    }.joined(separator: ",")
    return runtimeSnapshotSampleDescription(sample: sample, count: windows.count, limit: limit)
}

private func runtimeSnapshotWindowEntrySummary(
    _ entries: [RuntimeSnapshotProvider.WindowListEntry],
    limit: Int = 16
) -> String {
    guard !entries.isEmpty else { return "empty" }
    let sample = entries.prefix(limit).enumerated().map { index, entry in
        let mode = RuntimeWindowDiagnostics.displayMode(
            frame: entry.frame,
            spaceIDs: entry.spaceIDs,
            confirmationSource: entry.lastConfirmationSource
        )
        let identity = RuntimeWindowDiagnostics.activationIdentity(
            activationHandleID: entry.activationHandleID,
            hasAXWindow: entry.axWindow != nil,
            cgWindowID: entry.cgWindowID,
            hasStickyBinding: entry.hasStickyBinding
        )
        let cg = entry.cgWindowID.map(String.init) ?? "nil"
        let handle = entry.activationHandleID ?? "nil"
        let spaces = entry.spaceIDs.isEmpty
            ? "[]"
            : "[\(entry.spaceIDs.map(String.init).joined(separator: ","))]"
        let onscreen = entry.isOnscreen ? "on" : "off"
        let ax = entry.axWindow == nil ? 0 : 1
        let minimized = entry.isMinimized ? 1 : 0
        let publicAXRecovery = entry.allowsPublicAXRecovery ? 1 : 0
        let sticky = entry.hasStickyBinding ? 1 : 0
        let source = entry.lastConfirmationSource?.rawValue ?? "nil"
        let spaceEvidence = entry.spaceEvidence?.confidence.rawValue ?? "nil"
        return "\(index):id=\(entry.windowID):title=\(runtimeSnapshotLogValue(entry.title)):mode=\(mode):identity=\(identity):handle=\(handle):ax=\(ax):cg=\(cg):sticky=\(sticky):source=\(source):spaceEvidence=\(spaceEvidence):publicAXRecovery=\(publicAXRecovery):spaces=\(spaces):\(onscreen):minimized=\(minimized):frame=\(runtimeSnapshotFrameDescription(entry.frame))"
    }.joined(separator: ",")
    return runtimeSnapshotSampleDescription(sample: sample, count: entries.count, limit: limit)
}

private func runtimeSnapshotSampleDescription(sample: String, count: Int, limit: Int) -> String {
    count > limit ? "\(sample),...+\(count - limit)" : sample
}

private func runtimeSnapshotFrameDescription(_ frame: CGRect?) -> String {
    guard let frame else { return "nil" }
    return "\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.size.width))x\(Int(frame.size.height))"
}

private func runtimeSnapshotLogValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
