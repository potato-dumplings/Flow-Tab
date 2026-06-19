import ApplicationServices
import CoreGraphics
import Foundation

enum RuntimeAXWindowRecovery {
    struct DiagnosticResult {
        let window: RuntimeAXWindowEntry
        let reason: String
    }

    static func recoverAXWindowFromPublicSources(
        targetCGWindowID: CGWindowID?,
        expectedTitle: String,
        expectedFrame: CGRect?,
        windows: [RuntimeAXWindowEntry],
        cgWindows: [RuntimeCGWindowEntry],
        appName: String?
    ) -> RuntimeAXWindowEntry? {
        recoverAXWindowFromPublicSourcesWithDiagnostics(
            targetCGWindowID: targetCGWindowID,
            expectedTitle: expectedTitle,
            expectedFrame: expectedFrame,
            windows: windows,
            cgWindows: cgWindows,
            appName: appName
        )?.window
    }

    static func recoverAXWindowFromPublicSourcesWithDiagnostics(
        targetCGWindowID: CGWindowID?,
        expectedTitle: String,
        expectedFrame: CGRect?,
        windows: [RuntimeAXWindowEntry],
        cgWindows: [RuntimeCGWindowEntry],
        appName: String?
    ) -> DiagnosticResult? {
        RuntimeLog.debug(
            .activation,
            "ax-recovery candidates app=\(runtimeAXRecoveryLogValue(appName)) targetCG=\(targetCGWindowID.map(String.init) ?? "nil") expectedTitle=\(runtimeAXRecoveryLogValue(expectedTitle)) expectedFrame=\(runtimeAXRecoveryFrameDescription(expectedFrame)) ax=\(runtimeAXRecoveryAXWindowSummary(windows)) cg=\(runtimeAXRecoveryCGWindowSummary(cgWindows, targetCGWindowID: targetCGWindowID))"
        )

        if let targetCGWindowID {
            let exactBridgeMatches = windows.filter {
                AXWindowInspector.cgWindowID(for: $0.window) == targetCGWindowID
            }
            RuntimeLog.debug(
                .activation,
                "ax-recovery exact-bridge targetCG=\(targetCGWindowID) matches=\(exactBridgeMatches.count) ids=\(runtimeAXRecoveryWindowIDs(exactBridgeMatches))"
            )
            if exactBridgeMatches.count == 1 {
                return DiagnosticResult(
                    window: exactBridgeMatches[0],
                    reason: "exact-bridge"
                )
            }
        }

        if let targetCGWindowID, cgWindows.contains(where: { $0.id == targetCGWindowID }) {
            let matchedWindowIDs = RuntimeWindowAssignmentMatcher.matchCGWindowAssignments(
                axWindows: windows,
                cgWindows: cgWindows,
                appName: appName
            )
            RuntimeLog.debug(
                .activation,
                "ax-recovery public-assignments targetCG=\(targetCGWindowID) matches=\(runtimeAXRecoveryAssignmentSummary(matchedWindowIDs))"
            )
            if
                let matchedWindowID = matchedWindowIDs.first(where: { $0.value == targetCGWindowID })?.key,
                let matchedWindow = windows.first(where: { $0.id == matchedWindowID })
            {
                return DiagnosticResult(
                    window: matchedWindow,
                    reason: "public-assignment"
                )
            }
        } else if let targetCGWindowID {
            RuntimeLog.debug(
                .activation,
                "ax-recovery target-cg-not-current targetCG=\(targetCGWindowID)"
            )
        }

        RuntimeLog.debug(
            .activation,
            "ax-recovery no-public-match targetCG=\(targetCGWindowID.map(String.init) ?? "nil")"
        )
        return nil
    }
}

private func runtimeAXRecoveryAXWindowSummary(
    _ windows: [RuntimeAXWindowEntry]
) -> String {
    let sample = windows.prefix(12).map { window in
        let bridgedCGWindowID = AXWindowInspector.cgWindowID(for: window.window).map(String.init) ?? "nil"
        let title = runtimeAXRecoveryLogValue(window.sourceTitle ?? window.title)
        let role = runtimeAXRecoveryLogValue(AXWindowInspector.role(for: window.window))
        let subrole = runtimeAXRecoveryLogValue(AXWindowInspector.subrole(for: window.window))
        let publicState = "min=\(window.isMinimized ? 1 : 0):focused=\(window.isFocused ? 1 : 0):main=\(window.isMain ? 1 : 0)"
        return "\(window.id):idx=\(window.index):title=\(title):cg=\(bridgedCGWindowID):frame=\(runtimeAXRecoveryFrameDescription(window.frame)):\(publicState):role=\(role):subrole=\(subrole)"
    }.joined(separator: ",")
    return "count=\(windows.count) sample=[\(sample)]"
}

private func runtimeAXRecoveryCGWindowSummary(
    _ windows: [RuntimeCGWindowEntry],
    targetCGWindowID: CGWindowID?
) -> String {
    let sample = windows.prefix(12).map { window in
        let marker = window.id == targetCGWindowID ? "*" : ""
        let title = runtimeAXRecoveryLogValue(window.title)
        let onscreen = window.isOnscreen ? "on" : "off"
        let alpha = String(format: "%.2f", window.alpha)
        return "\(marker)\(window.id):title=\(title):\(onscreen):alpha=\(alpha):store=\(window.storeType):spaces=\(window.spaceIDs):frame=\(runtimeAXRecoveryFrameDescription(window.bounds))"
    }.joined(separator: ",")
    return "count=\(windows.count) sample=[\(sample)]"
}

private func runtimeAXRecoveryWindowIDs(
    _ windows: [RuntimeAXWindowEntry]
) -> String {
    windows
        .map { window in
            let bridgedCGWindowID = AXWindowInspector.cgWindowID(for: window.window).map(String.init) ?? "nil"
            let publicState = "min=\(window.isMinimized ? 1 : 0),focused=\(window.isFocused ? 1 : 0),main=\(window.isMain ? 1 : 0)"
            return "\(window.id)(cg=\(bridgedCGWindowID),title=\(runtimeAXRecoveryLogValue(window.sourceTitle ?? window.title)),frame=\(runtimeAXRecoveryFrameDescription(window.frame)),\(publicState))"
        }
        .joined(separator: ",")
}

private func runtimeAXRecoveryAssignmentSummary(_ assignments: [String: CGWindowID]) -> String {
    assignments
        .sorted { lhs, rhs in
            if lhs.key == rhs.key {
                return lhs.value < rhs.value
            }
            return lhs.key < rhs.key
        }
        .map { "\($0.key)->\($0.value)" }
        .joined(separator: ",")
}

private func runtimeAXRecoveryFrameDescription(_ frame: CGRect?) -> String {
    guard let frame else { return "nil" }
    return "\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.size.width))x\(Int(frame.size.height))"
}

private func runtimeAXRecoveryLogValue(_ value: String?) -> String {
    guard let value else { return "nil" }
    let trimmed = value
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "empty" : trimmed
}
