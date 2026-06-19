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

struct RuntimeFullRepairProjectionPayload {
    let apps: [AppSwitchCandidate]
    let contextsByID: [String: RuntimeAppContext]
}

struct RuntimeAppContext {
    let appID: String
    let runningApp: NSRunningApplication
    let windowsByID: [String: RuntimeWindowContext]
}

struct RuntimeAppWindowProjectionSeed {
    let windowID: String
    let title: String
    let isMinimized: Bool
    let lastActiveAt: TimeInterval
    let ownerPID: pid_t
    let cgWindowID: CGWindowID?
    let spaceIDs: [Int]
    let activationHandleID: String?
    let axWindow: AXUIElement?
    let frame: CGRect?
    let allowsPublicAXRecovery: Bool
    let hasStickyBinding: Bool
    let lastConfirmationSource: WindowBindingConfirmationSource?
    let bindingConfidenceOverride: WindowBindingConfidence?
    let bindingCandidateCount: Int?
    let spaceEvidence: RuntimeSpaceEvidence?

    init(
        windowID: String,
        title: String,
        isMinimized: Bool,
        lastActiveAt: TimeInterval,
        ownerPID: pid_t = 0,
        cgWindowID: CGWindowID? = nil,
        spaceIDs: [Int] = [],
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
        self.windowID = windowID
        self.title = title
        self.isMinimized = isMinimized
        self.lastActiveAt = lastActiveAt
        self.ownerPID = ownerPID
        self.cgWindowID = cgWindowID
        self.spaceIDs = spaceIDs
        self.activationHandleID = activationHandleID
        self.axWindow = axWindow
        self.frame = frame
        self.allowsPublicAXRecovery = allowsPublicAXRecovery
        self.hasStickyBinding = hasStickyBinding
        self.lastConfirmationSource = lastConfirmationSource
        self.bindingConfidenceOverride = bindingConfidenceOverride
        self.bindingCandidateCount = bindingCandidateCount
        self.spaceEvidence = spaceEvidence
    }

    var candidate: WindowCandidate {
        WindowCandidate(
            id: windowID,
            title: title,
            isMinimized: isMinimized,
            lastActiveAt: lastActiveAt
        )
    }

    var context: RuntimeWindowContext {
        RuntimeWindowContext(
            id: windowID,
            title: title,
            isMinimized: isMinimized,
            ownerPID: ownerPID,
            cgWindowID: cgWindowID,
            spaceIDs: spaceIDs,
            inferredTitleBarStyle: nil,
            activationHandleID: activationHandleID,
            axWindow: axWindow,
            frame: frame,
            allowsPublicAXRecovery: allowsPublicAXRecovery,
            hasStickyBinding: hasStickyBinding,
            lastConfirmationSource: lastConfirmationSource,
            bindingConfidenceOverride: bindingConfidenceOverride,
            bindingCandidateCount: bindingCandidateCount,
            spaceEvidence: spaceEvidence
        )
    }
}

enum RuntimeAppIdentity {
    static func appID(for app: NSRunningApplication) -> String {
        let pid = app.processIdentifier
        return app.bundleIdentifier ?? "pid:\(pid)"
    }
}

enum WindowBindingConfirmationSource: String {
    case stickyBinding
    case publicExactMatch
    case privateExactBridge
    case verifiedFocusReadback
    case fullscreenContentRebinding
    case fullscreenContentFallbackBinding
    case desktopSiblingBinding

    var bindingConfidence: WindowBindingConfidence {
        switch self {
        case .publicExactMatch, .privateExactBridge, .verifiedFocusReadback:
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

struct RuntimeAppWindowRepairPayload {
    let summary: RuntimeHomeAppSummary
    let candidate: AppSwitchCandidate
    let context: RuntimeAppContext

    init(
        summary: RuntimeHomeAppSummary,
        candidate: AppSwitchCandidate,
        context: RuntimeAppContext
    ) {
        self.summary = summary
        self.candidate = candidate
        self.context = context
    }

    init(
        appID: String,
        displayName: String,
        groupID: String,
        summaryLastActiveAt: TimeInterval,
        candidateLastActiveAt: TimeInterval,
        pid: pid_t,
        runningApp: NSRunningApplication,
        windowSeeds: [RuntimeAppWindowProjectionSeed]
    ) {
        let windowCandidates = windowSeeds.map(\.candidate)
        let windowContexts = Dictionary(
            uniqueKeysWithValues: windowSeeds.map { seed in
                (seed.windowID, seed.context)
            }
        )
        self.init(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: displayName,
                groupID: groupID,
                lastActiveAt: summaryLastActiveAt,
                windowCount: windowSeeds.count,
                pid: pid
            ),
            candidate: AppSwitchCandidate(
                id: appID,
                displayName: displayName,
                groupID: groupID,
                lastActiveAt: candidateLastActiveAt,
                windows: windowCandidates
            ),
            context: RuntimeAppContext(
                appID: appID,
                runningApp: runningApp,
                windowsByID: windowContexts
            )
        )
    }
}
