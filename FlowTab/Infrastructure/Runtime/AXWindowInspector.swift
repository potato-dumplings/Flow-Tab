import AppKit
import ApplicationServices
import Darwin
import Foundation

enum AXWindowInspector {
    struct WindowsFetchResult {
        let windows: [AXUIElement]
        let error: AXError
        let rawValueTypeDescription: String
        let rawArrayCount: Int?

        var logDetails: String {
            AXWindowInspector.windowsFetchLogDetails(
                error: error,
                rawValueTypeDescription: rawValueTypeDescription,
                rawArrayCount: rawArrayCount,
                decodedCount: windows.count
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

    static func windows(for app: NSRunningApplication) -> [AXUIElement] {
        windowsFetchResult(for: app).windows
    }

    static func windowsFetchResult(for app: NSRunningApplication) -> WindowsFetchResult {
        guard AccessibilityPermissionChecker.isTrusted() else {
            return WindowsFetchResult(
                windows: [],
                error: .apiDisabled,
                rawValueTypeDescription: "nil",
                rawArrayCount: nil
            )
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )
        let rawValueTypeDescription = cfTypeDescription(for: windowsValue)
        let rawArrayCount = rawArrayCount(from: windowsValue)
        guard error == .success, let windows = windowsValue as? [AXUIElement] else {
            return WindowsFetchResult(
                windows: [],
                error: error,
                rawValueTypeDescription: rawValueTypeDescription,
                rawArrayCount: rawArrayCount
            )
        }
        return WindowsFetchResult(
            windows: windows,
            error: error,
            rawValueTypeDescription: rawValueTypeDescription,
            rawArrayCount: rawArrayCount
        )
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

        var titleElementValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                window,
                kAXTitleUIElementAttribute as CFString,
                &titleElementValue
            ) == .success
        else {
            return preferredWindowTitle(candidates: [titleFromAX])
        }
        guard let rawTitleElement = titleElementValue else {
            return preferredWindowTitle(candidates: [titleFromAX])
        }
        guard CFGetTypeID(rawTitleElement) == AXUIElementGetTypeID() else {
            return preferredWindowTitle(candidates: [titleFromAX])
        }
        let titleElement = unsafeBitCast(rawTitleElement, to: AXUIElement.self)
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

    static func isMinimized(_ window: AXUIElement) -> Bool {
        var minimizedValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
                == .success,
            let number = minimizedValue as? NSNumber
        else {
            return false
        }
        return number.boolValue
    }

    static func windowsFetchLogDetails(
        error: AXError,
        rawValueTypeDescription: String,
        rawArrayCount: Int?,
        decodedCount: Int
    ) -> String {
        let rawArrayCountDescription = rawArrayCount.map(String.init) ?? "nil"
        return "fetchError=\(error.rawValue) rawValueType=\(rawValueTypeDescription) rawArrayCount=\(rawArrayCountDescription) decodedCount=\(decodedCount)"
    }

    private static func pointValue(for window: AXUIElement, attribute: CFString) -> CGPoint? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, attribute, &value) == .success,
            let rawValue = value,
            CFGetTypeID(rawValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let axValue = rawValue as! AXValue
        guard
            AXValueGetType(axValue) == .cgPoint
        else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeValue(for window: AXUIElement, attribute: CFString) -> CGSize? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, attribute, &value) == .success,
            let rawValue = value,
            CFGetTypeID(rawValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let axValue = rawValue as! AXValue
        guard
            AXValueGetType(axValue) == .cgSize
        else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
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

    private static func rawArrayCount(from rawValue: CFTypeRef?) -> Int? {
        guard let rawValue else { return nil }
        guard CFGetTypeID(rawValue) == CFArrayGetTypeID() else { return nil }
        let array = unsafeBitCast(rawValue, to: CFArray.self)
        return CFArrayGetCount(array)
    }

    private static func cfTypeDescription(for rawValue: CFTypeRef?) -> String {
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

    static func windowsFetchLogDetails(
        error: AXError,
        rawValueTypeDescription: String,
        rawArrayCount: Int?,
        decodedCount: Int
    ) -> String {
        AXWindowInspector.windowsFetchLogDetails(
            error: error,
            rawValueTypeDescription: rawValueTypeDescription,
            rawArrayCount: rawArrayCount,
            decodedCount: decodedCount
        )
    }
}
