import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit

enum ScreenCapturePermissionChecker {
#if FLOWTAB_TESTING
    static var hasPermissionOverrideForTesting: (() -> Bool)?
    static var requestPermissionOverrideForTesting: (() -> Bool)?
#endif

    private static var supportsScreenCapturePermissionAPI: Bool {
        if #available(macOS 10.15, *) {
            return true
        }
        return false
    }

    static var hasScreenCapturePermission: Bool {
#if FLOWTAB_TESTING
        resolvePermission(
            testingOverride: hasPermissionOverrideForTesting,
            launchOverride: FlowTabTestLaunchOptions.screenCaptureTrustedOverride,
            supportsPermissionAPI: supportsScreenCapturePermissionAPI,
            systemPermissionProvider: { CGPreflightScreenCaptureAccess() }
        )
#else
        guard supportsScreenCapturePermissionAPI else { return true }
        return CGPreflightScreenCaptureAccess()
#endif
    }

    @discardableResult
    static func requestScreenCapturePermission() -> Bool {
#if FLOWTAB_TESTING
        resolvePermission(
            testingOverride: requestPermissionOverrideForTesting,
            launchOverride: FlowTabTestLaunchOptions.screenCaptureTrustedOverride,
            supportsPermissionAPI: supportsScreenCapturePermissionAPI,
            systemPermissionProvider: { CGRequestScreenCaptureAccess() }
        )
#else
        guard supportsScreenCapturePermissionAPI else { return true }
        return CGRequestScreenCaptureAccess()
#endif
    }

    private static func resolvePermission(
        testingOverride: (() -> Bool)?,
        launchOverride: Bool?,
        supportsPermissionAPI: Bool,
        systemPermissionProvider: () -> Bool
    ) -> Bool {
        if let testingOverride {
            return testingOverride()
        }
        if let launchOverride {
            return launchOverride
        }
        guard supportsPermissionAPI else {
            return true
        }
        return systemPermissionProvider()
    }

#if FLOWTAB_TESTING
    static func resolvePermissionForTesting(
        testingOverride: (() -> Bool)?,
        launchOverride: Bool?,
        supportsPermissionAPI: Bool,
        systemPermissionProvider: () -> Bool
    ) -> Bool {
        resolvePermission(
            testingOverride: testingOverride,
            launchOverride: launchOverride,
            supportsPermissionAPI: supportsPermissionAPI,
            systemPermissionProvider: systemPermissionProvider
        )
    }
#endif
}
