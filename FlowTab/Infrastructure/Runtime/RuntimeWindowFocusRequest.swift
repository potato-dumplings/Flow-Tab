import AppKit
import ApplicationServices
import CoreGraphics

struct RuntimeWindowFocusRequest {
    let appID: String
    let windowID: String
    let title: String
    let frame: CGRect?
    let ownerPID: pid_t
    let preferredAXWindow: AXUIElement?
    let preferredActivationHandleID: String?
    let preferredCGWindowID: CGWindowID?
    let spaceIDs: [Int]
    let allowsPublicAXRecovery: Bool
    let bindingConfidence: WindowBindingConfidence
    let bindingAllowedActions: Set<WindowBindingAction>
    let restoreIfMinimized: Bool

    var allowsAnyActivationRoute: Bool {
        bindingAllowedActions.contains(.useForAXActivation)
            || bindingAllowedActions.contains(.useForCGActivationFallback)
    }

    func targetCGWindowID(expectedPID: pid_t) -> CGWindowID? {
        preferredCGWindowID ?? RuntimeActivator.cgWindowID(from: windowID, expectedPID: expectedPID)
    }
}

typealias WindowFocusRequest = RuntimeWindowFocusRequest

enum RuntimeWindowFocusAttemptResult {
    case verified(RuntimeWindowFocusReadbackEvidence)
    case focusedButUnverified
    case noFocusRoute

    var debugName: String {
        switch self {
        case .verified:
            return "verified"
        case .focusedButUnverified:
            return "focusedButUnverified"
        case .noFocusRoute:
            return "noFocusRoute"
        }
    }

    var verifiedReadback: RuntimeWindowFocusReadbackEvidence? {
        guard case let .verified(readback) = self else { return nil }
        return readback
    }
}

enum WindowBindingReadbackMismatchReason: String, Equatable {
    case targetCGNotVisible
    case focusedAXCGWindowMismatch
    case frontmostCGWindowMismatch
}

struct WindowBindingReadbackDiagnostic: Equatable {
    let appID: String
    let windowID: String
    let ownerPID: pid_t
    let route: String
    let reason: WindowBindingReadbackMismatchReason
    let targetCGWindowID: CGWindowID?
    let focusedCGWindowID: CGWindowID?
    let visibleCGWindowIDs: [CGWindowID]
    let bindingConfidence: WindowBindingConfidence
    let allowedActions: Set<WindowBindingAction>

    var affectedCGWindowIDs: Set<CGWindowID> {
        Set([targetCGWindowID, focusedCGWindowID].compactMap { $0 })
    }
}

struct RuntimeWindowFocusVerification: Equatable {
    let appID: String
    let windowID: String
    let ownerPID: pid_t
    let targetCGWindowID: CGWindowID?
    let focusedCGWindowID: CGWindowID?
    let focusedAXWindow: AXUIElement?
    let title: String
    let frame: CGRect?
    let allowedActions: Set<WindowBindingAction>

    static func == (lhs: RuntimeWindowFocusVerification, rhs: RuntimeWindowFocusVerification) -> Bool {
        lhs.appID == rhs.appID
            && lhs.windowID == rhs.windowID
            && lhs.ownerPID == rhs.ownerPID
            && lhs.targetCGWindowID == rhs.targetCGWindowID
            && lhs.focusedCGWindowID == rhs.focusedCGWindowID
            && axWindowsEqual(lhs.focusedAXWindow, rhs.focusedAXWindow)
            && lhs.title == rhs.title
            && lhs.frame == rhs.frame
            && lhs.allowedActions == rhs.allowedActions
    }

    private static func axWindowsEqual(_ lhs: AXUIElement?, _ rhs: AXUIElement?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return CFEqual(lhs, rhs)
        default:
            return false
        }
    }

    var affectedCGWindowIDs: Set<CGWindowID> {
        Set([targetCGWindowID, focusedCGWindowID].compactMap { $0 })
    }
}

