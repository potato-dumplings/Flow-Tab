import ApplicationServices
import Foundation

enum AccessibilityPermissionChecker {
#if FLOWTAB_TESTING
    static var isTrustedOverrideForTesting: (() -> Bool)?
    static var requestPermissionOverrideForTesting: (() -> Bool)?
#endif

    static func isTrusted() -> Bool {
#if FLOWTAB_TESTING
        if let isTrustedOverrideForTesting {
            return isTrustedOverrideForTesting()
        }
        if let override = FlowTabTestLaunchOptions.accessibilityTrustedOverride {
            return override
        }
#endif
        return AXIsProcessTrusted()
    }

    @discardableResult
    static func requestPermission() -> Bool {
#if FLOWTAB_TESTING
        if let requestPermissionOverrideForTesting {
            return requestPermissionOverrideForTesting()
        }
        if let override = FlowTabTestLaunchOptions.accessibilityTrustedOverride {
            return override
        }
#endif
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
