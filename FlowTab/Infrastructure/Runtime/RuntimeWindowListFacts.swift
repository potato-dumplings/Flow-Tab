import AppKit
import ApplicationServices
import FlowTabCore

struct RuntimeAXAppWindowCollection {
    let app: NSRunningApplication
    let appName: String
    let cgWindows: [RuntimeCGWindowEntry]
    let allCGWindows: [RuntimeCGWindowEntry]
    let publicWindowsFetchResult: AXWindowInspector.WindowsFetchResult
    let publicSwitchableWindowCount: Int
    let shouldIncludeRemoteAXWindows: Bool
    let windowsFetchResult: AXWindowInspector.WindowsFetchResult
    let windows: [AXUIElement]
    let axEntries: [RuntimeAXWindowEntry]
    let cgPrepMs: Double
    let publicFetchMs: Double
    let publicSwitchableMs: Double
    let remoteDecisionMs: Double
    let finalFetchMs: Double
    let axInspectMs: Double
    let totalMs: Double
}

struct RuntimeWindowListEntry {
    let windowID: String
    let title: String
    let isMinimized: Bool
    let ownerPID: pid_t
    let cgWindowID: CGWindowID?
    let activationHandleID: String?
    let axWindow: AXUIElement?
    let frame: CGRect?
    let spaceIDs: [Int]
    let isOnscreen: Bool
    let allowsPublicAXRecovery: Bool
    let hasStickyBinding: Bool
    let lastConfirmationSource: WindowBindingConfirmationSource?
    let bindingConfidenceOverride: WindowBindingConfidence?
    let bindingAllowedActionsOverride: Set<WindowBindingAction>?
    let bindingCandidateCount: Int
    let spaceEvidence: RuntimeSpaceEvidence?

    var bindingConfidence: WindowBindingConfidence {
        if let bindingConfidenceOverride {
            return bindingConfidenceOverride
        }
        if let lastConfirmationSource {
            return lastConfirmationSource.bindingConfidence
        }
        if hasStickyBinding {
            return .sticky
        }
        return .provisional
    }

    var bindingAllowedActions: Set<WindowBindingAction> {
        bindingAllowedActionsOverride ?? bindingConfidence.allowedActions
    }

    var bindingDiagnostic: WindowBindingDiagnostic {
        WindowBindingDiagnostic(
            stableWindowID: windowID,
            axWindowID: activationHandleID,
            cgWindowID: cgWindowID,
            confidence: bindingConfidence,
            source: lastConfirmationSource,
            reason: nil,
            candidateCount: bindingCandidateCount,
            allowedActions: bindingAllowedActions
        )
    }

    static func cgStableWindowID(pid: pid_t, cgWindowID: CGWindowID) -> String {
        "cg:\(pid):\(cgWindowID)"
    }

    init(
        windowID: String,
        title: String,
        isMinimized: Bool,
        ownerPID: pid_t = 0,
        cgWindowID: CGWindowID?,
        activationHandleID: String? = nil,
        axWindow: AXUIElement? = nil,
        frame: CGRect? = nil,
        spaceIDs: [Int] = [],
        isOnscreen: Bool = false,
        allowsPublicAXRecovery: Bool = false,
        hasStickyBinding: Bool = false,
        lastConfirmationSource: WindowBindingConfirmationSource? = nil,
        bindingConfidenceOverride: WindowBindingConfidence? = nil,
        bindingAllowedActionsOverride: Set<WindowBindingAction>? = nil,
        bindingCandidateCount: Int? = nil,
        spaceEvidence: RuntimeSpaceEvidence? = nil
    ) {
        self.windowID = windowID
        self.title = title
        self.isMinimized = isMinimized
        self.ownerPID = ownerPID
        self.cgWindowID = cgWindowID
        self.activationHandleID = activationHandleID
        self.axWindow = axWindow
        self.frame = frame
        let normalizedSpaceIDs = RuntimeWindowTopologyClassifier.normalizedSpaceIDs(spaceIDs)
        self.spaceIDs = normalizedSpaceIDs
        self.isOnscreen = isOnscreen
        self.allowsPublicAXRecovery = allowsPublicAXRecovery
        self.hasStickyBinding = hasStickyBinding
        self.lastConfirmationSource = lastConfirmationSource
        self.bindingConfidenceOverride = bindingConfidenceOverride
        self.bindingAllowedActionsOverride = bindingAllowedActionsOverride
        self.bindingCandidateCount = bindingCandidateCount ?? (cgWindowID == nil ? 0 : 1)
        self.spaceEvidence = spaceEvidence ?? cgWindowID.map {
            RuntimeWindowTopologyClassifier.spaceEvidence(
                cgWindowID: $0,
                spaceIDs: normalizedSpaceIDs,
                bounds: frame,
                source: "window-list-entry"
            )
        }
    }
}

enum RuntimeWindowListSupplementer {
    static func appendOffSpaceCGWindows(
        to entries: [RuntimeWindowListEntry],
        appName: String,
        pid: pid_t,
        allCGWindows: [RuntimeCGWindowEntry],
        matchedCGWindowIDs: Set<CGWindowID> = []
    ) -> [RuntimeWindowListEntry] {
        let unmatchedCGWindows = selectSupplementalOffSpaceCGWindows(
            existingCGWindowIDs: matchedCGWindowIDs,
            allCGWindows: allCGWindows
        )
        guard !unmatchedCGWindows.isEmpty else { return entries }

        let cgOnlyEntries = unmatchedCGWindows.map { cgWindow in
            RuntimeWindowListEntry(
                windowID: RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindow.id),
                title: RuntimeWindowTitleResolver.supplementalCGWindowTitle(
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

    static func selectSupplementalOffSpaceCGWindows(
        existingCGWindowIDs: Set<CGWindowID>,
        allCGWindows: [RuntimeCGWindowEntry]
    ) -> [RuntimeCGWindowEntry] {
        allCGWindows.filter { window in
            !existingCGWindowIDs.contains(window.id) && RuntimeCGWindowFacts.passesValidityConstraints(window)
        }
    }
}
