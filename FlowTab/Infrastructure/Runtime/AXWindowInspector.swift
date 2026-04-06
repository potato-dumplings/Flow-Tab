import AppKit
import ApplicationServices
import Foundation

enum AXWindowInspector {
    private static let windowIDPrefix = "ax"

    static func windows(for app: NSRunningApplication) -> [AXUIElement] {
        guard AccessibilityPermissionChecker.isTrusted() else { return [] }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
                == .success,
            let windows = windowsValue as? [AXUIElement]
        else {
            return []
        }
        return windows
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
        var titleValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
                == .success,
            let title = (titleValue as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty
        else {
            return nil
        }
        return title
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

    static func frame(for window: AXUIElement) -> CGRect? {
        AXWindowInspector.frame(for: window)
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
}
