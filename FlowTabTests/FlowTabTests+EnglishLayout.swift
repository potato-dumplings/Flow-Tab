import AppKit
import SwiftUI
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabTests {
    func testLocalizedCountTextUsesEnglishSingularAndPlural() {
        XCTAssertEqual(AppStrings.appCount(0, language: .english), "0 apps")
        XCTAssertEqual(AppStrings.appCount(1, language: .english), "1 app")
        XCTAssertEqual(AppStrings.appCount(2, language: .english), "2 apps")
        XCTAssertEqual(AppStrings.windowCount(1, language: .english), "1 window")
        XCTAssertEqual(AppStrings.windowCount(2, language: .english), "2 windows")
        XCTAssertEqual(AppStrings.hiddenAppCount(1, language: .english), "1 app hidden")
        XCTAssertEqual(AppStrings.hiddenAppCount(2, language: .english), "2 apps hidden")
        XCTAssertEqual(AppStrings.appCount(1, language: .simplifiedChinese), "1 个应用")
        XCTAssertEqual(AppStrings.windowCount(2, language: .simplifiedChinese), "2 个窗口")
    }

    @MainActor
    func testSettingsEnglishLayoutUsesContentSizedControlsAndPermissionButtons() throws {
        let view = AppKitSettingsPageView()
        view.frame = NSRect(x: 0, y: 0, width: 760, height: 760)
        view.update(with: makeEnglishSettingsPageState(hiddenAppCount: 1))
        view.prepareLayout(forWidth: 760)
        view.layout()
        view.layoutSubtreeIfNeeded()

        let localizedText = localizedTextValues(in: view)
        XCTAssertTrue(localizedText.contains("1 app hidden"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertFalse(localizedText.contains("1 apps hidden"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertTrue(localizedText.contains("System"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertFalse(localizedText.contains("Follow System"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertFalse(
            localizedText.contains("Allow Terminal content previews"),
            localizedText.sorted().joined(separator: "\n")
        )
        let fixedControlWidthConstraints = requiredFixedSettingsControlWidthConstraints(in: view)
            .filter { constraint in
                constraint.firstItem is FlowSettingsSelectControl
                    || constraint.firstItem is FlowSettingsActionButton
            }
        XCTAssertTrue(
            fixedControlWidthConstraints.isEmpty,
            fixedControlWidthConstraints.map(\.description).joined(separator: "\n")
        )
        let explicitSelectWidthConstraints = explicitSettingsSelectWidthConstraints(in: view)
        XCTAssertTrue(
            explicitSelectWidthConstraints.isEmpty,
            explicitSelectWidthConstraints.map(\.description).joined(separator: "\n")
        )

        let languageSelect: FlowSettingsSelectControl = try XCTUnwrap(
            descendant(in: view, identifier: "flowtab.settings.appearance.app-language")
        )
        XCTAssertGreaterThanOrEqual(languageSelect.intrinsicContentSize.width, 140)

        let scopeSelect: FlowSettingsSelectControl = try XCTUnwrap(
            descendant(in: view, identifier: "flowtab.settings.search.default-scope")
        )
        XCTAssertGreaterThanOrEqual(scopeSelect.intrinsicContentSize.width, FlowDropdownMetrics.defaultMinimumWidth)

        let themeModeControl: FlowSettingsSegmentedControl = try XCTUnwrap(
            descendant(in: view, identifier: "flowtab.settings.appearance.theme-mode")
        )
        XCTAssertLessThanOrEqual(themeModeControl.frame.width, themeModeControl.intrinsicContentSize.width + 1)
        XCTAssertLessThanOrEqual(themeModeControl.intrinsicContentSize.width, 260)

        let accessibilityButton: FlowSettingsActionButton = try XCTUnwrap(
            descendant(in: view, identifier: "flowtab.settings.permission.accessibility-action")
        )
        let screenCaptureButton: FlowSettingsActionButton = try XCTUnwrap(
            descendant(in: view, identifier: "flowtab.settings.permission.screen-capture-action")
        )
        let terminalContentPreviewsSwitch: NSSwitch? = descendant(
            in: view,
            identifier: "flowtab.settings.permission.terminal-content-previews"
        )
        XCTAssertEqual(accessibilityButton.title, "Request")
        XCTAssertEqual(screenCaptureButton.title, "Request")
        XCTAssertEqual(accessibilityButton.accessibilityLabel(), "Request Accessibility permission")
        XCTAssertEqual(screenCaptureButton.accessibilityLabel(), "Request Screen Recording permission")
        XCTAssertLessThanOrEqual(accessibilityButton.frame.height, 34)
        XCTAssertLessThanOrEqual(screenCaptureButton.frame.height, 34)
        XCTAssertLessThanOrEqual(accessibilityButton.frame.width, accessibilityButton.intrinsicContentSize.width + 1)
        XCTAssertLessThanOrEqual(screenCaptureButton.frame.width, screenCaptureButton.intrinsicContentSize.width + 1)
        XCTAssertFalse(accessibilityButton.attributedTitle.string.contains("\n"))
        XCTAssertFalse(screenCaptureButton.attributedTitle.string.contains("\n"))
        XCTAssertNil(terminalContentPreviewsSwitch)

        XCTAssertLessThanOrEqual(
            try sectionCard(in: view, containingText: "Appearance").frame.height,
            280
        )
        XCTAssertLessThanOrEqual(
            try sectionCard(in: view, containingText: "Window Behavior").frame.height,
            260
        )
        XCTAssertLessThanOrEqual(
            try sectionCard(in: view, containingText: "Permissions").frame.height,
            340
        )
    }

    @MainActor
    func testSettingsEnglishGrantedPermissionsUseManageActions() throws {
        let view = AppKitSettingsPageView()
        view.frame = NSRect(x: 0, y: 0, width: 760, height: 760)
        view.update(
            with: makeEnglishSettingsPageState(
                hiddenAppCount: 1,
                accessibilityTrusted: true,
                screenCaptureTrusted: true
            )
        )
        view.prepareLayout(forWidth: 760)
        view.layoutSubtreeIfNeeded()

        let localizedText = localizedTextValues(in: view)
        XCTAssertTrue(localizedText.contains("Accessibility: Granted"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertTrue(localizedText.contains("Screen Recording: Granted"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertTrue(localizedText.contains("Manage"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertFalse(localizedText.contains("Disable Accessibility permission"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertFalse(localizedText.contains("Disable Screen Recording permission"), localizedText.sorted().joined(separator: "\n"))

        let accessibilityButton: FlowSettingsActionButton = try XCTUnwrap(
            descendant(in: view, identifier: "flowtab.settings.permission.accessibility-action")
        )
        let screenCaptureButton: FlowSettingsActionButton = try XCTUnwrap(
            descendant(in: view, identifier: "flowtab.settings.permission.screen-capture-action")
        )
        XCTAssertEqual(accessibilityButton.title, "Manage")
        XCTAssertEqual(screenCaptureButton.title, "Manage")
        XCTAssertEqual(accessibilityButton.accessibilityLabel(), "Manage Accessibility permission")
        XCTAssertEqual(screenCaptureButton.accessibilityLabel(), "Manage Screen Recording permission")
        XCTAssertEqual(accessibilityButton.toolTip, "Manage Accessibility permission")
        XCTAssertEqual(screenCaptureButton.toolTip, "Manage Screen Recording permission")
        XCTAssertLessThanOrEqual(accessibilityButton.frame.width, accessibilityButton.intrinsicContentSize.width + 1)
        XCTAssertLessThanOrEqual(screenCaptureButton.frame.width, screenCaptureButton.intrinsicContentSize.width + 1)
        XCTAssertFalse(accessibilityButton.attributedTitle.string.contains("\n"))
        XCTAssertFalse(screenCaptureButton.attributedTitle.string.contains("\n"))
    }

    @MainActor
    func testSettingsSimplifiedChinesePermissionStatusesStayVisible() throws {
        let view = AppKitSettingsPageView()
        view.frame = NSRect(x: 0, y: 0, width: 760, height: 760)
        view.update(with: makeSettingsPageState(language: .simplifiedChinese, hiddenAppCount: 1))
        view.prepareLayout(forWidth: 760)
        view.layoutSubtreeIfNeeded()

        let permissionCard = try sectionCard(in: view, containingText: "权限")
        try assertTextFieldIsVisiblyLaidOut(
            "辅助功能权限：未授权",
            in: permissionCard
        )
        try assertTextFieldIsVisiblyLaidOut(
            "屏幕录制权限：未授权",
            in: permissionCard
        )
    }

    @MainActor
    func testSettingsLanguageSwitchRelayoutsChineseCardsWithoutOverlap() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_440, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        let container = AppKitSettingsPageContainerView()
        container.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        window.contentView = container

        container.update(
            with: makeSettingsPageState(language: .english, hiddenAppCount: 1),
            isActive: true
        )
        settleSettingsContainerLayout(container)
        container.update(
            with: makeSettingsPageState(language: .simplifiedChinese, hiddenAppCount: 1),
            isActive: true
        )
        settleSettingsContainerLayout(container)

        let cards = settingsCards(in: container.pageView)
        XCTAssertEqual(cards.count, 6)
        assertCardsDoNotOverlap(cards, in: container.pageView)
        assertArrangedSubviewsDoNotOverlap(in: container.pageView)
        try assertSettingsCardsStayNearHeader(in: container.pageView)

        let permissionCard = try sectionCard(in: container.pageView, containingText: "权限")
        try assertTextFieldIsVisiblyLaidOut("辅助功能权限：未授权", in: permissionCard)
        try assertTextFieldIsVisiblyLaidOut("屏幕录制权限：未授权", in: permissionCard)
        try assertControlIsVisiblyLaidOut(
            identifier: "flowtab.settings.permission.accessibility-action",
            in: permissionCard
        )
        try assertControlIsVisiblyLaidOut(
            identifier: "flowtab.settings.permission.screen-capture-action",
            in: permissionCard
        )

        let hotkeyCard = try sectionCard(in: container.pageView, containingText: "快捷键")
        for label in [
            "主修饰键",
            "反向修饰键",
            "主切换按键",
            "结束应用按键",
            "应用内保持按键",
            "应用内反向修饰键",
            "应用内切换按键"
        ] {
            try assertTextFieldIsVisiblyLaidOut(label, in: hotkeyCard)
        }
        for identifier in [
            "flowtab.settings.hotkey.main-modifiers",
            "flowtab.settings.hotkey.main-reverse-modifiers",
            "flowtab.settings.hotkey.main-key",
            "flowtab.settings.hotkey.quit-key",
            "flowtab.settings.hotkey.in-app-base-keys",
            "flowtab.settings.hotkey.in-app-reverse-modifiers",
            "flowtab.settings.hotkey.in-app-main-keys"
        ] {
            try assertControlIsVisiblyLaidOut(
                identifier: identifier,
                in: hotkeyCard
            )
        }
    }

    @MainActor
    func testSettingsThemeSwitchKeepsCardFramesStable() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_440, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        let container = AppKitSettingsPageContainerView()
        container.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        window.contentView = container

        container.update(
            with: makeSettingsPageState(
                themeMode: .light,
                language: .simplifiedChinese,
                hiddenAppCount: 1
            ),
            isActive: true
        )
        settleSettingsContainerLayout(container)
        let lightFrames = settingsCardFramesByTitle(in: container.pageView, relativeTo: container)

        container.update(
            with: makeSettingsPageState(
                themeMode: .dark,
                language: .simplifiedChinese,
                hiddenAppCount: 1
            ),
            isActive: true
        )
        settleSettingsContainerLayout(container)

        let darkFrames = settingsCardFramesByTitle(in: container.pageView, relativeTo: container)
        XCTAssertEqual(darkFrames.keys.sorted(), lightFrames.keys.sorted())
        XCTAssertEqual(darkFrames.count, 6)
        for (title, lightFrame) in lightFrames {
            let darkFrame = try XCTUnwrap(darkFrames[title], "Missing card frame for \(title)")
            assertFrameEqual(darkFrame, lightFrame, accuracy: 1, message: "Theme switch moved card \(title)")
        }
        assertCardsDoNotOverlap(settingsCards(in: container.pageView), in: container.pageView)
        assertArrangedSubviewsDoNotOverlap(in: container.pageView)
        try assertSettingsCardsStayNearHeader(in: container.pageView)
    }

    @MainActor
    func testSettingsCardsKeepPreferredHeightsInTwoColumnLayout() throws {
        let view = AppKitSettingsPageView()
        view.frame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        view.update(with: makeSettingsPageState(
            themeMode: .followSystem,
            language: .simplifiedChinese,
            hiddenAppCount: 1
        ))
        view.prepareLayout(forWidth: 1_240)
        view.layout()
        view.layoutSubtreeIfNeeded()

        let cards = settingsCards(in: view)
        XCTAssertEqual(cards.count, 6)
        for card in cards {
            XCTAssertLessThanOrEqual(
                card.frame.height,
                card.preferredLayoutHeight() + 1,
                "Settings card should not absorb extra column height: \(localizedTextValues(in: card).sorted())"
            )
            assertCardBottomContentInsetIsCompact(card)
        }
    }

    @MainActor
    func testSettingsContainerKeepsCardsAnchoredWithSingleLayoutPassAcrossThemeSwitch() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_440, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        let container = AppKitSettingsPageContainerView()
        container.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        window.contentView = container

        container.update(
            with: makeSettingsPageState(
                themeMode: .light,
                language: .simplifiedChinese,
                hiddenAppCount: 1
            ),
            isActive: true
        )
        container.layout()
        container.layoutSubtreeIfNeeded()

        let lightFrames = settingsCardFramesByTitle(in: container.pageView, relativeTo: container)
        try assertSettingsCardsStayNearHeader(in: container.pageView)

        container.update(
            with: makeSettingsPageState(
                themeMode: .dark,
                language: .simplifiedChinese,
                hiddenAppCount: 1
            ),
            isActive: true
        )
        container.layout()
        container.layoutSubtreeIfNeeded()

        let darkFrames = settingsCardFramesByTitle(in: container.pageView, relativeTo: container)
        try assertSettingsCardsStayNearHeader(in: container.pageView)
        XCTAssertEqual(darkFrames.keys.sorted(), lightFrames.keys.sorted())
        for (title, lightFrame) in lightFrames {
            let darkFrame = try XCTUnwrap(darkFrames[title], "Missing card frame for \(title)")
            assertFrameEqual(darkFrame, lightFrame, accuracy: 1, message: "Theme switch moved card \(title)")
        }
    }

    @MainActor
    func testSidebarPermissionStatusExpandsForEnglishAtSidebarWidth() {
        let hostedView = NSHostingView(
            rootView: HomePermissionStatusCard(
                accessibilityTrusted: false,
                screenCaptureTrusted: false,
                language: .english,
                colorScheme: .light
            )
            .frame(width: 180)
        )
        hostedView.frame = NSRect(x: 0, y: 0, width: 180, height: 120)
        hostedView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(hostedView.fittingSize.height, HomePageLayout.bottomStatusHeight)
        XCTAssertLessThanOrEqual(hostedView.fittingSize.height, 100)
    }

    @MainActor
    func testSidebarPermissionStatusUsesCompactTrailingInset() throws {
        XCTAssertEqual(HomePermissionStatusLayout.leadingInset, 14)
        XCTAssertEqual(HomePermissionStatusLayout.trailingInset, 8)
        XCTAssertEqual(HomePermissionStatusLayout.verticalInset, 12)
        XCTAssertLessThan(
            HomePermissionStatusLayout.trailingInset,
            HomePermissionStatusLayout.leadingInset
        )

        let hostedView = NSHostingView(
            rootView: HomePermissionStatusCard(
                accessibilityTrusted: true,
                screenCaptureTrusted: false,
                language: .simplifiedChinese,
                colorScheme: .dark
            )
            .frame(
                width: 180,
                height: HomePageLayout.bottomStatusHeight
            )
        )
        hostedView.frame = NSRect(
            x: 0,
            y: 0,
            width: 180,
            height: HomePageLayout.bottomStatusHeight
        )
        hostedView.layoutSubtreeIfNeeded()

        for identifier in [
            "flowtab.sidebar.permission.accessibility.status",
            "flowtab.sidebar.permission.screen-capture.status"
        ] {
            let statusLabel: NSTextField = try XCTUnwrap(
                descendant(in: hostedView, identifier: identifier)
            )
            let statusFrame = statusLabel.convert(
                statusLabel.bounds,
                to: hostedView
            )
            XCTAssertEqual(
                hostedView.bounds.maxX - statusFrame.maxX,
                HomePermissionStatusLayout.trailingInset,
                accuracy: 2
            )
            XCTAssertLessThanOrEqual(
                statusFrame.width,
                statusLabel.intrinsicContentSize.width + 4,
                "Status label contains trailing blank layout space: "
                    + "frame=\(statusFrame) intrinsic="
                    + "\(statusLabel.intrinsicContentSize)"
            )
        }
    }

    private func makeEnglishSettingsPageState(
        hiddenAppCount: Int,
        accessibilityTrusted: Bool = false,
        screenCaptureTrusted: Bool = false
    ) -> AppKitSettingsPageState {
        makeSettingsPageState(
            language: .english,
            hiddenAppCount: hiddenAppCount,
            accessibilityTrusted: accessibilityTrusted,
            screenCaptureTrusted: screenCaptureTrusted
        )
    }

    private func makeSettingsPageState(
        themeMode: ThemeMode = .followSystem,
        language: AppLanguage,
        hiddenAppCount: Int,
        accessibilityTrusted: Bool = false,
        screenCaptureTrusted: Bool = false
    ) -> AppKitSettingsPageState {
        AppKitSettingsPageState(
            showInCommandTab: true,
            themeModeRaw: themeMode.rawValue,
            appLanguageRaw: language.rawValue,
            windowLayerAutoEnterDelayText: "0.75",
            autoRestoreMinimizedWindowOnSwitch: false,
            hideMinimizedAppsFromAppLayer: false,
            showPermissionReminder: true,
            allowLaunchAtLogin: false,
            searchEnabled: true,
            searchDefaultScopeRaw: SwitcherSearchScope.window.rawValue,
            hiddenAppCount: hiddenAppCount,
            hotkeyPrimaryModifierRaw: SwitcherHotkeyKey.option.rawValue,
            hotkeyMainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            hotkeyQuitKeyRaw: SwitcherHotkeyKey.q.rawValue,
            inAppWindowHotkeyBaseKeysRaw: "control",
            inAppWindowHotkeyMainKeysRaw: "tab",
            commandTabTakeoverRegistrationState: .inactive,
            accessibilityTrusted: accessibilityTrusted,
            screenCaptureTrusted: screenCaptureTrusted,
            targetNSAppearanceName: themeMode
                .resolvedColorScheme(systemColorScheme: .light)
                .flowTabNSAppearanceName
        )
    }

    private func requiredFixedSettingsControlWidthConstraints(in view: NSView) -> [NSLayoutConstraint] {
        descendantViews(in: view)
            .flatMap(\.constraints)
            .filter { constraint in
                guard constraint.firstAttribute == .width,
                    constraint.relation == .equal,
                    constraint.secondItem == nil,
                    constraint.priority == .required,
                    !String(describing: type(of: constraint)).contains("NSContentSizeLayoutConstraint")
                else {
                    return false
                }

                return constraint.firstItem is FlowSettingsSegmentedControl
                    || constraint.firstItem is FlowSettingsSelectControl
                    || constraint.firstItem is FlowSettingsActionButton
            }
    }

    private func explicitSettingsSelectWidthConstraints(in view: NSView) -> [NSLayoutConstraint] {
        descendantViews(in: view)
            .flatMap(\.constraints)
            .filter { constraint in
                guard constraint.firstAttribute == .width,
                    constraint.secondItem == nil,
                    !String(describing: type(of: constraint)).contains("NSContentSizeLayoutConstraint")
                else {
                    return false
                }

                return constraint.firstItem is FlowSettingsSelectControl
            }
    }

    private func localizedTextValues(in view: NSView) -> Set<String> {
        Set(
            descendantViews(in: view).compactMap { view in
                if let textField = view as? NSTextField {
                    return textField.stringValue.isEmpty ? nil : textField.stringValue
                }
                if let button = view as? NSButton {
                    return button.title.isEmpty ? nil : button.title
                }
                return nil
            }
        )
    }

    private func sectionCard(in view: NSView, containingText text: String) throws -> FlowSettingsCardView {
        try XCTUnwrap(
            descendantViews(in: view).compactMap { card in
                guard let sectionCard = card as? FlowSettingsCardView,
                    localizedTextValues(in: sectionCard).contains(text)
                else {
                    return nil
                }
                return sectionCard
            }
            .first,
            "Missing Settings card containing text: \(text)"
        )
    }

    private func settingsCards(in view: NSView) -> [FlowSettingsCardView] {
        descendantViews(in: view).compactMap { $0 as? FlowSettingsCardView }
    }

    private func settleSettingsContainerLayout(_ container: AppKitSettingsPageContainerView) {
        for _ in 0..<4 {
            container.layout()
            container.layoutSubtreeIfNeeded()
        }
    }

    private func settingsCardFramesByTitle(in view: NSView, relativeTo ancestor: NSView) -> [String: NSRect] {
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
            guard let card = findSectionCard(in: view, containingText: title) else { continue }
            frames[title] = visualFrame(of: card, relativeTo: ancestor)
        }
        return frames
    }

    private func findSectionCard(in view: NSView, containingText text: String) -> FlowSettingsCardView? {
        descendantViews(in: view).compactMap { card in
            guard let sectionCard = card as? FlowSettingsCardView,
                localizedTextValues(in: sectionCard).contains(text)
            else {
                return nil
            }
            return sectionCard
        }
        .first
    }

    private func visualFrame(of view: NSView, relativeTo ancestor: NSView) -> NSRect {
        let rawFrame = view.convert(view.bounds, to: ancestor)
        return NSRect(
            x: rawFrame.minX,
            y: ancestor.bounds.height - rawFrame.maxY,
            width: rawFrame.width,
            height: rawFrame.height
        )
    }

    private func assertFrameEqual(
        _ actual: NSRect,
        _ expected: NSRect,
        accuracy: CGFloat,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: accuracy, "\(message) x", file: file, line: line)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: accuracy, "\(message) y", file: file, line: line)
        XCTAssertEqual(actual.size.width, expected.size.width, accuracy: accuracy, "\(message) width", file: file, line: line)
        XCTAssertEqual(actual.size.height, expected.size.height, accuracy: accuracy, "\(message) height", file: file, line: line)
    }

    private func assertSettingsCardsStayNearHeader(
        in view: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let subtitle: NSTextField = try XCTUnwrap(
            descendant(
                in: view,
                identifier: "flowtab.settings.page.subtitle"
            ),
            file: file,
            line: line
        )
        let subtitleFrame = visualFrame(of: subtitle, relativeTo: view)
        let cardFrames = settingsCards(in: view).map { visualFrame(of: $0, relativeTo: view) }
        let firstCardTop = cardFrames.map(\.minY).min() ?? .infinity
        let gapBelowSubtitle = firstCardTop - subtitleFrame.maxY
        XCTAssertGreaterThanOrEqual(
            gapBelowSubtitle,
            -1,
            "Settings cards moved above the page subtitle. subtitle=\(subtitleFrame) cards=\(cardFrames)",
            file: file,
            line: line
        )
        XCTAssertLessThan(
            gapBelowSubtitle,
            60,
            "Settings cards drifted away from the page header. subtitle=\(subtitleFrame) cards=\(cardFrames)",
            file: file,
            line: line
        )
    }

    private func assertCardsDoNotOverlap(
        _ cards: [FlowSettingsCardView],
        in ancestor: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frames = cards.map { card in
            card.convert(card.bounds, to: ancestor)
        }
        for index in frames.indices {
            for otherIndex in frames.indices where otherIndex > index {
                let intersection = frames[index].intersection(frames[otherIndex])
                XCTAssertTrue(
                    intersection.isNull || intersection.width <= 1 || intersection.height <= 1,
                    "Settings cards overlap: \(frames[index]) and \(frames[otherIndex])",
                    file: file,
                    line: line
                )
            }
        }
    }

    private func assertCardBottomContentInsetIsCompact(
        _ card: FlowSettingsCardView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let contentFrames = descendantViews(in: card)
            .filter { view in
                guard !view.isHidden, view.alphaValue > 0 else { return false }
                return view is NSTextField || view is NSControl || view is NSImageView
            }
            .map { view in
                view.convert(view.bounds, to: card)
            }
            .filter { !$0.isEmpty }
        guard let bottomContentY = contentFrames.map(\.minY).min() else { return }
        XCTAssertLessThanOrEqual(
            bottomContentY,
            24,
            "Settings card has excessive bottom content inset: \(localizedTextValues(in: card).sorted()) frames=\(contentFrames)",
            file: file,
            line: line
        )
    }

    private func assertArrangedSubviewsDoNotOverlap(
        in view: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for stackView in descendantViews(in: view).compactMap({ $0 as? NSStackView }) {
            let visibleSubviews = stackView.arrangedSubviews.filter { !$0.isHidden && !$0.frame.isEmpty }
            for index in visibleSubviews.indices {
                for otherIndex in visibleSubviews.indices where otherIndex > index {
                    let firstFrame = visibleSubviews[index].convert(visibleSubviews[index].bounds, to: stackView)
                    let secondFrame = visibleSubviews[otherIndex].convert(visibleSubviews[otherIndex].bounds, to: stackView)
                    let intersection = firstFrame.intersection(secondFrame)
                    XCTAssertTrue(
                        intersection.isNull || intersection.width <= 1 || intersection.height <= 1,
                        "Arranged subviews overlap in \(type(of: stackView)): \(firstFrame) and \(secondFrame)",
                        file: file,
                        line: line
                    )
                }
            }
        }
    }

    private func assertTextFieldIsVisiblyLaidOut(
        _ text: String,
        in ancestor: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let textField = try XCTUnwrap(
            descendantViews(in: ancestor)
                .compactMap { $0 as? NSTextField }
                .first { $0.stringValue == text },
            "Missing text field: \(text)",
            file: file,
            line: line
        )
        ancestor.layoutSubtreeIfNeeded()
        let visibleFrame = textField.convert(textField.bounds, to: ancestor)

        XCTAssertFalse(textField.isHidden, file: file, line: line)
        XCTAssertGreaterThan(textField.frame.height, 8, file: file, line: line)
        XCTAssertTrue(
            ancestor.bounds.insetBy(dx: -1, dy: -1).intersects(visibleFrame),
            "Text field is laid out outside the card: \(text)",
            file: file,
            line: line
        )
    }

    private func assertControlIsVisiblyLaidOut(
        identifier: String,
        in ancestor: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let control: NSView = try XCTUnwrap(
            descendant(in: ancestor, identifier: identifier),
            "Missing control: \(identifier)",
            file: file,
            line: line
        )
        ancestor.layoutSubtreeIfNeeded()
        let visibleFrame = control.convert(control.bounds, to: ancestor)

        XCTAssertFalse(control.isHidden, file: file, line: line)
        XCTAssertGreaterThan(control.frame.width, 20, file: file, line: line)
        XCTAssertGreaterThan(control.frame.height, 12, file: file, line: line)
        XCTAssertTrue(
            ancestor.bounds.insetBy(dx: -1, dy: -1).contains(visibleFrame),
            "Control is laid out outside the card: \(identifier) \(visibleFrame)",
            file: file,
            line: line
        )
    }

    private func restoreStandardUserDefaultsValue(_ value: String?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
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
}
