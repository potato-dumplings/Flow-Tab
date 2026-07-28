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
        let compactActionButton = FlowCompactActionButtonControl()
        compactActionButton.configure(
            title: "管理",
            accessibilityLabel: nil,
            presentation: .compact(targetAppearance: NSAppearance(named: .aqua) ?? NSApp.effectiveAppearance)
        )
        let selectControl = FlowSettingsSelectControl(frame: .zero)
        selectControl.configure(
            options: [
                (id: "a", title: "A"),
                (id: "b", title: "B")
            ]
        )

        XCTAssertGreaterThan(actionButton.intrinsicContentSize.width, 160)
        XCTAssertGreaterThanOrEqual(compactActionButton.intrinsicContentSize.width, 68)
        XCTAssertEqual(
            selectControl.intrinsicContentSize.width,
            FlowDropdownMetrics.defaultMinimumWidth,
            accuracy: 0.001
        )
    }

    @MainActor
    func testSettingsSelectIntrinsicWidthLeavesRoomForTitleAndChevron() throws {
        let selectControl = FlowSettingsSelectControl(frame: .zero)
        selectControl.configure(
            options: [
                (id: "zh-Hans", title: "简体中文"),
                (id: "en", title: "English")
            ]
        )
        selectControl.updateSelection(id: "zh-Hans")
        selectControl.frame = NSRect(origin: .zero, size: selectControl.intrinsicContentSize)
        selectControl.layoutSubtreeIfNeeded()

        let dropdownControl: FlowDropdownControl = try XCTUnwrap(
            descendant(in: selectControl, as: FlowDropdownControl.self)
        )
        let titleLabel = NSTextField(labelWithString: "简体中文")
        titleLabel.font = FlowTypography.appKit(.controlText)
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alignment = .center
        let titleWidth = try XCTUnwrap(titleLabel.cell).cellSize.width

        XCTAssertGreaterThanOrEqual(dropdownControl.titleFrameForTesting.width, ceil(titleWidth))
    }

    @MainActor
    func testCompactActionButtonPresentationRespectsTheme() throws {
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let lightPresentation = FlowCompactActionButtonPresentation.compact(targetAppearance: lightAppearance)
        let darkPresentation = FlowCompactActionButtonPresentation.compact(targetAppearance: darkAppearance)

        let lightStyle = lightPresentation.style(for: .normal)
        let darkStyle = darkPresentation.style(for: .normal)

        assertColor(lightStyle.textColor, resolvesTo: .dark, in: lightAppearance)
        assertColor(darkStyle.textColor, resolvesTo: .light, in: darkAppearance)
        assertDropdownColor(lightStyle.backgroundColor, matches: NSColor.white.withAlphaComponent(0.96))
        assertDropdownColor(darkStyle.backgroundColor, matches: NSColor.white.withAlphaComponent(0.12))
        assertDropdownColor(lightStyle.borderColor, matches: NSColor.black.withAlphaComponent(0.12))
        assertDropdownColor(darkStyle.borderColor, matches: NSColor.white.withAlphaComponent(0.18))
    }

    @MainActor
    func testFlowDropdownKeepsSelectionByStableIDWhenTitlesRefresh() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let presentation = FlowDropdownPresentation.form(targetAppearance: appearance)
        let control = FlowDropdownControl(frame: NSRect(x: 0, y: 0, width: 180, height: 32))
        control.configure(
            options: [
                FlowDropdownOption(id: "zh-Hans", title: "Simplified Chinese"),
                FlowDropdownOption(id: "en", title: "English")
            ],
            selectedID: "zh-Hans",
            presentation: presentation
        )

        control.configure(
            options: [
                FlowDropdownOption(id: "zh-Hans", title: "简体中文"),
                FlowDropdownOption(id: "en", title: "English")
            ],
            selectedID: control.selectedIdentifierForTesting,
            presentation: presentation
        )

        XCTAssertEqual(control.selectedIdentifierForTesting, "zh-Hans")
        XCTAssertEqual(control.selectedTitleForTesting, "简体中文")
        XCTAssertEqual(presentation.metrics.minimumWidth, FlowDropdownMetrics.defaultMinimumWidth)
        XCTAssertGreaterThanOrEqual(control.intrinsicContentSize.width, FlowDropdownMetrics.defaultMinimumWidth)
        XCTAssertLessThan(control.intrinsicContentSize.width, 132)

        let menuView = FlowDropdownMenuView(
            options: [
                FlowDropdownOption(id: "zh-Hans", title: "Simplified Chinese"),
                FlowDropdownOption(id: "en", title: "English")
            ],
            selectedID: "zh-Hans",
            controlIdentifier: "flowtab.test.dropdown",
            presentation: presentation
        )
        menuView.configure(
            options: [
                FlowDropdownOption(id: "zh-Hans", title: "简体中文"),
                FlowDropdownOption(id: "en", title: "English")
            ],
            selectedID: "zh-Hans",
            controlIdentifier: "flowtab.test.dropdown",
            presentation: presentation
        )

        XCTAssertEqual(menuView.rowsForTesting.first?.titleForTesting, "简体中文")
        XCTAssertEqual(
            menuView.rowsForTesting.first?.accessibilityIdentifier(),
            "flowtab.test.dropdown.option.zh-Hans"
        )
    }

    @MainActor
    func testFlowDropdownCentersTextAndKeepsNormalRowsUnfilled() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let presentation = FlowDropdownPresentation.form(targetAppearance: appearance)
        let options = [
            FlowDropdownOption(id: "option", title: "Option"),
            FlowDropdownOption(id: "control", title: "Control"),
            FlowDropdownOption(id: "command", title: "Command")
        ]
        let control = FlowDropdownControl(frame: NSRect(x: 0, y: 0, width: 180, height: 32))
        control.configure(options: options, selectedID: "option", presentation: presentation)
        control.layoutSubtreeIfNeeded()

        XCTAssertEqual(control.titleFrameForTesting.midY, control.bounds.midY, accuracy: 1)

        let menuView = FlowDropdownMenuView(
            options: options,
            selectedID: "option",
            controlIdentifier: "flowtab.test.dropdown",
            presentation: presentation
        )
        menuView.frame = NSRect(x: 0, y: 0, width: 180, height: 120)
        menuView.layoutSubtreeIfNeeded()

        let rows = menuView.rowsForTesting
        XCTAssertEqual(rows.map(\.titleForTesting), ["Option", "Control", "Command"])
        let selectedRow = try XCTUnwrap(rows.first)
        let normalRow = try XCTUnwrap(rows.dropFirst().first)
        let commandRow = try XCTUnwrap(rows.last)
        XCTAssertEqual(selectedRow.titleFrameForTesting.midY, selectedRow.bounds.midY, accuracy: 1)
        XCTAssertEqual(control.titleAlignmentForTesting, .center)
        XCTAssertEqual(
            control.titleFrameForTesting.maxX,
            control.chevronFrameForTesting.minX - 6,
            accuracy: 1
        )
        XCTAssertLessThan(control.titleFrameForTesting.midX, control.bounds.midX)
        XCTAssertEqual(selectedRow.titleAlignmentForTesting, .center)
        XCTAssertEqual(selectedRow.titleFrameForTesting.midX, selectedRow.bounds.midX, accuracy: 1)
        XCTAssertEqual(normalRow.titleFrameForTesting.midX, selectedRow.titleFrameForTesting.midX)
        XCTAssertEqual(commandRow.titleFrameForTesting.midX, selectedRow.titleFrameForTesting.midX)
        assertDropdownColor(try XCTUnwrap(normalRow.textColorForTesting), matches: presentation.menuStyle.textColor)
        XCTAssertNotNil(selectedRow.backgroundColorForTesting)
        XCTAssertNil(normalRow.backgroundColorForTesting)
        XCTAssertNil(commandRow.backgroundColorForTesting)
    }

    @MainActor
    func testFlowDropdownKeepsOnlyOneHoveredRowFilled() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let presentation = FlowDropdownPresentation.form(targetAppearance: appearance)
        let menuView = FlowDropdownMenuView(
            options: [
                FlowDropdownOption(id: "e", title: "E"),
                FlowDropdownOption(id: "f", title: "F"),
                FlowDropdownOption(id: "g", title: "G")
            ],
            selectedID: nil,
            controlIdentifier: "flowtab.test.dropdown",
            presentation: presentation
        )
        menuView.frame = NSRect(x: 0, y: 0, width: 180, height: 120)
        menuView.layoutSubtreeIfNeeded()

        let rows = menuView.rowsForTesting
        let firstRow = try XCTUnwrap(rows.first)
        let secondRow = try XCTUnwrap(rows.dropFirst().first)
        let event = try XCTUnwrap(dropdownMouseEvent())

        firstRow.mouseEntered(with: event)
        XCTAssertNotNil(firstRow.backgroundColorForTesting)
        XCTAssertNil(secondRow.backgroundColorForTesting)

        secondRow.mouseEntered(with: event)
        XCTAssertNil(firstRow.backgroundColorForTesting)
        XCTAssertNotNil(secondRow.backgroundColorForTesting)
    }

    @MainActor
    func testFlowDropdownUsesResolvedPresentationAndSelectionCallbackOnce() throws {
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let options = [
            FlowDropdownOption(id: "one", title: "One"),
            FlowDropdownOption(id: "two", title: "Two")
        ]
        let control = FlowDropdownControl(frame: NSRect(x: 0, y: 0, width: 180, height: 32))
        control.configure(
            options: options,
            selectedID: "one",
            presentation: .form(targetAppearance: lightAppearance)
        )
        control.layoutSubtreeIfNeeded()
        let lightColor = try XCTUnwrap(control.textColorForTesting)

        control.configure(
            options: options,
            selectedID: control.selectedIdentifierForTesting,
            presentation: .form(targetAppearance: darkAppearance)
        )
        control.layoutSubtreeIfNeeded()
        let darkColor = try XCTUnwrap(control.textColorForTesting)
        XCTAssertNotEqual(
            lightColor.usingColorSpace(.sRGB)?.brightnessComponent,
            darkColor.usingColorSpace(.sRGB)?.brightnessComponent
        )

        var selectedIDs: [String] = []
        control.onSelectionChanged = { selectedIDs.append($0) }
        control.selectOptionForTesting("two")
        control.selectOptionForTesting("two")

        XCTAssertEqual(control.selectedIdentifierForTesting, "two")
        XCTAssertEqual(selectedIDs, ["two"])

        control.isEnabled = false
        XCTAssertFalse(control.accessibilityPerformPress())
    }

    func testFlowDropdownSharedControlDoesNotReadPresentationOrLocalizationState() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcePaths = [
            "FlowTab/Features/SharedUI/FlowDropdownTypes.swift",
            "FlowTab/Features/SharedUI/FlowDropdownControl.swift",
            "FlowTab/Features/SharedUI/FlowDropdownMenuView.swift",
            "FlowTab/Features/SharedUI/FlowDropdownMenuWindowController.swift",
            "FlowTab/Features/SharedUI/FlowDropdownRepresentable.swift",
            "FlowTab/Features/SharedUI/FlowCompactActionButton.swift"
        ]
        let forbiddenSymbols = [
            "FlowPresentationState",
            "AppStrings",
            "UserDefaults",
            "AppPreferenceKeys"
        ]

        for sourcePath in sourcePaths {
            let source = try String(contentsOf: repoRoot.appendingPathComponent(sourcePath))
            for symbol in forbiddenSymbols {
                XCTAssertFalse(source.contains(symbol), "\(sourcePath) should not reference \(symbol)")
            }
        }
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
    func testCompactActionButtonUsesSingleMainLayerBorder() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let button = FlowCompactActionButtonControl()
        button.configure(
            title: AppStrings.text(.appVisibilityManage, language: .simplifiedChinese),
            accessibilityLabel: nil,
            presentation: .compact(targetAppearance: appearance)
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
    func testSettingsAppVisibilityManageUsesSharedCompactActionButton() throws {
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

        let manageButton: FlowCompactActionButtonControl = try XCTUnwrap(
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

            XCTAssertNil(
                descendant(in: selectControl, as: NSPopUpButton.self),
                "Settings selects should not expose system popup buttons",
                file: file,
                line: line
            )
            let dropdownControl: FlowDropdownControl = try XCTUnwrap(
                descendant(in: selectControl, as: FlowDropdownControl.self),
                file: file,
                line: line
            )
            assertColor(dropdownControl.textColorForTesting, resolvesTo: expectedInk, in: selectControl.effectiveAppearance)
            XCTAssertFalse(dropdownControl.selectedTitleForTesting.isEmpty, file: file, line: line)
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
            commandTabTakeoverRegistrationState: .inactive,
            accessibilityTrusted: false,
            screenCaptureTrusted: false,
            targetNSAppearanceName: ThemePreferencesStore.resolve(rawValue: themeModeRaw)
                .resolvedColorScheme(systemColorScheme: .light)
                .flowTabNSAppearanceName
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

    private func assertDropdownColor(
        _ color: NSColor,
        matches expectedColor: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard
            let actual = color.usingColorSpace(.sRGB),
            let expected = expectedColor.usingColorSpace(.sRGB)
        else {
            XCTFail("Expected comparable sRGB colors", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: 0.01, file: file, line: line)
    }

    private func dropdownMouseEvent() -> NSEvent? {
        NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )
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
