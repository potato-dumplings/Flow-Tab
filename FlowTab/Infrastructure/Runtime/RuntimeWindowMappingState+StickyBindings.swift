import ApplicationServices
import Foundation

extension RuntimeWindowMappingState {
    mutating func applyReusableStickyBindings(
        axWindows: [RuntimeAXWindowEntry],
        validCGWindowIDs: Set<CGWindowID>,
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String,
        observedAt: TimeInterval
    ) -> RuntimeStickyBindingResolution {
        var exactMatchesByAXWindowID: [String: CGWindowID] = [:]
        var assignedAXWindowIDs: Set<String> = []
        var bindingDiagnostics: [WindowBindingDiagnostic] = []

        for cgWindowID in windowRecordsByCGWindowID.keys.sorted() {
            guard var record = windowRecordsByCGWindowID[cgWindowID] else { continue }
            let reusedAXWindow = record.reusableStickyAXWindow(
                from: axWindows,
                assignedAXWindowIDs: assignedAXWindowIDs
            )

            if let reusedAXWindow {
                let confirmationSource: WindowBindingConfirmationSource
                switch RuntimeAXWindowRecovery.verifyStickyBinding(
                    record: record,
                    reusedAXWindow: reusedAXWindow,
                    validCGWindowIDs: validCGWindowIDs
                ) {
                case .exactPrivateBridge:
                    confirmationSource = .privateExactBridge
                case .unavailable:
                    confirmationSource = .stickyBinding
                case let .conflict(diagnostic):
                    bindingDiagnostics.append(diagnostic)
                    RuntimeLog.debug(
                        .axMatch,
                        "binding-assignment conflict reason=\(diagnostic.reason?.rawValue ?? "unknown") ax=\(reusedAXWindow.id) stickyCG=\(cgWindowID) exactCG=\(diagnostic.cgWindowID.map(String.init) ?? "nil") allowedActions=\(diagnostic.allowedActions.map(\.rawValue).sorted().joined(separator: ","))"
                    )
                    record.updateFallbackDisplayStateIfNeeded()
                    windowRecordsByCGWindowID[cgWindowID] = record
                    continue
                }

                let resolvedTitle = RuntimeWindowTitleResolver.stableWindowTitle(
                    sourceTitle: reusedAXWindow.sourceTitle,
                    matchedCGTitle: knownCGWindowsByID[cgWindowID]?.title ?? record.displayTitle,
                    appName: appName,
                    fallbackIndex: reusedAXWindow.index,
                    refreshedAXTitle: nil
                )
                record.applyExactMatch(
                    axWindow: reusedAXWindow,
                    resolvedTitle: resolvedTitle,
                    confirmationSource: confirmationSource,
                    observedAt: observedAt,
                    matchedCGWindow: knownCGWindowsByID[cgWindowID]
                )
                exactMatchesByAXWindowID[reusedAXWindow.id] = cgWindowID
                assignedAXWindowIDs.insert(reusedAXWindow.id)
            } else {
                record.updateFallbackDisplayStateIfNeeded()
            }

            windowRecordsByCGWindowID[cgWindowID] = record
        }

        return RuntimeStickyBindingResolution(
            exactMatchesByAXWindowID: exactMatchesByAXWindowID,
            assignedAXWindowIDs: assignedAXWindowIDs,
            bindingDiagnostics: bindingDiagnostics
        )
    }
}
