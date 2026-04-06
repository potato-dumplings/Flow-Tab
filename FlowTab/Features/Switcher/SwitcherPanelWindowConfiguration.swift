import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

final class SwitcherOverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

enum SwitcherPanelWindowConfiguration {
    enum PresentationBehaviorMode {
        case allSpaces
        case activeSpaceMove
    }

    static let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    static let level: NSWindow.Level = .statusBar
    static let fallbackPresentationLevel = NSWindow.Level(
        rawValue: Int(CGShieldingWindowLevel()) + 1
    )
    // Keep the proven panel presentation behavior and only add the explicit
    // cross-application fullscreen-space eligibility we were missing.
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .ignoresCycle,
        .stationary,
        .canJoinAllApplications
    ]

    static func presentationLevel(
        frontmostWindowIsFullScreen: Bool,
        requiresFallbackElevation: Bool = false
    ) -> NSWindow.Level {
        guard frontmostWindowIsFullScreen || requiresFallbackElevation else { return level }
        return fallbackPresentationLevel
    }

    static func presentationCollectionBehavior(
        mode: PresentationBehaviorMode = .allSpaces
    ) -> NSWindow.CollectionBehavior {
        switch mode {
        case .allSpaces:
            return collectionBehavior
        case .activeSpaceMove:
            var behavior = collectionBehavior
            behavior.remove(.canJoinAllSpaces)
            behavior.insert(.moveToActiveSpace)
            return behavior
        }
    }
}

enum FrontmostWindowInspector {
    private static let fullScreenAttribute = "AXFullScreen" as CFString
    private static let titleAttribute = kAXTitleAttribute as CFString

    struct Inspection {
        let axTrusted: Bool
        let appName: String
        let pid: pid_t?
        let focusedWindowAvailable: Bool
        let focusedWindowTitle: String?
        let fullScreenDetected: Bool
        let failureReason: String?
    }

    static func inspect() -> Inspection {
        guard AccessibilityPermissionChecker.isTrusted() else {
            return Inspection(
                axTrusted: false,
                appName: "unavailable",
                pid: nil,
                focusedWindowAvailable: false,
                focusedWindowTitle: nil,
                fullScreenDetected: false,
                failureReason: "ax_not_trusted"
            )
        }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return Inspection(
                axTrusted: true,
                appName: "unavailable",
                pid: nil,
                focusedWindowAvailable: false,
                focusedWindowTitle: nil,
                fullScreenDetected: false,
                failureReason: "frontmost_app_unavailable"
            )
        }

        let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindowValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedWindowAttribute as CFString,
                &focusedWindowValue
            ) == .success,
            let focusedWindowValue
        else {
            return Inspection(
                axTrusted: true,
                appName: appName,
                pid: app.processIdentifier,
                focusedWindowAvailable: false,
                focusedWindowTitle: nil,
                fullScreenDetected: false,
                failureReason: "focused_window_unavailable"
            )
        }
        let focusedWindow = focusedWindowValue as! AXUIElement

        var titleValue: CFTypeRef?
        let focusedWindowTitle: String?
        if
            AXUIElementCopyAttributeValue(
                focusedWindow,
                titleAttribute,
                &titleValue
            ) == .success,
            let title = titleValue as? String,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            focusedWindowTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            focusedWindowTitle = nil
        }

        var fullScreenValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                focusedWindow,
                fullScreenAttribute,
                &fullScreenValue
            ) == .success,
            let number = fullScreenValue as? NSNumber
        else {
            return Inspection(
                axTrusted: true,
                appName: appName,
                pid: app.processIdentifier,
                focusedWindowAvailable: true,
                focusedWindowTitle: focusedWindowTitle,
                fullScreenDetected: false,
                failureReason: "fullscreen_attribute_unavailable"
            )
        }
        return Inspection(
            axTrusted: true,
            appName: appName,
            pid: app.processIdentifier,
            focusedWindowAvailable: true,
            focusedWindowTitle: focusedWindowTitle,
            fullScreenDetected: number.boolValue,
            failureReason: nil
        )
    }

    static func frontmostWindowIsFullScreen() -> Bool {
        inspect().fullScreenDetected
    }
}
