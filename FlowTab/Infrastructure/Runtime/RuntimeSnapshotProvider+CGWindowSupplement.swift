import AppKit
import ApplicationServices
import Foundation

extension RuntimeSnapshotProvider {
    func logChromeLikeTopologyFacts(
        appName: String,
        pid: pid_t,
        publicWindowsFetchResult: AXWindowInspector.WindowsFetchResult,
        finalWindowsFetchResult: AXWindowInspector.WindowsFetchResult,
        includeRemoteAXWindows: Bool,
        publicSwitchableWindowCount: Int,
        axWindows: [RuntimeAXWindowEntry],
        cgWindows: [RuntimeCGWindowEntry]
    ) {
        RuntimeLog.debug(
            .snapshot,
            "chrome-topology app=\(runtimeWindowListLogValue(appName)) pid=\(pid) publicSwitchableAX=\(publicSwitchableWindowCount) publicFetch=[\(publicWindowsFetchResult.logDetails)] includeRemoteAX=\(includeRemoteAXWindows ? 1 : 0) finalFetch=[\(finalWindowsFetchResult.logDetails)] ax=[\(runtimeWindowListAXWindowSummary(axWindows))] cg=[\(runtimeWindowListCGWindowSummary(cgWindows))]"
        )
    }

    func logResolvedWindowEntrySummary(
        appName: String,
        pid: pid_t,
        axWindowCount: Int,
        entries: [RuntimeWindowListEntry]
    ) {
        guard !entries.isEmpty else { return }

        let cgOnlyCount = entries.filter { $0.activationHandleID == nil && $0.axWindow == nil }.count
        let stickyCount = entries.filter(\.hasStickyBinding).count
        RuntimeLog.debug(
            .snapshot,
            "window-entries app=\(runtimeWindowListLogValue(appName)) pid=\(pid) ax=\(axWindowCount) entries=\(entries.count) cgOnly=\(cgOnlyCount) sticky=\(stickyCount) detail=[\(runtimeWindowListEntrySummary(entries))]"
        )
    }
}

private func runtimeWindowListAXWindowSummary(
    _ windows: [RuntimeAXWindowEntry],
    limit: Int = 12
) -> String {
    guard !windows.isEmpty else { return "empty" }
    let sample = windows.prefix(limit).map { window in
        let bridgeCG = AXWindowInspector.cgWindowID(for: window.window).map(String.init) ?? "nil"
        let publicState = "min=\(window.isMinimized ? 1 : 0):focused=\(window.isFocused ? 1 : 0):main=\(window.isMain ? 1 : 0)"
        return "\(window.id):\(runtimeWindowListLogValue(window.sourceTitle ?? window.title)):frame=\(runtimeWindowListFrameDescription(window.frame)):bridgeCG=\(bridgeCG):\(publicState)"
    }.joined(separator: ",")
    return runtimeWindowListSampleDescription(sample: sample, count: windows.count, limit: limit)
}

private func runtimeWindowListCGWindowSummary(
    _ windows: [RuntimeCGWindowEntry],
    limit: Int = 16
) -> String {
    guard !windows.isEmpty else { return "empty" }
    let sample = windows.prefix(limit).map { window in
        let onscreen = window.isOnscreen ? "on" : "off"
        let spaces = window.spaceIDs.isEmpty ? "[]" : "[\(window.spaceIDs.map(String.init).joined(separator: ","))]"
        return "\(window.id):\(runtimeWindowListLogValue(window.title ?? "nil")):\(onscreen):spaces=\(spaces):frame=\(runtimeWindowListFrameDescription(window.bounds))"
    }.joined(separator: ",")
    return runtimeWindowListSampleDescription(sample: sample, count: windows.count, limit: limit)
}

private func runtimeWindowListEntrySummary(
    _ entries: [RuntimeWindowListEntry],
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
        return "\(index):id=\(entry.windowID):title=\(runtimeWindowListLogValue(entry.title)):mode=\(mode):identity=\(identity):handle=\(handle):ax=\(ax):cg=\(cg):sticky=\(sticky):source=\(source):spaceEvidence=\(spaceEvidence):publicAXRecovery=\(publicAXRecovery):spaces=\(spaces):\(onscreen):minimized=\(minimized):frame=\(runtimeWindowListFrameDescription(entry.frame))"
    }.joined(separator: ",")
    return runtimeWindowListSampleDescription(sample: sample, count: entries.count, limit: limit)
}

private func runtimeWindowListSampleDescription(sample: String, count: Int, limit: Int) -> String {
    count > limit ? "\(sample),...+\(count - limit)" : sample
}

private func runtimeWindowListFrameDescription(_ frame: CGRect?) -> String {
    guard let frame else { return "nil" }
    return "\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.size.width))x\(Int(frame.size.height))"
}

private func runtimeWindowListLogValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
