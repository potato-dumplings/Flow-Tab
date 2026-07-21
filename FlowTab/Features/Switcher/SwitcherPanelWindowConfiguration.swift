import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

final class SwitcherOverlayPanel: NSPanel {
    private var switcherAppAccessibilityElements: [String: NSAccessibilityElement] = [:]
    private var orderedSwitcherAppIDs: [String] = []
    private var switcherAppTileSize: CGFloat = 1
    private var switcherAppTileSpacing: CGFloat = 0
    private var switcherAppStripHeaderOffset: CGFloat = 0

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    func updateSwitcherAccessibilityApps(
        _ apps: [AppSwitchCandidate],
        tileSize: CGFloat,
        spacing: CGFloat,
        appStripHeaderOffset: CGFloat
    ) {
        let visibleAppIDs = Set(apps.map(\.id))

        for appID in Array(switcherAppAccessibilityElements.keys) where !visibleAppIDs.contains(appID) {
            switcherAppAccessibilityElements.removeValue(forKey: appID)
        }

        orderedSwitcherAppIDs = apps.map(\.id)
        switcherAppTileSize = max(1, tileSize)
        switcherAppTileSpacing = max(0, spacing)
        switcherAppStripHeaderOffset = max(0, appStripHeaderOffset)
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
        let availableWidth = max(1, baseFrame.width - SwitcherPanelLayoutMetrics.horizontalInset)
        let tileCount = CGFloat(orderedSwitcherAppIDs.count)
        let contentWidth =
            tileCount * switcherAppTileSize
            + max(0, tileCount - 1) * switcherAppTileSpacing
        let startX =
            baseFrame.minX
            + SwitcherPanelLayoutMetrics.rootPadding
            + SwitcherPanelLayoutMetrics.bodyHorizontalPadding
            + max(0, (availableWidth - contentWidth) / 2)
        let originY =
            baseFrame.maxY
            - SwitcherPanelLayoutMetrics.rootPadding
            - SwitcherPanelLayoutMetrics.bodyVerticalPadding
            - switcherAppStripHeaderOffset
            - switcherAppTileSize

        for (index, appID) in orderedSwitcherAppIDs.enumerated() {
            guard let element = switcherAppAccessibilityElements[appID] else { continue }
            element.setAccessibilityFrame(
                NSRect(
                    x: startX + CGFloat(index) * (switcherAppTileSize + switcherAppTileSpacing),
                    y: originY,
                    width: switcherAppTileSize,
                    height: switcherAppTileSize
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
    static var sharingType: NSWindow.SharingType {
#if FLOWTAB_TESTING
        resolvedSharingType(isRunningUITests: FlowTabTestLaunchOptions.isRunningUITests)
#else
        .none
#endif
    }
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
        frontmostWindowIsFullScreen: Bool
    ) -> NSWindow.Level {
        guard frontmostWindowIsFullScreen else { return level }
        return fallbackPresentationLevel
    }

    static func resolvedSharingType(isRunningUITests: Bool) -> NSWindow.SharingType {
        isRunningUITests ? .readOnly : .none
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
