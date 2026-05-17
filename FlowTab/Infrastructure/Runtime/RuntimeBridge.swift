import AppKit
import ApplicationServices
import Foundation
import FlowTabCore

enum WindowTitleBarStyleGuess: String {
    case dark
    case light
}

struct RuntimeSnapshot {
    let apps: [AppSwitchCandidate]
    let contextsByID: [String: RuntimeAppContext]
}

struct RuntimeAppContext {
    let appID: String
    let runningApp: NSRunningApplication
    let windowsByID: [String: RuntimeWindowContext]
}

enum WindowBindingConfirmationSource: String {
    case stickyBinding
    case publicExactMatch
    case privateExactBridge
    case fullscreenContentRebinding
    case fullscreenContentFallbackBinding
    case desktopSiblingBinding

    var bindingConfidence: WindowBindingConfidence {
        switch self {
        case .publicExactMatch, .privateExactBridge:
            .exact
        case .stickyBinding:
            .sticky
        case .fullscreenContentRebinding,
             .fullscreenContentFallbackBinding,
             .desktopSiblingBinding:
            .inferred
        }
    }
}

enum WindowBindingConfidence: String {
    case exact
    case sticky
    case inferred
    case provisional
    case ambiguous
}

enum WindowBindingAction: String, Hashable {
    case exposeInSwitcher
    case useForAXActivation
    case useForCGActivationFallback
    case updateStickyHistory
    case updateRecency
    case capturePreview
    case quarantineOnly
}

enum WindowBindingDiagnosticReason: String {
    case publicAssignmentAmbiguous
    case privateExactBridgeConflictsWithStickyBinding
    case fullscreenTopologyAmbiguous
}

extension WindowBindingConfidence {
    var allowedActions: Set<WindowBindingAction> {
        switch self {
        case .exact:
            [
                .exposeInSwitcher,
                .useForAXActivation,
                .useForCGActivationFallback,
                .updateStickyHistory,
                .updateRecency,
                .capturePreview
            ]
        case .sticky:
            [
                .exposeInSwitcher,
                .useForCGActivationFallback,
                .capturePreview
            ]
        case .inferred:
            [
                .exposeInSwitcher,
                .useForCGActivationFallback,
                .capturePreview
            ]
        case .provisional:
            [
                .exposeInSwitcher,
                .capturePreview
            ]
        case .ambiguous:
            [
                .quarantineOnly
            ]
        }
    }
}

struct WindowBindingDiagnostic: Equatable {
    let stableWindowID: String
    let axWindowID: String?
    let cgWindowID: CGWindowID?
    let confidence: WindowBindingConfidence
    let source: WindowBindingConfirmationSource?
    let reason: WindowBindingDiagnosticReason?
    let candidateCount: Int
    let allowedActions: Set<WindowBindingAction>

    var isQuarantined: Bool {
        allowedActions == [.quarantineOnly]
    }
}

struct RuntimeWindowContext {
    let id: String
    let title: String
    let isMinimized: Bool
    let ownerPID: pid_t
    var cgWindowID: CGWindowID?
    let spaceIDs: [Int]
    var inferredTitleBarStyle: WindowTitleBarStyleGuess?
    var activationHandleID: String?
    var axWindow: AXUIElement? = nil
    let frame: CGRect?
    let allowsPublicAXRecovery: Bool
    let hasStickyBinding: Bool
    let lastConfirmationSource: WindowBindingConfirmationSource?
    let bindingConfidenceOverride: WindowBindingConfidence?
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
        bindingConfidence.allowedActions
    }

    var bindingDiagnostic: WindowBindingDiagnostic {
        WindowBindingDiagnostic(
            stableWindowID: id,
            axWindowID: activationHandleID,
            cgWindowID: cgWindowID,
            confidence: bindingConfidence,
            source: lastConfirmationSource,
            reason: nil,
            candidateCount: bindingCandidateCount,
            allowedActions: bindingAllowedActions
        )
    }

    init(
        id: String,
        title: String,
        isMinimized: Bool,
        ownerPID: pid_t = 0,
        cgWindowID: CGWindowID? = nil,
        spaceIDs: [Int] = [],
        inferredTitleBarStyle: WindowTitleBarStyleGuess? = nil,
        activationHandleID: String? = nil,
        axWindow: AXUIElement? = nil,
        frame: CGRect? = nil,
        allowsPublicAXRecovery: Bool = false,
        hasStickyBinding: Bool = false,
        lastConfirmationSource: WindowBindingConfirmationSource? = nil,
        bindingConfidenceOverride: WindowBindingConfidence? = nil,
        bindingCandidateCount: Int? = nil,
        spaceEvidence: RuntimeSpaceEvidence? = nil
    ) {
        self.id = id
        self.title = title
        self.isMinimized = isMinimized
        self.ownerPID = ownerPID
        self.cgWindowID = cgWindowID
        let normalizedSpaceIDs = RuntimeWindowTopologyClassifier.normalizedSpaceIDs(spaceIDs)
        self.spaceIDs = normalizedSpaceIDs
        self.inferredTitleBarStyle = inferredTitleBarStyle
        self.activationHandleID = activationHandleID
        self.axWindow = axWindow
        self.frame = frame
        self.allowsPublicAXRecovery = allowsPublicAXRecovery
        self.hasStickyBinding = hasStickyBinding
        self.lastConfirmationSource = lastConfirmationSource
        self.bindingConfidenceOverride = bindingConfidenceOverride
        self.bindingCandidateCount = bindingCandidateCount ?? (cgWindowID == nil ? 0 : 1)
        self.spaceEvidence = spaceEvidence ?? cgWindowID.map {
            RuntimeWindowTopologyClassifier.spaceEvidence(
                cgWindowID: $0,
                spaceIDs: normalizedSpaceIDs,
                bounds: frame,
                source: "runtime-window-context"
            )
        }
    }
}


struct RuntimeHomeAppSummary: Equatable, Identifiable {
    let appID: String
    let displayName: String
    let groupID: String
    let lastActiveAt: TimeInterval
    let windowCount: Int
    let pid: pid_t

    var id: String { appID }
}

struct RuntimeHomeAppSnapshot {
    let summary: RuntimeHomeAppSummary
    let candidate: AppSwitchCandidate
    let context: RuntimeAppContext
}
