import AppKit
import ApplicationServices
import Darwin
import Foundation

enum AXExtractionError: Error, CustomStringConvertible {
    case attributeUnavailable(attribute: String, code: AXError)
    case typeMismatch(attribute: String, expected: String, actual: String)
    case invalidAXValue(attribute: String)

    var description: String {
        switch self {
        case .attributeUnavailable(let attribute, let code):
            return "attributeUnavailable attribute=\(attribute) code=\(code.rawValue)"
        case .typeMismatch(let attribute, let expected, let actual):
            return "typeMismatch attribute=\(attribute) expected=\(expected) actual=\(actual)"
        case .invalidAXValue(let attribute):
            return "invalidAXValue attribute=\(attribute)"
        }
    }
}

enum AXTypedAttributeReader {
    static func copiedAttribute(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> Result<CFTypeRef, AXExtractionError> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else {
            return .failure(
                .attributeUnavailable(attribute: attributeName(attribute), code: error)
            )
        }
        guard let value else {
            return .failure(.invalidAXValue(attribute: attributeName(attribute)))
        }
        return .success(value)
    }

    static func elementAttribute(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> Result<AXUIElement, AXExtractionError> {
        switch copiedAttribute(element, attribute) {
        case .success(let rawValue):
            return axElement(from: rawValue, attribute: attribute)
        case .failure(let error):
            return .failure(error)
        }
    }

    static func pointAttribute(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> Result<CGPoint, AXExtractionError> {
        switch copiedAttribute(element, attribute) {
        case .success(let rawValue):
            return point(from: rawValue, attribute: attribute)
        case .failure(let error):
            return .failure(error)
        }
    }

    static func sizeAttribute(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> Result<CGSize, AXExtractionError> {
        switch copiedAttribute(element, attribute) {
        case .success(let rawValue):
            return size(from: rawValue, attribute: attribute)
        case .failure(let error):
            return .failure(error)
        }
    }

    static func axElement(
        from rawValue: CFTypeRef?,
        attribute: CFString
    ) -> Result<AXUIElement, AXExtractionError> {
        guard let rawValue else {
            return .failure(.invalidAXValue(attribute: attributeName(attribute)))
        }
        guard CFGetTypeID(rawValue) == AXUIElementGetTypeID() else {
            return .failure(
                .typeMismatch(
                    attribute: attributeName(attribute),
                    expected: "AXUIElement",
                    actual: typeDescription(for: rawValue)
                )
            )
        }
        // CF-backed AX types cannot be conditionally downcast; the CFTypeID check is the safety boundary.
        let element = unsafeBitCast(rawValue, to: AXUIElement.self)
        return .success(element)
    }

    static func point(
        from rawValue: CFTypeRef?,
        attribute: CFString
    ) -> Result<CGPoint, AXExtractionError> {
        switch axValue(from: rawValue, attribute: attribute, expected: "AXValue<CGPoint>") {
        case .success(let axValue):
            guard AXValueGetType(axValue) == .cgPoint else {
                return .failure(
                    .typeMismatch(
                        attribute: attributeName(attribute),
                        expected: "AXValue<CGPoint>",
                        actual: "AXValue<\(AXValueGetType(axValue))>"
                    )
                )
            }
            var point = CGPoint.zero
            guard AXValueGetValue(axValue, .cgPoint, &point) else {
                return .failure(.invalidAXValue(attribute: attributeName(attribute)))
            }
            return .success(point)
        case .failure(let error):
            return .failure(error)
        }
    }

    static func size(
        from rawValue: CFTypeRef?,
        attribute: CFString
    ) -> Result<CGSize, AXExtractionError> {
        switch axValue(from: rawValue, attribute: attribute, expected: "AXValue<CGSize>") {
        case .success(let axValue):
            guard AXValueGetType(axValue) == .cgSize else {
                return .failure(
                    .typeMismatch(
                        attribute: attributeName(attribute),
                        expected: "AXValue<CGSize>",
                        actual: "AXValue<\(AXValueGetType(axValue))>"
                    )
                )
            }
            var size = CGSize.zero
            guard AXValueGetValue(axValue, .cgSize, &size) else {
                return .failure(.invalidAXValue(attribute: attributeName(attribute)))
            }
            return .success(size)
        case .failure(let error):
            return .failure(error)
        }
    }

    static func rawArrayCount(from rawValue: CFTypeRef?) -> Int? {
        guard let rawValue else { return nil }
        guard CFGetTypeID(rawValue) == CFArrayGetTypeID() else { return nil }
        return (rawValue as? NSArray)?.count
    }

    static func typeDescription(for rawValue: CFTypeRef?) -> String {
        guard let rawValue else { return "nil" }
        let typeID = CFGetTypeID(rawValue)
        switch typeID {
        case CFArrayGetTypeID():
            return "CFArray"
        case AXUIElementGetTypeID():
            return "AXUIElement"
        case AXValueGetTypeID():
            return "AXValue"
        case CFStringGetTypeID():
            return "CFString"
        case CFAttributedStringGetTypeID():
            return "CFAttributedString"
        case CFDictionaryGetTypeID():
            return "CFDictionary"
        case CFBooleanGetTypeID():
            return "CFBoolean"
        case CFNumberGetTypeID():
            return "CFNumber"
        default:
            return "typeID=\(typeID)"
        }
    }

    private static func axValue(
        from rawValue: CFTypeRef?,
        attribute: CFString,
        expected: String
    ) -> Result<AXValue, AXExtractionError> {
        guard let rawValue else {
            return .failure(.invalidAXValue(attribute: attributeName(attribute)))
        }
        guard CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return .failure(
                .typeMismatch(
                    attribute: attributeName(attribute),
                    expected: expected,
                    actual: typeDescription(for: rawValue)
                )
            )
        }
        // CF-backed AX types cannot be conditionally downcast; the CFTypeID check is the safety boundary.
        let axValue = unsafeBitCast(rawValue, to: AXValue.self)
        return .success(axValue)
    }

    private static func attributeName(_ attribute: CFString) -> String {
        attribute as String
    }
}

enum AXWindowInspector {
    struct WindowsFetchResult {
        let windows: [AXUIElement]
        let error: AXError
        let rawValueTypeDescription: String
        let rawArrayCount: Int?
        let remoteScanCompleteness: RuntimeAXRemoteWindowResolver.RemoteScanCompleteness?

        var logDetails: String {
            AXWindowInspector.windowsFetchLogDetails(
                error: error,
                rawValueTypeDescription: rawValueTypeDescription,
                rawArrayCount: rawArrayCount,
                decodedCount: windows.count,
                remoteScanCompleteness: remoteScanCompleteness
            )
        }
    }

    private static let windowIDPrefix = "ax"
    private static let exactBridgeSymbolName = "_AXUIElementGetWindow"
    private typealias AXUIElementGetWindowFn = @convention(c) (
        AXUIElement,
        UnsafeMutablePointer<CGWindowID>
    ) -> AXError
    static var cgWindowIDOverrideForTesting: ((AXUIElement) -> CGWindowID?)?
    static var remoteWindowsResolverOverrideForTesting: ((pid_t) -> [AXUIElement])?
    static var remoteWindowScanResultOverrideForTesting: ((pid_t) -> RuntimeAXRemoteWindowResolver.WindowScanResult)?

    static func windows(
        for app: NSRunningApplication,
        includeRemoteWindows: Bool = false
    ) -> [AXUIElement] {
        windowsFetchResult(for: app, includeRemoteWindows: includeRemoteWindows).windows
    }

    static func windowsFetchResult(
        for app: NSRunningApplication,
        includeRemoteWindows: Bool = false
    ) -> WindowsFetchResult {
        guard AccessibilityPermissionChecker.isTrusted() else {
            return WindowsFetchResult(
                windows: [],
                error: .apiDisabled,
                rawValueTypeDescription: "nil",
                rawArrayCount: nil,
                remoteScanCompleteness: nil
            )
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )
        let rawValueTypeDescription = AXTypedAttributeReader.typeDescription(for: windowsValue)
        let rawArrayCount = AXTypedAttributeReader.rawArrayCount(from: windowsValue)
        guard error == .success, let windows = windowsValue as? [AXUIElement] else {
            let remoteScanResult = remoteWindowScanResult(
                forPID: app.processIdentifier,
                includeRemoteWindows: includeRemoteWindows
            )
            return WindowsFetchResult(
                windows: remoteScanResult?.windows ?? [],
                error: error,
                rawValueTypeDescription: rawValueTypeDescription,
                rawArrayCount: rawArrayCount,
                remoteScanCompleteness: remoteScanResult?.completeness
            )
        }
        let remoteScanResult = remoteWindowScanResult(
            forPID: app.processIdentifier,
            includeRemoteWindows: includeRemoteWindows
        )
        return WindowsFetchResult(
            windows: RuntimeAXRemoteWindowResolver.mergedWindows(
                publicWindows: windows,
                remoteWindows: remoteScanResult?.windows ?? []
            ),
            error: error,
            rawValueTypeDescription: rawValueTypeDescription,
            rawArrayCount: rawArrayCount,
            remoteScanCompleteness: remoteScanResult?.completeness
        )
    }

    private static func remoteWindowScanResult(
        forPID pid: pid_t,
        includeRemoteWindows: Bool
    ) -> RuntimeAXRemoteWindowResolver.WindowScanResult? {
        guard includeRemoteWindows else { return nil }
        return remoteWindowScanResultOnCurrentThread(forPID: pid)
    }

    private static func remoteWindowScanResultOnCurrentThread(
        forPID pid: pid_t
    ) -> RuntimeAXRemoteWindowResolver.WindowScanResult {
        if let remoteWindowScanResultOverrideForTesting {
            return remoteWindowScanResultOverrideForTesting(pid)
        }
        if let remoteWindowsResolverOverrideForTesting {
            let windows = remoteWindowsResolverOverrideForTesting(pid)
            return RuntimeAXRemoteWindowResolver.WindowScanResult(
                windows: windows,
                completeness: .complete(scanned: windows.count)
            )
        }
        return RuntimeAXRemoteWindowResolver.windowScanResult(forPID: pid)
    }

    static func makeWindowID(pid: pid_t, index: Int) -> String {
        "\(windowIDPrefix):\(pid):\(index)"
    }

    static func windowIndex(from windowID: String, expectedPID: pid_t) -> Int? {
        let parts = windowID.split(separator: ":")
        guard parts.count == 3 else { return nil }
        guard parts[0] == Substring(windowIDPrefix) else { return nil }
        guard let pid = pid_t(parts[1]), pid == expectedPID else { return nil }
        return Int(parts[2])
    }

    static func fallbackTitle(index: Int) -> String {
        "Window #\(index + 1)"
    }

    static func title(for window: AXUIElement) -> String? {
        let titleFromAX = title(from: window, attribute: kAXTitleAttribute as CFString)

        let titleElementResult = AXTypedAttributeReader.elementAttribute(
            window,
            kAXTitleUIElementAttribute as CFString
        )
        guard case .success(let titleElement) = titleElementResult else {
            return preferredWindowTitle(candidates: [titleFromAX])
        }
        let titleFromTitleElementValue = title(
            from: titleElement,
            attribute: kAXValueAttribute as CFString
        )
        let titleFromTitleElementTitle = title(
            from: titleElement,
            attribute: kAXTitleAttribute as CFString
        )
        return preferredWindowTitle(
            candidates: [
                titleFromTitleElementValue,
                titleFromTitleElementTitle,
                titleFromAX
            ]
        )
    }

    static func frame(for window: AXUIElement) -> CGRect? {
        guard
            let position = pointValue(for: window, attribute: kAXPositionAttribute as CFString),
            let size = sizeValue(for: window, attribute: kAXSizeAttribute as CFString)
        else {
            return nil
        }
        return CGRect(origin: position, size: size).standardized
    }

    static func cgWindowID(for window: AXUIElement) -> CGWindowID? {
        if let cgWindowIDOverrideForTesting {
            return cgWindowIDOverrideForTesting(window)
        }
        guard let exactBridgeFunction else { return nil }
        var cgWindowID: CGWindowID = 0
        guard exactBridgeFunction(window, &cgWindowID) == .success else { return nil }
        return cgWindowID == 0 ? nil : cgWindowID
    }

    static func belongsToProcess(_ window: AXUIElement, pid: pid_t) -> Bool {
        var ownerPID: pid_t = 0
        guard AXUIElementGetPid(window, &ownerPID) == .success else { return false }
        return ownerPID == pid
    }

    static func isSwitchable(_ window: AXUIElement) -> Bool {
        guard let role = role(for: window) else { return true }
        return role == kAXWindowRole as String
    }

    static func role(for window: AXUIElement) -> String? {
        var roleValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleValue)
                == .success,
            let role = roleValue as? String
        else {
            return nil
        }
        return role
    }

    static func subrole(for window: AXUIElement) -> String? {
        var subroleValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue)
                == .success,
            let subrole = subroleValue as? String
        else {
            return nil
        }
        return subrole
    }

