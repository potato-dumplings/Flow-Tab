import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabTests {
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
            let selectControl: FlowFormSelectControl = try XCTUnwrap(
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

            let titleLabel: NSTextField = try XCTUnwrap(
                descendant(in: selectControl, as: NSTextField.self),
                "Missing title label for \(identifier)",
                file: file,
                line: line
            )
            assertColor(titleLabel.textColor, resolvesTo: expectedInk, in: selectControl.effectiveAppearance)

            let chevronImageView: NSImageView = try XCTUnwrap(
                descendant(in: selectControl, as: NSImageView.self),
                "Missing chevron for \(identifier)",
                file: file,
                line: line
            )
            assertColor(chevronImageView.contentTintColor, resolvesTo: expectedInk, in: selectControl.effectiveAppearance)

            try assertSelectMenuButtonsResolveToExpectedInk(
                selectControl,
                expectedInk: expectedInk,
                file: file,
                line: line
            )
        }
    }

    @MainActor
    private func assertSelectMenuButtonsResolveToExpectedInk(
        _ selectControl: FlowFormSelectControl,
        expectedInk: ExpectedSettingsSelectInk,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let window = try XCTUnwrap(selectControl.window, file: file, line: line)
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: selectControl.bounds.midX, y: selectControl.bounds.midY),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ),
            file: file,
            line: line
        )
        selectControl.mouseDown(with: event)
        defer {
            selectControl.mouseDown(with: event)
        }

        let menuView = try XCTUnwrap(
            selectMenuView(for: selectControl),
            file: file,
            line: line
        )
        menuView.appearance = selectControl.effectiveAppearance
        menuView.layoutSubtreeIfNeeded()

        let optionPrefix = "\(selectControl.identifier?.rawValue ?? "").option."
        let optionButtons = NSApp.windows
            .compactMap(\.contentView)
            .flatMap { descendantViews(in: $0) } + descendantViews(in: menuView)
        let menuButtons = optionButtons
            .compactMap { $0 as? NSButton }
            .filter { $0.identifier?.rawValue.hasPrefix(optionPrefix) == true }

        XCTAssertFalse(menuButtons.isEmpty, "Missing menu option buttons", file: file, line: line)
        let selectedOptionID = selectedOptionID(for: selectControl.identifier?.rawValue)
        for button in menuButtons {
            XCTAssertFalse(button.attributedTitle.string.isEmpty, "Expected non-empty attributed title", file: file, line: line)
            XCTAssertFalse(
                button.attributedAlternateTitle.string.isEmpty,
                "Expected non-empty attributed alternate title",
                file: file,
                line: line
            )
            guard button.identifier?.rawValue != selectedOptionID.map({ "\(optionPrefix)\($0)" }) else {
                continue
            }
            assertButtonTitleColor(
                button.attributedTitle,
                expectedInk: expectedInk,
                appearance: button.effectiveAppearance,
                file: file,
                line: line
            )
            assertButtonTitleColor(
                button.attributedAlternateTitle,
                expectedInk: expectedInk,
                appearance: button.effectiveAppearance,
                file: file,
                line: line
            )
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
            screenCaptureTrusted: false
        )
    }

    private func selectMenuView(for selectControl: FlowFormSelectControl) -> NSView? {
        mirroredChild(named: "menuViewController", in: selectControl)
            .flatMap { $0 as? NSViewController }?
            .view
    }

    private func mirroredChild(named name: String, in value: Any) -> Any? {
        var mirror: Mirror? = Mirror(reflecting: value)
        while let currentMirror = mirror {
            if let child = currentMirror.children.first(where: { $0.label == name }) {
                return child.value
            }
            mirror = currentMirror.superclassMirror
        }
        return nil
    }

    private func selectedOptionID(for selectControlIdentifier: String?) -> String? {
        switch selectControlIdentifier {
        case "flowtab.settings.appearance.app-language":
            return AppLanguage.simplifiedChinese.rawValue
        case "flowtab.settings.search.default-scope":
            return SwitcherSearchScope.app.rawValue
        case "flowtab.settings.hotkey.main-modifier":
            return SwitcherPrimaryModifier.option.rawValue
        default:
            return nil
        }
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
