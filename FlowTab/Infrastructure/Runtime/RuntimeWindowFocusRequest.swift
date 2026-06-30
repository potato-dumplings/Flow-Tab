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

extension RuntimeActivator {
    @discardableResult
    func reportWindowFocusVerified(_ request: WindowFocusRequest, in app: NSRunningApplication) -> Bool {
        let focusedAXWindow = currentFocusedAXWindowForReconciliation(in: app)
        let verification = RuntimeWindowFocusVerification(
            appID: request.appID,
            windowID: request.windowID,
            ownerPID: request.ownerPID,
            targetCGWindowID: request.targetCGWindowID(expectedPID: app.processIdentifier),
            focusedCGWindowID: focusedAXWindow.flatMap { AXWindowInspector.cgWindowID(for: $0) },
            focusedAXWindow: focusedAXWindow,
            title: request.title,
            frame: request.frame,
            allowedActions: request.bindingAllowedActions
        )
        windowFocusVerifiedHandler?(verification)
        return true
    }
}
