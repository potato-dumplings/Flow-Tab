import AppKit
import FlowTabCore
import SwiftUI
import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func makeSettingsPresentationLayoutHost(
        recorder: SettingsPresentationUpdateRecorder
    ) -> NSHostingView<SettingsPresentationObservedContent<some View>> {
        let hostedView = NSHostingView(
            rootView: SettingsPresentationObservedContent(
                content: HomeRootView()
                    .frame(width: 1_440, height: 900, alignment: .topLeading),
                recorder: recorder
            )
        )
        hostedView.frame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        hostedView.layoutSubtreeIfNeeded()
        return hostedView
    }

    func settingsPresentationLayoutContainer(
        in root: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AppKitSettingsPageContainerView {
        let containers = settingsPresentationLayoutDescendants(in: root)
            .compactMap { $0 as? AppKitSettingsPageContainerView }
        XCTAssertEqual(containers.count, 1, file: file, line: line)
        return try XCTUnwrap(containers.first, file: file, line: line)
    }

    func settleSettingsPresentationLayout(
        _ container: AppKitSettingsPageContainerView
    ) {
        for _ in 0..<4 {
            container.layout()
            container.layoutSubtreeIfNeeded()
        }
    }

    func settingsPresentationLayoutCardFrames(
        in view: NSView,
        relativeTo ancestor: NSView
    ) -> [String: NSRect] {
        var frames: [String: NSRect] = [:]
        for title in [
            "外观",
            "窗口行为",
            "权限",
            "搜索",
            "应用可见性",
            "快捷键",
            "Appearance",
            "Window Behavior",
            "Permissions",
            "Search",
            "App Visibility",
            "Hotkeys"
        ] {
            guard let card = settingsPresentationLayoutDescendants(in: view)
                .compactMap({ $0 as? FlowSettingsCardView })
                .first(where: {
                    settingsPresentationLayoutTextValues(in: $0)
                        .contains(title)
                })
            else {
                continue
            }
            frames[title] = settingsPresentationVisualFrame(
                of: card,
                relativeTo: ancestor
            )
        }
        return frames
    }

    func assertSettingsPresentationLayoutFrame(
        _ actual: NSRect,
        equals expected: NSRect,
        accuracy: CGFloat = 1,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            actual.origin.x,
            expected.origin.x,
            accuracy: accuracy,
            "\(message) x",
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.origin.y,
            expected.origin.y,
            accuracy: accuracy,
            "\(message) y",
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.size.width,
            expected.size.width,
            accuracy: accuracy,
            "\(message) width",
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.size.height,
            expected.size.height,
            accuracy: accuracy,
            "\(message) height",
            file: file,
            line: line
        )
    }

    func assertSettingsPresentationCardsStayNearHeader(
        in view: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let subtitle = try XCTUnwrap(
            settingsPresentationLayoutDescendants(in: view)
                .first(where: {
                    $0.identifier?.rawValue == "flowtab.settings.page.subtitle"
                        || $0.accessibilityIdentifier()
                            == "flowtab.settings.page.subtitle"
                }),
            file: file,
            line: line
        )
        let subtitleFrame = settingsPresentationVisualFrame(
            of: subtitle,
            relativeTo: view
        )
        let cardFrames = settingsPresentationLayoutCards(in: view).map {
            settingsPresentationVisualFrame(of: $0, relativeTo: view)
        }
        let firstCardTop = cardFrames.map(\.minY).min() ?? .infinity
        let gapBelowSubtitle = firstCardTop - subtitleFrame.maxY
        XCTAssertGreaterThanOrEqual(gapBelowSubtitle, -1, file: file, line: line)
        XCTAssertLessThan(gapBelowSubtitle, 60, file: file, line: line)
    }

    func assertSettingsPresentationCardsDoNotOverlap(
        _ cards: [FlowSettingsCardView],
        in ancestor: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frames = cards.map { $0.convert($0.bounds, to: ancestor) }
        for index in frames.indices {
            for otherIndex in frames.indices where otherIndex > index {
                let intersection = frames[index].intersection(frames[otherIndex])
                XCTAssertTrue(
                    intersection.isNull
                        || intersection.width <= 1
                        || intersection.height <= 1,
                    "Settings cards overlap: \(frames[index]) and \(frames[otherIndex])",
                    file: file,
                    line: line
                )
            }
        }
    }

    func assertSettingsPresentationArrangedSubviewsDoNotOverlap(
        in view: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for stackView in settingsPresentationLayoutDescendants(in: view)
        .compactMap({ $0 as? NSStackView }) {
            let visibleSubviews = stackView.arrangedSubviews.filter {
                !$0.isHidden && !$0.frame.isEmpty
            }
            for index in visibleSubviews.indices {
                for otherIndex in visibleSubviews.indices
                where otherIndex > index {
                    let first = visibleSubviews[index]
                        .convert(visibleSubviews[index].bounds, to: stackView)
                    let second = visibleSubviews[otherIndex]
                        .convert(
                            visibleSubviews[otherIndex].bounds,
                            to: stackView
                        )
                    let intersection = first.intersection(second)
                    XCTAssertTrue(
                        intersection.isNull
                            || intersection.width <= 1
                            || intersection.height <= 1,
                        "Arranged subviews overlap: \(first) and \(second)",
                        file: file,
                        line: line
                    )
                }
            }
        }
    }

    func settingsPresentationLayoutCards(
        in view: NSView
    ) -> [FlowSettingsCardView] {
        settingsPresentationLayoutDescendants(in: view)
            .compactMap { $0 as? FlowSettingsCardView }
    }

    func settingsPresentationLayoutIsDark(
        _ container: AppKitSettingsPageContainerView
    ) -> Bool {
        guard container.appearance?.isFlowTabDarkInterface == true else {
            return false
        }
        return settingsPresentationLayoutCards(in: container.pageView)
            .contains { card in
                guard let backgroundColor = card.layer?.backgroundColor,
                      let color = NSColor(cgColor: backgroundColor)?
                        .usingColorSpace(.sRGB)
                else {
                    return false
                }
                return color.redComponent < 0.3
                    && color.greenComponent < 0.3
                    && color.blueComponent < 0.3
            }
    }

    @MainActor
    func postSettingsPresentationSystemAppearanceChanged() {
        SystemThemeState.shared.refreshColorScheme()
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    func restoreSettingsPresentationLayoutDefault(
        _ value: String?,
        forKey key: String
    ) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func settingsPresentationLayoutTextValues(
        in view: NSView
    ) -> Set<String> {
        Set(
            settingsPresentationLayoutDescendants(in: view).compactMap {
                descendant in
                if let textField = descendant as? NSTextField {
                    return textField.stringValue.isEmpty
                        ? nil
                        : textField.stringValue
                }
                if let button = descendant as? NSButton {
                    return button.title.isEmpty ? nil : button.title
                }
                return nil
            }
        )
    }

    private func settingsPresentationVisualFrame(
        of view: NSView,
        relativeTo ancestor: NSView
    ) -> NSRect {
        let rawFrame = view.convert(view.bounds, to: ancestor)
        return NSRect(
            x: rawFrame.minX,
            y: ancestor.bounds.height - rawFrame.maxY,
            width: rawFrame.width,
            height: rawFrame.height
        )
    }

    private func settingsPresentationLayoutDescendants(
        in view: NSView
    ) -> [NSView] {
        [view] + view.subviews.flatMap {
            settingsPresentationLayoutDescendants(in: $0)
        }
    }
}
