import AppKit
import Combine
import FlowTabCore

struct PendingPreviewCapture {
    let appID: String
    let bundleIdentifier: String?
    let windowID: String
    let ownerPID: pid_t
    let preferredWindowID: CGWindowID?
    let preferredTitle: String
    let windowFrame: CGRect?
    let inferTitleBarStyle: Bool
    let activationHandleID: String?
    let initialCacheKey: String

    var providerRequest: WindowPreviewRequest {
        WindowPreviewRequest(
            appID: appID,
            bundleIdentifier: bundleIdentifier,
            ownerPID: ownerPID,
            windowID: windowID,
            preferredCGWindowID: preferredWindowID,
            preferredTitle: preferredTitle,
            windowFrame: windowFrame,
            inferTitleBarStyle: inferTitleBarStyle,
            activationHandleID: activationHandleID
        )
    }
}
