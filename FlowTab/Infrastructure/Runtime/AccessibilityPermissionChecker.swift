import ApplicationServices
import Foundation

enum AccessibilityPermissionChecker {
    static var isTrustedOverrideForTesting: (() -> Bool)?
    static var requestPermissionOverrideForTesting: (() -> Bool)?

    static func isTrusted() -> Bool {
        if let isTrustedOverrideForTesting {
            return isTrustedOverrideForTesting()
        }
        if let override = FlowTabTestLaunchOptions.accessibilityTrustedOverride {
            return override
        }
        return AXIsProcessTrusted()
    }

    @discardableResult
    static func requestPermission() -> Bool {
        if let requestPermissionOverrideForTesting {
            return requestPermissionOverrideForTesting()
        }
        if let override = FlowTabTestLaunchOptions.accessibilityTrustedOverride {
            return override
        }
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
