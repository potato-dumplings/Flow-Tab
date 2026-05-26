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
        let fixedControlWidthConstraints = requiredFixedSettingsControlWidthConstraints(in: view)
            .filter { constraint in
                constraint.firstItem is FlowSettingsSelectControl
                    || constraint.firstItem is FlowSettingsActionButton
            }
        XCTAssertTrue(
            fixedControlWidthConstraints.isEmpty,
            fixedControlWidthConstraints.map(\.description).joined(separator: "\n")
        )

        let languageSelect: FlowSettingsSelectControl = try XCTUnwrap(
            descendant(in: view, identifier: "flowtab.settings.appearance.app-language")
        )
        XCTAssertGreaterThanOrEqual(languageSelect.intrinsicContentSize.width, 140)

        let scopeSelect: FlowSettingsSelectControl = try XCTUnwrap(
            descendant(in: view, identifier: "flowtab.settings.search.default-scope")
        )
        XCTAssertGreaterThanOrEqual(scopeSelect.intrinsicContentSize.width, 84)

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
        try assertTextFieldIsVisiblyLaidOut("主修饰键", in: hotkeyCard)
        try assertControlIsVisiblyLaidOut(
            identifier: "flowtab.settings.hotkey.main-modifier",
            in: hotkeyCard
        )
        try assertControlIsVisiblyLaidOut(
            identifier: "flowtab.settings.hotkey.in-app-key",
            in: hotkeyCard
        )
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
    func testSettingsRootThemeSwitchMatchesColdDarkLayoutInSwiftUIHost() throws {
        let previousSelectedTab = HomeTabState.shared.selectedTab
        let previousLanguageRaw = UserDefaults.standard.string(forKey: AppPreferenceKeys.appLanguage)
        let previousThemeRaw = UserDefaults.standard.string(forKey: AppPreferenceKeys.themeMode)
        let previousPresentationContext = FlowPresentationState.shared.context
        HomeTabState.shared.selectedTab = .settings
        FlowPresentationState.shared.setAppLanguage(rawValue: AppLanguage.english.rawValue)
        FlowPresentationState.shared.setThemeMode(rawValue: ThemeMode.light.rawValue)
        defer {
            HomeTabState.shared.selectedTab = previousSelectedTab
            FlowPresentationState.shared.setAppLanguage(rawValue: previousPresentationContext.appLanguage.rawValue)
            FlowPresentationState.shared.setThemeMode(rawValue: previousPresentationContext.themeMode.rawValue)
            restoreStandardUserDefaultsValue(previousLanguageRaw, forKey: AppPreferenceKeys.appLanguage)
            restoreStandardUserDefaultsValue(previousThemeRaw, forKey: AppPreferenceKeys.themeMode)
        }

        let hostedView = NSHostingView(
            rootView: HomeRootView()
                .frame(width: 1_440, height: 900, alignment: .topLeading)
        )
        hostedView.frame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        hostedView.layoutSubtreeIfNeeded()

        let initialContainer: AppKitSettingsPageContainerView = try XCTUnwrap(
            descendantViews(in: hostedView).compactMap { $0 as? AppKitSettingsPageContainerView }.first
        )
        settleSettingsContainerLayout(initialContainer)

        FlowPresentationState.shared.setThemeMode(rawValue: ThemeMode.dark.rawValue)

        XCTAssertTrue(
            waitForRunLoopCondition(timeout: 1.0) {
                hostedView.layoutSubtreeIfNeeded()
                let containers = descendantViews(in: hostedView)
                    .compactMap { $0 as? AppKitSettingsPageContainerView }
                guard containers.count == 1, let container = containers.first else { return false }
                return container.appearance?.isFlowTabDarkInterface == true
                    && settingsCardBackgroundIsDark(in: container.pageView)
            },
            "Root theme changes should rebuild or refresh Settings with the target app appearance."
        )
        let switchedContainer: AppKitSettingsPageContainerView = try XCTUnwrap(
            descendantViews(in: hostedView).compactMap { $0 as? AppKitSettingsPageContainerView }.first
        )
        settleSettingsContainerLayout(switchedContainer)

        let switchedFrames = settingsCardFramesByTitle(in: switchedContainer.pageView, relativeTo: hostedView)

        let coldDarkHostedView = NSHostingView(
            rootView: HomeRootView()
                .frame(width: 1_440, height: 900, alignment: .topLeading)
        )
        coldDarkHostedView.frame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        coldDarkHostedView.layoutSubtreeIfNeeded()
        XCTAssertTrue(
            waitForRunLoopCondition(timeout: 1.0) {
                coldDarkHostedView.layoutSubtreeIfNeeded()
                let containers = descendantViews(in: coldDarkHostedView)
                    .compactMap { $0 as? AppKitSettingsPageContainerView }
                guard containers.count == 1, let container = containers.first else { return false }
                return container.appearance?.isFlowTabDarkInterface == true
                    && settingsCardBackgroundIsDark(in: container.pageView)
            },
            "Cold dark Settings should settle with the target app appearance."
        )
        let coldDarkContainer: AppKitSettingsPageContainerView = try XCTUnwrap(
            descendantViews(in: coldDarkHostedView).compactMap { $0 as? AppKitSettingsPageContainerView }.first
        )
        settleSettingsContainerLayout(coldDarkContainer)
        let coldDarkFrames = settingsCardFramesByTitle(in: coldDarkContainer.pageView, relativeTo: coldDarkHostedView)

        XCTAssertEqual(switchedFrames.keys.sorted(), coldDarkFrames.keys.sorted())
        for (title, switchedFrame) in switchedFrames {
            let coldFrame = try XCTUnwrap(coldDarkFrames[title], "Missing cold dark card frame for \(title)")
            assertFrameEqual(switchedFrame, coldFrame, accuracy: 1, message: "Hot theme switch differs from cold dark layout for \(title)")
        }
        try assertSettingsCardsStayNearHeader(in: switchedContainer.pageView)
    }

    @MainActor
    func testSettingsRootFollowSystemThemeChangeRebuildsSettingsBridgeLikeExplicitSwitch() throws {
        let systemAppearanceKey = "AppleInterfaceStyle"
        let previousSelectedTab = HomeTabState.shared.selectedTab
        let previousLanguageRaw = UserDefaults.standard.string(forKey: AppPreferenceKeys.appLanguage)
        let previousThemeRaw = UserDefaults.standard.string(forKey: AppPreferenceKeys.themeMode)
        let previousSystemAppearanceRaw = UserDefaults.standard.string(forKey: systemAppearanceKey)
        let previousPresentationContext = FlowPresentationState.shared.context
        HomeTabState.shared.selectedTab = .settings
        UserDefaults.standard.set("Light", forKey: systemAppearanceKey)
        postSystemAppearanceChangedNotification()
        FlowPresentationState.shared.setAppLanguage(rawValue: AppLanguage.english.rawValue)
        FlowPresentationState.shared.setThemeMode(rawValue: ThemeMode.followSystem.rawValue)
        XCTAssertTrue(
            waitForRunLoopCondition(timeout: 1.0) {
                FlowPresentationState.shared.context.resolvedColorScheme == .light
            },
            "Test setup should settle in follow-system light mode before switching the system appearance."
        )
        defer {
            HomeTabState.shared.selectedTab = previousSelectedTab
            restoreStandardUserDefaultsValue(previousSystemAppearanceRaw, forKey: systemAppearanceKey)
            postSystemAppearanceChangedNotification()
            FlowPresentationState.shared.setAppLanguage(rawValue: previousPresentationContext.appLanguage.rawValue)
            FlowPresentationState.shared.setThemeMode(rawValue: previousPresentationContext.themeMode.rawValue)
            restoreStandardUserDefaultsValue(previousLanguageRaw, forKey: AppPreferenceKeys.appLanguage)
            restoreStandardUserDefaultsValue(previousThemeRaw, forKey: AppPreferenceKeys.themeMode)
        }

        let hostedView = NSHostingView(
            rootView: HomeRootView()
                .frame(width: 1_440, height: 900, alignment: .topLeading)
        )
        hostedView.frame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        hostedView.layoutSubtreeIfNeeded()

        let initialContainer: AppKitSettingsPageContainerView = try XCTUnwrap(
            descendantViews(in: hostedView).compactMap { $0 as? AppKitSettingsPageContainerView }.first
        )
        settleSettingsContainerLayout(initialContainer)
        let initialContainerID = ObjectIdentifier(initialContainer)

        UserDefaults.standard.set("Dark", forKey: systemAppearanceKey)
        postSystemAppearanceChangedNotification()

        XCTAssertTrue(
            waitForRunLoopCondition(timeout: 1.0) {
                hostedView.layoutSubtreeIfNeeded()
                let containers = descendantViews(in: hostedView)
                    .compactMap { $0 as? AppKitSettingsPageContainerView }
                guard containers.count == 1, let container = containers.first else { return false }
                return FlowPresentationState.shared.context.themeMode == .followSystem
                    && FlowPresentationState.shared.context.resolvedColorScheme == .dark
                    && ObjectIdentifier(container) != initialContainerID
                    && container.appearance?.isFlowTabDarkInterface == true
                    && settingsCardBackgroundIsDark(in: container.pageView)
            },
            "Follow-system theme changes should rebuild Settings through the same bridge path as explicit theme switches."
        )
        let rebuiltContainer: AppKitSettingsPageContainerView = try XCTUnwrap(
            descendantViews(in: hostedView).compactMap { $0 as? AppKitSettingsPageContainerView }.first
        )
        settleSettingsContainerLayout(rebuiltContainer)
        try assertSettingsCardsStayNearHeader(in: rebuiltContainer.pageView)
        assertCardsDoNotOverlap(settingsCards(in: rebuiltContainer.pageView), in: rebuiltContainer.pageView)
        assertArrangedSubviewsDoNotOverlap(in: rebuiltContainer.pageView)
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
            showShortcutHint: true,
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
            hotkeyPrimaryModifierRaw: SwitcherPrimaryModifier.option.rawValue,
            hotkeyMainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            hotkeyQuitKeyRaw: SwitcherHotkeyKey.q.rawValue,
            inAppWindowHotkeyPrimaryModifierRaw: SwitcherPrimaryModifier.control.rawValue,
            inAppWindowHotkeyMainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            commandTabTakeoverActive: false,
            accessibilityTrusted: accessibilityTrusted,
            screenCaptureTrusted: screenCaptureTrusted,
            targetNSAppearanceName: themeMode == .dark ? .darkAqua : .aqua
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

    private func waitForRunLoopCondition(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    private func restoreStandardUserDefaultsValue(_ value: String?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func postSystemAppearanceChangedNotification() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func settingsCardBackgroundIsDark(in view: NSView) -> Bool {
        settingsCards(in: view).contains { card in
            guard let backgroundColor = card.layer?.backgroundColor else { return false }
            let color = NSColor(cgColor: backgroundColor)?.usingColorSpace(.sRGB)
            return (color?.brightnessComponent ?? 1) < 0.3
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
