#if FLOWTAB_TESTING
import ApplicationServices
import Foundation

enum AXWindowInspectorForTesting {
    static func makeWindowID(pid: pid_t, index: Int) -> String {
        AXWindowInspector.makeWindowID(pid: pid, index: index)
    }

    static func makeVerifiedFocusFallbackWindowID(pid: pid_t, cgWindowID: CGWindowID) -> String {
        AXWindowInspector.makeVerifiedFocusFallbackWindowID(pid: pid, cgWindowID: cgWindowID)
    }

    static func verifiedFocusFallbackCGWindowID(from windowID: String) -> CGWindowID? {
        AXWindowInspector.verifiedFocusFallbackCGWindowID(from: windowID)
    }

    static func windowIndex(from windowID: String, expectedPID: pid_t) -> Int? {
        AXWindowInspector.windowIndex(from: windowID, expectedPID: expectedPID)
    }

    static func fallbackTitle(index: Int) -> String {
        AXWindowInspector.fallbackTitle(index: index)
    }

    static func title(for window: AXUIElement) -> String? {
        AXWindowInspector.title(for: window)
    }

    static func preferredWindowTitle(candidates: [String?]) -> String? {
        AXWindowInspector.preferredWindowTitle(candidates: candidates)
    }

    static func frame(for window: AXUIElement) -> CGRect? {
        AXWindowInspector.frame(for: window)
    }

    static func cgWindowID(for window: AXUIElement) -> CGWindowID? {
        AXWindowInspector.cgWindowID(for: window)
    }

    static func role(for window: AXUIElement) -> String? {
        AXWindowInspector.role(for: window)
    }

    static func isSwitchable(_ window: AXUIElement) -> Bool {
        AXWindowInspector.isSwitchable(window)
    }

    static func isMinimized(_ window: AXUIElement) -> Bool {
        AXWindowInspector.isMinimized(window)
    }

    static func isFocused(_ window: AXUIElement) -> Bool {
        AXWindowInspector.isFocused(window)
    }

    static func isMain(_ window: AXUIElement) -> Bool {
        AXWindowInspector.isMain(window)
    }

    static func windowsFetchLogDetails(
        error: AXError,
        rawValueTypeDescription: String,
        rawArrayCount: Int?,
        decodedCount: Int,
        remoteScanCompleteness: RuntimeAXRemoteWindowResolver.RemoteScanCompleteness? = nil
    ) -> String {
        AXWindowInspector.windowsFetchLogDetails(
            error: error,
            rawValueTypeDescription: rawValueTypeDescription,
            rawArrayCount: rawArrayCount,
            decodedCount: decodedCount,
            remoteScanCompleteness: remoteScanCompleteness
        )
    }

    static func remoteScanLogDescription(
        _ completeness: RuntimeAXRemoteWindowResolver.RemoteScanCompleteness
    ) -> String {
        AXWindowInspector.remoteScanLogDescription(completeness)
    }

    static func axElement(
        from rawValue: CFTypeRef?,
        attribute: CFString
    ) -> Result<AXUIElement, AXExtractionError> {
        AXTypedAttributeReader.axElement(from: rawValue, attribute: attribute)
    }

    static func point(
        from rawValue: CFTypeRef?,
        attribute: CFString
    ) -> Result<CGPoint, AXExtractionError> {
        AXTypedAttributeReader.point(from: rawValue, attribute: attribute)
    }

    static func size(
        from rawValue: CFTypeRef?,
        attribute: CFString
    ) -> Result<CGSize, AXExtractionError> {
        AXTypedAttributeReader.size(from: rawValue, attribute: attribute)
    }

    static func rawArrayCount(from rawValue: CFTypeRef?) -> Int? {
        AXTypedAttributeReader.rawArrayCount(from: rawValue)
    }

    static func typeDescription(for rawValue: CFTypeRef?) -> String {
        AXTypedAttributeReader.typeDescription(for: rawValue)
    }
}
#endif
