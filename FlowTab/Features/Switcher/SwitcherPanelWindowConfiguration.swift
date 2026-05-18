import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

final class SwitcherOverlayPanel: NSPanel {
    private var switcherAppAccessibilityElements: [String: NSAccessibilityElement] = [:]
    private var orderedSwitcherAppIDs: [String] = []

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    func updateSwitcherAccessibilityApps(_ apps: [AppSwitchCandidate]) {
        let visibleAppIDs = Set(apps.map(\.id))

        for appID in Array(switcherAppAccessibilityElements.keys) where !visibleAppIDs.contains(appID) {
            switcherAppAccessibilityElements.removeValue(forKey: appID)
        }

        orderedSwitcherAppIDs = apps.map(\.id)
        for app in apps {
            let element = switcherAppAccessibilityElements[app.id] ?? NSAccessibilityElement()
            configureSwitcherAccessibilityElement(
                element,
                identifier: SwitcherAccessibilityIdentifiers.app(id: app.id),
                label: app.displayName,
                value: "\(app.id), \(app.windows.count)w"
            )
            switcherAppAccessibilityElements[app.id] = element
        }

        updateSwitcherAccessibilityFrames()
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        updateSwitcherAccessibilityFrames()
    }

    override func accessibilityChildren() -> [Any]? {
        switcherAccessibilityChildren()
    }

    private func switcherAccessibilityChildren() -> [Any] {
        let appElements = orderedSwitcherAppIDs.compactMap { switcherAppAccessibilityElements[$0] }
        guard !appElements.isEmpty else { return super.accessibilityChildren() ?? [] }
        return (super.accessibilityChildren() ?? []) + appElements
    }

    private func updateSwitcherAccessibilityFrames() {
        let baseFrame = frame
        for (index, appID) in orderedSwitcherAppIDs.enumerated() {
            guard let element = switcherAppAccessibilityElements[appID] else { continue }
            element.setAccessibilityFrame(
                NSRect(
                    x: baseFrame.minX + CGFloat(index + 1),
                    y: baseFrame.minY + 1,
                    width: 1,
                    height: 1
                )
            )
        }
    }

    private func configureSwitcherAccessibilityElement(
        _ element: NSAccessibilityElement,
        identifier: String,
        label: String,
        value: String?
    ) {
        element.setAccessibilityParent(self)
        element.setAccessibilityRole(.group)
        element.setAccessibilityIdentifier(identifier)
        element.setAccessibilityLabel(label)
        element.setAccessibilityValue(value ?? "")
    }
}

enum SwitcherPanelWindowConfiguration {
    enum PresentationBehaviorMode {
        case allSpaces
        case activeSpaceMove
    }

    static let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    static let level: NSWindow.Level = .statusBar
    static let sharingType: NSWindow.SharingType = .none
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
        guard case .success(let focusedWindow) = AXTypedAttributeReader.axElement(
            from: focusedWindowValue,
            attribute: kAXFocusedWindowAttribute as CFString
        ) else {
            return Inspection(
                axTrusted: true,
                appName: appName,
                pid: app.processIdentifier,
                focusedWindowAvailable: false,
                focusedWindowTitle: nil,
                fullScreenDetected: false,
                failureReason: "focused_window_type_mismatch"
            )
        }

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
