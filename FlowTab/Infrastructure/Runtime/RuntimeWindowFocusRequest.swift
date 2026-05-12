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
    let restoreIfMinimized: Bool

    func targetCGWindowID(expectedPID: pid_t) -> CGWindowID? {
        preferredCGWindowID ?? RuntimeActivator.cgWindowID(from: windowID, expectedPID: expectedPID)
    }
}

typealias WindowFocusRequest = RuntimeWindowFocusRequest

extension RuntimeActivator {
    @discardableResult
    func reportWindowFocusVerified(_ request: WindowFocusRequest, in app: NSRunningApplication) -> Bool {
        windowFocusVerifiedHandler?(
            request.appID,
            request.windowID,
            request.ownerPID,
            request.targetCGWindowID(expectedPID: app.processIdentifier),
            request.title,
            request.frame
        )
        return true
    }
}