struct RuntimeWindowFocusReadbackEvidence {
    let focusedAXWindow: AXUIElement?
    let focusedCGWindowID: CGWindowID?
}

struct RuntimeExactWindowFocusState {
    let targetCGWindowID: CGWindowID?
    let targetIsVisible: Bool
    let activationReadbackMatchesTarget: Bool
    let focusedCGWindowID: CGWindowID?
    let frontmostCGWindowID: CGWindowID?
    let visibleCGWindowIDs: [CGWindowID]

    init(
        targetCGWindowID: CGWindowID?,
        currentWindows: [RuntimeCGWindowEntry],
        focusReadback: RuntimeWindowFocusReadbackEvidence
    ) {
        self.targetCGWindowID = targetCGWindowID
        focusedCGWindowID = focusReadback.focusedCGWindowID
        visibleCGWindowIDs = currentWindows.compactMap { window in
            guard window.isOnscreen else { return nil }
            guard RuntimeCGWindowFacts.passesValidityConstraints(window) else {
                return nil
            }
            return window.id
        }
        frontmostCGWindowID = visibleCGWindowIDs.first

        guard let targetCGWindowID else {
            targetIsVisible = true
            activationReadbackMatchesTarget = true
            return
        }
        targetIsVisible = visibleCGWindowIDs.contains(targetCGWindowID)
        activationReadbackMatchesTarget =
            focusedCGWindowID == targetCGWindowID
            || (focusedCGWindowID == nil
                && frontmostCGWindowID == targetCGWindowID)
    }

    var isVerified: Bool {
        targetIsVisible && activationReadbackMatchesTarget
    }

    var mismatchReason: WindowBindingReadbackMismatchReason? {
        guard let targetCGWindowID else { return nil }
        guard targetIsVisible else { return .targetCGNotVisible }
        if let focusedCGWindowID, focusedCGWindowID != targetCGWindowID {
            return .focusedAXCGWindowMismatch
        }
        guard activationReadbackMatchesTarget else {
            return .frontmostCGWindowMismatch
        }
        return nil
    }
}

extension RuntimeActivator {
    func focusedAXWindowCGWindowID(in app: NSRunningApplication) -> CGWindowID? {
        currentWindowFocusReadbackEvidence(in: app).focusedCGWindowID
    }

    func currentFocusedAXWindowCGWindowIDForReconciliation(
        in app: NSRunningApplication
    ) -> CGWindowID? {
        focusedAXWindowCGWindowID(in: app)
    }

    func currentFocusedAXWindowForReconciliation(
        in app: NSRunningApplication
    ) -> AXUIElement? {
        focusedAXWindow(in: app)
    }

    func currentWindowFocusReadbackEvidence(
        in app: NSRunningApplication
    ) -> RuntimeWindowFocusReadbackEvidence {
        let focusedAXWindow = focusedAXWindow(in: app)
        return RuntimeWindowFocusReadbackEvidence(
            focusedAXWindow: focusedAXWindow,
            focusedCGWindowID: focusedAXWindow.flatMap {
                AXWindowInspector.cgWindowID(for: $0)
            }
        )
    }

    @discardableResult
    func reportWindowFocusVerified(
        _ request: WindowFocusRequest,
        readback: RuntimeWindowFocusReadbackEvidence,
        in app: NSRunningApplication
    ) -> Bool {
        let verification = RuntimeWindowFocusVerification(
            appID: request.appID,
            windowID: request.windowID,
            ownerPID: request.ownerPID,
            targetCGWindowID: request.targetCGWindowID(expectedPID: app.processIdentifier),
            focusedCGWindowID: readback.focusedCGWindowID,
            focusedAXWindow: readback.focusedAXWindow,
            title: request.title,
            frame: request.frame,
            allowedActions: request.bindingAllowedActions
        )
        windowFocusVerifiedHandler?(verification)
        return true
    }
}
