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

extension RuntimeActivator {
    @discardableResult
    func reportWindowFocusVerified(_ request: WindowFocusRequest, in app: NSRunningApplication) -> Bool {
        windowFocusVerifiedHandler?(
            request.appID,
            request.windowID,
            request.ownerPID,
            request.targetCGWindowID(expectedPID: app.processIdentifier),
            request.title,
            request.frame,
            request.bindingAllowedActions
        )
        return true
    }
}
