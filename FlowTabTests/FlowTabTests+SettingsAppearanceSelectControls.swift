import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabTests {
    @MainActor
    func testSettingsColorResolverUsesTargetAppearanceInsteadOfHostAppearance() throws {
        let hostAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let targetAppearance = FlowSettingsStyleResolver.targetAppearance(
            named: .aqua,
            fallback: hostAppearance
        )
        let resolvedColor = FlowSettingsStyleResolver.color(
            .rgb(
                light: FlowSettingsRGBColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1),
                dark: FlowSettingsRGBColor(red: 0.8, green: 0.7, blue: 0.6, alpha: 1)
            ),
            appearance: targetAppearance
        ).usingColorSpace(.sRGB)

        XCTAssertEqual(targetAppearance.bestMatch(from: [.darkAqua, .aqua]), .aqua)
        XCTAssertEqual(resolvedColor?.redComponent ?? 0, 0.1, accuracy: 0.001)
        XCTAssertEqual(resolvedColor?.greenComponent ?? 0, 0.2, accuracy: 0.001)
        XCTAssertEqual(resolvedColor?.blueComponent ?? 0, 0.3, accuracy: 0.001)
    }

    func testSettingsStateStylesFallbackToNormalState() {
        let normal = FlowSettingsResolvedStyle(
            text: FlowSettingsTextToken(
                font: .systemFont(ofSize: 11),
                color: .semantic(.label, alpha: 1),
                alignment: .center,
                lineBreakMode: .byClipping
            ),
            surface: nil,
            gradient: nil
        )
        let styles = FlowSettingsStateStyle(
            values: [.normal: normal],
            fallback: FlowSettingsActionButtonState.normal
        )

        XCTAssertEqual(styles.value(for: .pressed).text?.font.pointSize, 11)
        XCTAssertEqual(
            FlowSettingsActionButtonStyle.preset(.primaryAction).states.value(for: .disabled).text?.font.pointSize,
            FlowSettingsActionButtonStyle.preset(.primaryAction).states.value(for: .normal).text?.font.pointSize
        )
        XCTAssertNotNil(FlowSettingsSelectStyle.preset(.formSelect).states.value(for: .expanded).surface)
    }

    @MainActor
    func testSettingsComponentMetricsUseContentAndMinimumWidths() {
        let actionButton = FlowSettingsActionButton()
        actionButton.update(
            title: "Request Accessibility permission",
            accessibilityLabel: nil,
            style: .preset(.secondaryAction)
        )
        let compactActionButton = FlowSettingsActionButton()
        compactActionButton.update(
            title: "管理",
            accessibilityLabel: nil,
            style: .preset(.compactSecondaryAction)
        )
        let selectControl = FlowSettingsSelectControl(frame: .zero)
        selectControl.configure(
            options: [
                (id: "zh-Hans", title: "简体中文"),
                (id: "en", title: "English")
            ]
        )

        XCTAssertGreaterThan(actionButton.intrinsicContentSize.width, 160)
        XCTAssertGreaterThanOrEqual(compactActionButton.intrinsicContentSize.width, 68)
        XCTAssertGreaterThanOrEqual(selectControl.intrinsicContentSize.width, 84)
    }

    @MainActor
    func testSettingsActionButtonRefreshesTextStatesAndAccessibility() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let button = FlowSettingsActionButton()
        button.applySettingsAppearance(appearance)
        button.update(
            title: "Manage",
            accessibilityLabel: "Manage Accessibility permission",
            tooltip: "Manage Accessibility permission",
            style: .preset(.primaryAction)
        )

        XCTAssertEqual(button.title, "Manage")
        XCTAssertEqual(button.accessibilityLabel(), "Manage Accessibility permission")
        XCTAssertEqual(button.toolTip, "Manage Accessibility permission")
        XCTAssertEqual(button.attributedAlternateTitle.string, "Manage")
        assertButtonTitleColor(button.attributedTitle, expectedInk: .light, appearance: appearance)

        button.isEnabled = false
        XCTAssertFalse(button.attributedTitle.string.contains("\n"))
        XCTAssertEqual(button.attributedAlternateTitle.string, button.attributedTitle.string)
    }

    @MainActor
    func testSettingsActionButtonUsesSingleMainLayerBorder() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let button = FlowSettingsActionButton()
        button.applySettingsAppearance(appearance)
        button.update(
            title: AppStrings.text(.appVisibilityManage, language: .simplifiedChinese),
            accessibilityLabel: nil,
            style: .preset(.compactSecondaryAction)
        )
        button.frame = NSRect(origin: .zero, size: button.intrinsicContentSize)
        button.layoutSubtreeIfNeeded()

        let extraBorderLayers = button.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }
            .filter { $0.lineWidth > 0 && $0.strokeColor != nil } ?? []

        XCTAssertEqual(button.layer?.borderWidth, 1)
        XCTAssertTrue(extraBorderLayers.isEmpty, "Action buttons should not draw a second custom border layer.")
    }

    @MainActor
    func testSettingsSelectControlsUseApplicationThemeWhenSystemAppearanceDiffers() throws {
        try assertSettingsSelectControls(
            hostAppearanceName: .darkAqua,
            themeMode: .light,
            expectedAppearanceName: .aqua,
            expectedInk: .dark
        )
        try assertSettingsSelectControls(
            hostAppearanceName: .aqua,
            themeMode: .dark,
            expectedAppearanceName: .darkAqua,
            expectedInk: .light
        )
    }

    @MainActor
    func testSettingsFollowSystemDoesNotReusePreviousExplicitAppearance() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 820),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        let container = AppKitSettingsPageContainerView()
        container.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 1_200, height: 820)
        window.contentView = container

        container.update(
            with: makeSettingsPageState(themeModeRaw: ThemeMode.dark.rawValue),
            isActive: true
        )
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(container.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), .darkAqua)

        container.update(
            with: makeSettingsPageState(themeModeRaw: ThemeMode.followSystem.rawValue),
            isActive: true
        )
        container.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            container.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]),
            .aqua
        )
    }

    @MainActor
    func testSettingsManageButtonUsesApplicationThemeAfterLanguageChange() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 820),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        let container = AppKitSettingsPageContainerView()
        container.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 1_200, height: 820)
        window.contentView = container
        container.update(
            with: makeSettingsPageState(
                themeModeRaw: ThemeMode.dark.rawValue,
                language: .english
            ),
            isActive: true
        )
        container.layoutSubtreeIfNeeded()
        container.update(
            with: makeSettingsPageState(
                themeModeRaw: ThemeMode.dark.rawValue,
                language: .simplifiedChinese
            ),
            isActive: true
        )
        container.layoutSubtreeIfNeeded()

        let manageButton: NSButton = try XCTUnwrap(
            descendant(in: container, identifier: "flowtab.settings.app-visibility.manage")
        )
        XCTAssertEqual(
            container.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]),
            .darkAqua
        )
        XCTAssertEqual(manageButton.attributedTitle.string, "管理")
        assertButtonTitleColor(
            manageButton.attributedTitle,
            expectedInk: .light,
            appearance: manageButton.effectiveAppearance
        )
        XCTAssertEqual(manageButton.attributedAlternateTitle.string, manageButton.attributedTitle.string)
        assertButtonTitleColor(
            manageButton.attributedAlternateTitle,
            expectedInk: .light,
            appearance: manageButton.effectiveAppearance
        )
    }

    private enum ExpectedSettingsSelectInk {
        case dark
        case light
    }

    @MainActor
    private func assertSettingsSelectControls(
        hostAppearanceName: NSAppearance.Name,
        themeMode: ThemeMode,
        expectedAppearanceName: NSAppearance.Name,
        expectedInk: ExpectedSettingsSelectInk,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 820),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: hostAppearanceName)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        let container = AppKitSettingsPageContainerView()
        container.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 1_200, height: 820)
        window.contentView = container
        container.update(
            with: makeSettingsPageState(themeModeRaw: themeMode.rawValue),
            isActive: true
        )
        container.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            container.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]),
            expectedAppearanceName,
            file: file,
            line: line
        )

        let selectIdentifiers = [
            "flowtab.settings.appearance.app-language",
            "flowtab.settings.search.default-scope",
            "flowtab.settings.hotkey.main-modifier"
        ]

        for identifier in selectIdentifiers {
            let selectControl: FlowSettingsSelectControl = try XCTUnwrap(
                descendant(in: container, identifier: identifier),
                "Missing select control \(identifier)",
                file: file,
                line: line
            )
            selectControl.layoutSubtreeIfNeeded()
            XCTAssertEqual(
                selectControl.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]),
                expectedAppearanceName,
                file: file,
                line: line
            )

            let popUpButton: NSPopUpButton = try XCTUnwrap(
                descendant(in: selectControl, as: NSPopUpButton.self),
                "Missing popup button for \(identifier)",
                file: file,
                line: line
            )
            assertColor(popUpButton.contentTintColor, resolvesTo: expectedInk, in: selectControl.effectiveAppearance)
            XCTAssertFalse(popUpButton.itemArray.isEmpty, "Expected system NSMenu options", file: file, line: line)
        }
    }

    private func makeSettingsPageState(
        themeModeRaw: String,
        language: AppLanguage = .simplifiedChinese
    ) -> AppKitSettingsPageState {
        AppKitSettingsPageState(
            showShortcutHint: true,
            showInCommandTab: true,
            themeModeRaw: themeModeRaw,
            appLanguageRaw: language.rawValue,
            windowLayerAutoEnterDelayText: "0.3",
            autoRestoreMinimizedWindowOnSwitch: true,
            hideMinimizedAppsFromAppLayer: false,
            showPermissionReminder: true,
            allowLaunchAtLogin: false,
            searchEnabled: true,
            searchDefaultScopeRaw: SwitcherSearchScope.app.rawValue,
            hiddenAppCount: 2,
            hotkeyPrimaryModifierRaw: SwitcherPrimaryModifier.option.rawValue,
            hotkeyMainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            hotkeyQuitKeyRaw: SwitcherHotkeyKey.q.rawValue,
            inAppWindowHotkeyPrimaryModifierRaw: SwitcherPrimaryModifier.control.rawValue,
            inAppWindowHotkeyMainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            commandTabTakeoverActive: false,
            accessibilityTrusted: false,
            screenCaptureTrusted: false,
            targetNSAppearanceName: ThemePreferencesStore.resolve(rawValue: themeModeRaw) == .dark
                ? .darkAqua
                : .aqua
        )
    }

    private func assertButtonTitleColor(
        _ title: NSAttributedString,
        expectedInk: ExpectedSettingsSelectInk,
        appearance: NSAppearance,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(title.string.isEmpty, "Expected non-empty attributed title", file: file, line: line)
        let color = title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        assertColor(color, resolvesTo: expectedInk, in: appearance, file: file, line: line)
    }

    private func assertColor(
        _ color: NSColor?,
        resolvesTo expectedInk: ExpectedSettingsSelectInk,
        in appearance: NSAppearance,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var resolvedColor: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = color?.usingColorSpace(.sRGB)
        }
        guard let resolvedColor else {
            XCTFail("Expected comparable sRGB color", file: file, line: line)
            return
        }

        let luminance = resolvedColor.redComponent * 0.2126
            + resolvedColor.greenComponent * 0.7152
            + resolvedColor.blueComponent * 0.0722

        switch expectedInk {
        case .dark:
            XCTAssertLessThan(luminance, 0.45, file: file, line: line)
        case .light:
            XCTAssertGreaterThan(luminance, 0.55, file: file, line: line)
        }
    }

    private func descendantViews(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendantViews(in: $0) }
    }

    private func descendant<T: NSView>(
        in view: NSView,
        identifier: String,
        as type: T.Type = T.self
    ) -> T? {
        if view.identifier?.rawValue == identifier || view.accessibilityIdentifier() == identifier {
            return view as? T
        }
        for subview in view.subviews {
            if let match: T = descendant(in: subview, identifier: identifier, as: type) {
                return match
            }
        }
        return nil
    }

    private func descendant<T: NSView>(
        in view: NSView,
        as type: T.Type = T.self
    ) -> T? {
        if let match = view as? T {
            return match
        }
        for subview in view.subviews {
            if let match: T = descendant(in: subview, as: type) {
                return match
            }
        }
        return nil
    }
}