    static func isMinimized(_ window: AXUIElement) -> Bool {
        booleanAttribute(kAXMinimizedAttribute as CFString, for: window)
    }

    static func isFocused(_ window: AXUIElement) -> Bool {
        booleanAttribute(kAXFocusedAttribute as CFString, for: window)
    }

    static func isMain(_ window: AXUIElement) -> Bool {
        booleanAttribute(kAXMainAttribute as CFString, for: window)
    }

    private static func booleanAttribute(_ attribute: CFString, for window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, attribute, &value) == .success,
            let number = value as? NSNumber
        else {
            return false
        }
        return number.boolValue
    }

    static func windowsFetchLogDetails(
        error: AXError,
        rawValueTypeDescription: String,
        rawArrayCount: Int?,
        decodedCount: Int,
        remoteScanCompleteness: RuntimeAXRemoteWindowResolver.RemoteScanCompleteness? = nil
    ) -> String {
        let rawArrayCountDescription = rawArrayCount.map(String.init) ?? "nil"
        let baseDetails = "fetchError=\(error.rawValue) rawValueType=\(rawValueTypeDescription) rawArrayCount=\(rawArrayCountDescription) decodedCount=\(decodedCount)"
        guard let remoteScanCompleteness else { return baseDetails }
        return "\(baseDetails) remoteScan=\(remoteScanLogDescription(remoteScanCompleteness))"
    }

    static func remoteScanLogDescription(
        _ completeness: RuntimeAXRemoteWindowResolver.RemoteScanCompleteness
    ) -> String {
        switch completeness {
        case .unavailable:
            return "unavailable"
        case .complete(let scanned):
            return "complete scanned=\(scanned)"
        case .partialTimedOut(let scanned, let maximum):
            return "partialTimedOut scanned=\(scanned) maximum=\(maximum)"
        }
    }

    private static func pointValue(for window: AXUIElement, attribute: CFString) -> CGPoint? {
        guard case .success(let point) = AXTypedAttributeReader.pointAttribute(
            window,
            attribute
        ) else { return nil }
        return point
    }

    private static func sizeValue(for window: AXUIElement, attribute: CFString) -> CGSize? {
        guard case .success(let size) = AXTypedAttributeReader.sizeAttribute(
            window,
            attribute
        ) else { return nil }
        return size
    }

    private static func title(from element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return normalizedTitle(from: value)
    }

    private static func normalizedTitle(from rawValue: CFTypeRef?) -> String? {
        if let title = (rawValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty
        {
            return title
        }
        if let title = (rawValue as? NSAttributedString)?.string
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty
        {
            return title
        }
        return nil
    }

    fileprivate static func preferredWindowTitle(candidates: [String?]) -> String? {
        let normalizedCandidates = candidates.compactMap { normalizedTitle($0) }
        guard !normalizedCandidates.isEmpty else { return nil }
        return normalizedCandidates.max(by: { titleSpecificityScore($0) < titleSpecificityScore($1) })
    }

    private static func normalizedTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func titleSpecificityScore(_ title: String) -> Int {
        var score = title.count
        if title.contains(" - ") {
            score += 50
        }
        return score
    }

    private static let exactBridgeFunction: AXUIElementGetWindowFn? = {
        let candidateHandles = [
            UnsafeMutableRawPointer(bitPattern: -2),
            dlopen(
                "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
                RTLD_LAZY
            ),
            dlopen(
                "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
                RTLD_LAZY
            )
        ]
        for handle in candidateHandles {
            guard let handle else { continue }
            guard let symbol = dlsym(handle, exactBridgeSymbolName) else { continue }
            return unsafeBitCast(symbol, to: AXUIElementGetWindowFn.self)
        }
        return nil
    }()
}

enum AXWindowInspectorForTesting {
    static func makeWindowID(pid: pid_t, index: Int) -> String {
        AXWindowInspector.makeWindowID(pid: pid, index: index)
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
