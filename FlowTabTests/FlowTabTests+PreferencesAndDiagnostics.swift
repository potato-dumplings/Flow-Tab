import AppKit
import SwiftUI
import XCTest
@testable import FlowTab
import FlowTabCore
import Carbon

extension FlowTabTests {
    func testAppLanguageResolveFallsBackToDefaultForUnknownRawValue() {
        XCTAssertEqual(AppLanguagePreferencesStore.resolve(rawValue: "invalid"), .simplifiedChinese)
        XCTAssertEqual(AppLanguagePreferencesStore.resolve(rawValue: AppLanguage.english.rawValue), .english)
    }

    func testAppLanguageLoadPersistsNormalizedValue() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        userDefaults.set("unsupported-language", forKey: AppPreferenceKeys.appLanguage)

        let resolved = AppLanguagePreferencesStore.load(userDefaults: userDefaults)

        XCTAssertEqual(resolved, .simplifiedChinese)
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.appLanguage),
            AppLanguagePreferencesStore.defaultLanguage.rawValue
        )
    }

    func testAppStringsReturnsLanguageSpecificTextAndAppliesReplacements() {
        XCTAssertEqual(
            AppStrings.text(
                .homeAppWindowsOf,
                replacements: ["app": "Terminal"],
                language: .english
            ),
            "Terminal windows"
        )
        XCTAssertEqual(
            AppStrings.text(
                .homeAppWindowsOf,
                replacements: ["app": "终端"],
                language: .simplifiedChinese
            ),
            "终端 的窗口"
        )
        XCTAssertEqual(AppStrings.text(.menuQuit, language: .simplifiedChinese), "退出")
        XCTAssertEqual(
            AppStrings.text(.appearanceShowAppWindow, language: .simplifiedChinese),
            "像普通应用一样显示"
        )
        XCTAssertEqual(
            AppStrings.text(.appearanceDescription, language: .simplifiedChinese),
            "关闭后，当前应用将仅作为菜单栏辅助应用运行。"
        )
        XCTAssertEqual(AppStrings.text(.tabSettings, language: .english), "Settings")
        XCTAssertEqual(
            AppStrings.text(.settingsPageSubtitle, language: .english),
            "Display, hotkeys, and permissions"
        )
        XCTAssertEqual(
            AppStrings.text(.settingsPageSubtitle, language: .simplifiedChinese),
            "基础显示设置、快捷键与权限"
        )
        XCTAssertEqual(AppStrings.text(.settingsCardAppearanceTitle, language: .english), "Appearance")
        XCTAssertEqual(AppStrings.text(.appearanceThemeMode, language: .english), "Theme mode")
        XCTAssertEqual(AppStrings.text(.themeFollowSystem, language: .english), "System")
        XCTAssertEqual(AppStrings.text(.permissionAccessibilityManage, language: .english), "Manage")
        XCTAssertEqual(
            AppStrings.text(.permissionAccessibilityRequest, language: .english),
            "Request"
        )
        XCTAssertEqual(
            AppStrings.text(.permissionAccessibilityManageActionLabel, language: .english),
            "Manage Accessibility permission"
        )
        XCTAssertEqual(
            AppStrings.text(.permissionAccessibilityManage, language: .simplifiedChinese),
            "管理辅助功能权限"
        )
        XCTAssertEqual(
            AppStrings.text(.permissionScreenManage, language: .simplifiedChinese),
            "管理屏幕录制权限"
        )
    }

    func testSettingsPageNarrowLayoutUsesSingleColumnAndFlexibleControlWidths() {
        XCTAssertTrue(AppKitSettingsPageView.usesSingleColumnLayout(forWidth: 320))
        XCTAssertFalse(AppKitSettingsPageView.usesSingleColumnLayout(forWidth: 760))

        let view = AppKitSettingsPageView()
        view.update(with: makeSettingsPageState())
        view.prepareLayout(forWidth: 320)

        XCTAssertNotNil(
            descendant(
                in: view,
                identifier: "flowtab.settings.appearance.theme-mode",
                as: FlowSettingsSegmentedControl.self
            )
        )
        XCTAssertTrue(
            requiredFixedSettingsControlWidthConstraints(in: view).isEmpty,
            requiredFixedSettingsControlWidthConstraints(in: view)
                .map { $0.description }
                .joined(separator: "\n")
        )
    }

    @MainActor
    func testSettingsAppKitPageRefreshesLocalizedTextWhenLanguageChanges() throws {
        let previousLanguageRaw = UserDefaults.standard.string(forKey: AppPreferenceKeys.appLanguage)
        UserDefaults.standard.set(AppLanguage.simplifiedChinese.rawValue, forKey: AppPreferenceKeys.appLanguage)
        defer {
            if let previousLanguageRaw {
                UserDefaults.standard.set(previousLanguageRaw, forKey: AppPreferenceKeys.appLanguage)
            } else {
                UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.appLanguage)
            }
        }

        let view = AppKitSettingsPageView()
        view.update(with: makeSettingsPageState(language: .simplifiedChinese))
        view.update(with: makeSettingsPageState(language: .english))
        view.frame = NSRect(x: 0, y: 0, width: 1_200, height: 760)
        view.prepareLayout(forWidth: 1_200)
        view.layout()
        view.layoutSubtreeIfNeeded()

        let localizedText = localizedTextValues(in: view)
        XCTAssertTrue(localizedText.contains("Display, hotkeys, and permissions"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertTrue(localizedText.contains("Appearance"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertTrue(localizedText.contains("Theme mode"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertTrue(localizedText.contains("System"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertTrue(localizedText.contains("Request"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertFalse(localizedText.contains("基础显示设置、快捷键与权限"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertFalse(localizedText.contains("外观"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertFalse(localizedText.contains("主题模式"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertFalse(localizedText.contains("Follow System"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertFalse(localizedText.contains("请求辅助功能权限"), localizedText.sorted().joined(separator: "\n"))

        let subtitle: NSTextField = try XCTUnwrap(
            descendant(
                in: view,
                identifier: "flowtab.settings.page.subtitle"
            )
        )
        XCTAssertFalse(subtitle.isHidden)
        XCTAssertEqual(subtitle.stringValue, "Display, hotkeys, and permissions")
        XCTAssertGreaterThan(subtitle.frame.width, 80)
        XCTAssertGreaterThan(subtitle.intrinsicContentSize.height, 8)
    }

    @MainActor
    func testSettingsPageContentExpandsToWideSwiftUIProposal() throws {
        let hostedView = NSHostingView(
            rootView: AppSettingsView(isActive: true)
                .frame(width: 1_200, height: 760, alignment: .topLeading)
        )
        hostedView.frame = NSRect(x: 0, y: 0, width: 1_200, height: 760)
        hostedView.layoutSubtreeIfNeeded()

        let container: AppKitSettingsPageContainerView? = descendant(
            in: hostedView,
            as: AppKitSettingsPageContainerView.self
        )
        let settingsContainer = try XCTUnwrap(container)
        settingsContainer.layout()
        settingsContainer.layoutSubtreeIfNeeded()

        XCTAssertEqual(settingsContainer.frame.width, 1_200, accuracy: 1)
        XCTAssertGreaterThan(settingsContainer.pageView.frame.width, 1_100)
    }

    @MainActor
    func testSettingsLanguageChangeRebuildsSettingsBridgeWithLocalizedText() throws {
        let previousLanguageRaw = UserDefaults.standard.string(forKey: AppPreferenceKeys.appLanguage)
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppPreferenceKeys.appLanguage)
        defer {
            if let previousLanguageRaw {
                UserDefaults.standard.set(previousLanguageRaw, forKey: AppPreferenceKeys.appLanguage)
            } else {
                UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.appLanguage)
            }
        }

        let hostedView = NSHostingView(
            rootView: AppSettingsView(isActive: true)
                .frame(width: 1_440, height: 900, alignment: .topLeading)
        )
        hostedView.frame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        hostedView.layoutSubtreeIfNeeded()

        _ = try XCTUnwrap(
            descendant(in: hostedView, as: AppKitSettingsPageContainerView.self)
        )

        UserDefaults.standard.set(
            AppLanguage.simplifiedChinese.rawValue,
            forKey: AppPreferenceKeys.appLanguage
        )

        XCTAssertTrue(
            waitForRunLoopCondition(timeout: 1.0) {
                hostedView.layoutSubtreeIfNeeded()
                let containers = descendantViews(in: hostedView)
                    .compactMap { $0 as? AppKitSettingsPageContainerView }
                guard containers.count == 1, let container = containers.first else { return false }
                return localizedTextValues(in: container.pageView).contains("基础显示设置、快捷键与权限")
            },
            "Language changes should rebuild or refresh Settings with localized text."
        )
    }

    @MainActor
    func testSettingsRootLanguageChangeRebuildsSettingsBridgeWithLocalizedText() throws {
        let previousSelectedTab = HomeTabState.shared.selectedTab
        let previousLanguageRaw = UserDefaults.standard.string(forKey: AppPreferenceKeys.appLanguage)
        let previousThemeRaw = UserDefaults.standard.string(forKey: AppPreferenceKeys.themeMode)
        HomeTabState.shared.selectedTab = .settings
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppPreferenceKeys.appLanguage)
        UserDefaults.standard.set(ThemeMode.light.rawValue, forKey: AppPreferenceKeys.themeMode)
        defer {
            HomeTabState.shared.selectedTab = previousSelectedTab
            restoreUserDefaultsValue(previousLanguageRaw, forKey: AppPreferenceKeys.appLanguage)
            restoreUserDefaultsValue(previousThemeRaw, forKey: AppPreferenceKeys.themeMode)
        }

        let hostedView = NSHostingView(
            rootView: HomeRootView()
                .frame(width: 1_440, height: 900, alignment: .topLeading)
        )
        hostedView.frame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        hostedView.layoutSubtreeIfNeeded()

        _ = try XCTUnwrap(
            descendant(in: hostedView, as: AppKitSettingsPageContainerView.self)
        )

        UserDefaults.standard.set(
            AppLanguage.simplifiedChinese.rawValue,
            forKey: AppPreferenceKeys.appLanguage
        )

        XCTAssertTrue(
            waitForRunLoopCondition(timeout: 1.0) {
                hostedView.layoutSubtreeIfNeeded()
                let containers = descendantViews(in: hostedView)
                    .compactMap { $0 as? AppKitSettingsPageContainerView }
                guard containers.count == 1, let container = containers.first else { return false }
                return localizedTextValues(in: container.pageView).contains("基础显示设置、快捷键与权限")
            },
            "Root language changes should rebuild or refresh Settings with localized text."
        )
    }

    @MainActor
    func testSettingsRootThemeChangeRebuildsSettingsBridgeWithTargetAppearance() throws {
        let previousSelectedTab = HomeTabState.shared.selectedTab
        let previousLanguageRaw = UserDefaults.standard.string(forKey: AppPreferenceKeys.appLanguage)
        let previousThemeRaw = UserDefaults.standard.string(forKey: AppPreferenceKeys.themeMode)
        let previousPresentationContext = FlowPresentationState.shared.context
        HomeTabState.shared.selectedTab = .settings
        FlowPresentationState.shared.setAppLanguage(rawValue: AppLanguage.simplifiedChinese.rawValue)
        FlowPresentationState.shared.setThemeMode(rawValue: ThemeMode.light.rawValue)
        defer {
            HomeTabState.shared.selectedTab = previousSelectedTab
            FlowPresentationState.shared.setAppLanguage(rawValue: previousPresentationContext.appLanguage.rawValue)
            FlowPresentationState.shared.setThemeMode(rawValue: previousPresentationContext.themeMode.rawValue)
            restoreUserDefaultsValue(previousLanguageRaw, forKey: AppPreferenceKeys.appLanguage)
            restoreUserDefaultsValue(previousThemeRaw, forKey: AppPreferenceKeys.themeMode)
        }

        let hostedView = NSHostingView(
            rootView: HomeRootView()
                .frame(width: 1_440, height: 900, alignment: .topLeading)
        )
        hostedView.frame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        hostedView.layoutSubtreeIfNeeded()

        _ = try XCTUnwrap(
            descendant(in: hostedView, as: AppKitSettingsPageContainerView.self)
        )

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
    }

    @MainActor
    func testHomePermissionStatusColorsFollowResolvedThemeAndSettingsStatusTone() throws {
        let lightLabel = try hostedHomePermissionStatusTitleLabel(colorScheme: .light)
        let darkLabel = try hostedHomePermissionStatusTitleLabel(colorScheme: .dark)

        assertColor(lightLabel.textColor, matches: NSColor.black.withAlphaComponent(0.86))
        assertColor(darkLabel.textColor, matches: NSColor.white.withAlphaComponent(0.86))
        assertColor(HomePermissionStatusColors.statusTextColor(isGranted: false), matches: .systemOrange)
    }

    func testPermissionSettingsCardStateUsesDeniedCopyWhenPermissionsMissing() {
        let state = PermissionSettingsCardState(
            showPermissionReminder: true,
            allowLaunchAtLogin: false,
            accessibilityTrusted: false,
            screenCaptureTrusted: false,
            appLanguageRaw: AppLanguage.simplifiedChinese.rawValue
        )

        XCTAssertEqual(
            state.accessibilityStatusText,
            AppStrings.text(.permissionAccessibilityDenied, language: .simplifiedChinese)
        )
        XCTAssertEqual(
            state.accessibilityButtonTitle,
            AppStrings.text(.permissionAccessibilityRequest, language: .simplifiedChinese)
        )
        XCTAssertEqual(
            state.screenCaptureStatusText,
            AppStrings.text(.permissionScreenDenied, language: .simplifiedChinese)
        )
        XCTAssertEqual(
            state.screenCaptureButtonTitle,
            AppStrings.text(.permissionScreenRequest, language: .simplifiedChinese)
        )
    }

    func testPermissionSettingsCardStateUsesGrantedCopyWhenPermissionsPresent() {
        let state = PermissionSettingsCardState(
            showPermissionReminder: false,
            allowLaunchAtLogin: true,
            accessibilityTrusted: true,
            screenCaptureTrusted: true,
            appLanguageRaw: AppLanguage.simplifiedChinese.rawValue
        )

        XCTAssertEqual(
            state.accessibilityStatusText,
            AppStrings.text(.permissionAccessibilityGranted, language: .simplifiedChinese)
        )
        XCTAssertEqual(
            state.accessibilityButtonTitle,
            AppStrings.text(.permissionAccessibilityManage, language: .simplifiedChinese)
        )
        XCTAssertEqual(
            state.accessibilityPermissionActionLabel,
            AppStrings.text(.permissionAccessibilityManageActionLabel, language: .simplifiedChinese)
        )
        XCTAssertEqual(
            state.screenCaptureStatusText,
            AppStrings.text(.permissionScreenGranted, language: .simplifiedChinese)
        )
        XCTAssertEqual(
            state.screenCaptureButtonTitle,
            AppStrings.text(.permissionScreenManage, language: .simplifiedChinese)
        )
        XCTAssertEqual(
            state.screenCapturePermissionActionLabel,
            AppStrings.text(.permissionScreenManageActionLabel, language: .simplifiedChinese)
        )
    }

    @MainActor
    func testPermissionSettingsRowsStayCompactWhenVerticalStackGetsExtraHeight() throws {
        let accessibilityRow = PermissionStatusControlRowView(
            control: FlowSettingsActionButton(),
            controlWidth: 96
        )
        let screenCaptureRow = PermissionStatusControlRowView(
            control: FlowSettingsActionButton(),
            controlWidth: 96
        )
        accessibilityRow.update(
            text: AppStrings.text(.permissionAccessibilityDenied),
            detail: AppStrings.text(.permissionAccessibilityDetail),
            statusColor: .systemOrange
        )
        screenCaptureRow.update(
            text: AppStrings.text(.permissionScreenDenied),
            detail: AppStrings.text(.permissionScreenDetail),
            statusColor: .systemOrange
        )

        let stackView = NSStackView(views: [accessibilityRow, screenCaptureRow])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.frame = NSRect(x: 0, y: 0, width: 620, height: 260)
        stackView.layoutSubtreeIfNeeded()

        XCTAssertLessThanOrEqual(accessibilityRow.frame.height, accessibilityRow.intrinsicContentSize.height + 1)
        XCTAssertLessThanOrEqual(screenCaptureRow.frame.height, screenCaptureRow.intrinsicContentSize.height + 1)
    }

    @MainActor
    func testPermissionSettingsScreenCaptureDetailUsesPostLayoutTextWidth() throws {
        let button = FlowSettingsActionButton()
        button.update(
            title: AppStrings.text(.permissionScreenRequest, language: .simplifiedChinese),
            accessibilityLabel: nil,
            style: .preset(.secondaryAction)
        )
        let row = PermissionStatusControlRowView(control: button, controlWidth: 96)
        row.update(
            text: AppStrings.text(.permissionScreenDenied, language: .simplifiedChinese),
            detail: AppStrings.text(.permissionScreenDetail, language: .simplifiedChinese),
            statusColor: .systemOrange
        )
        row.frame = NSRect(x: 0, y: 0, width: 632, height: 80)
        row.layoutSubtreeIfNeeded()

        let detailLabel = try XCTUnwrap(
            descendantViews(in: row).compactMap { $0 as? NSTextField }
                .first { $0.stringValue == AppStrings.text(.permissionScreenDetail, language: .simplifiedChinese) }
        )
        let controlWidth = max(button.fittingSize.width, button.intrinsicContentSize.width)
        let expectedTextWidth = floor(row.bounds.width - controlWidth - 10)

        XCTAssertGreaterThan(expectedTextWidth, 0)
        XCTAssertEqual(detailLabel.preferredMaxLayoutWidth, expectedTextWidth, accuracy: 2.5)
    }

    @MainActor
    func testSettingsPermissionRequestAppliesIndependentPostRequestReadback() throws {
        let previousAXTrusted =
            AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest =
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let previousScreenTrusted =
            ScreenCapturePermissionChecker.hasPermissionOverrideForTesting
        let previousLanguageRaw = UserDefaults.standard.string(
            forKey: AppPreferenceKeys.appLanguage
        )
        defer {
            AccessibilityPermissionChecker.isTrustedOverrideForTesting =
                previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting =
                previousAXRequest
            ScreenCapturePermissionChecker.hasPermissionOverrideForTesting =
                previousScreenTrusted
            restoreUserDefaultsValue(
                previousLanguageRaw,
                forKey: AppPreferenceKeys.appLanguage
            )
        }

        var isGranted = false
        var requestCount = 0
        AccessibilityPermissionChecker.isTrustedOverrideForTesting = {
            isGranted
        }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = {
            requestCount += 1
            isGranted = true
            return false
        }
        ScreenCapturePermissionChecker.hasPermissionOverrideForTesting = {
            true
        }
        UserDefaults.standard.set(
            AppLanguage.simplifiedChinese.rawValue,
            forKey: AppPreferenceKeys.appLanguage
        )

        let hostedView = NSHostingView(
            rootView: AppSettingsView(isActive: true)
                .frame(width: 1_200, height: 760)
        )
        hostedView.frame = NSRect(x: 0, y: 0, width: 1_200, height: 760)
        hostedView.layoutSubtreeIfNeeded()
        let actionButton: NSButton = try XCTUnwrap(
            descendant(
                in: hostedView,
                identifier: "flowtab.settings.permission.accessibility-action"
            )
        )

        actionButton.performClick(nil)

        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(
            waitForRunLoopCondition(timeout: 1) {
                hostedView.layoutSubtreeIfNeeded()
                return actionButton.title == AppStrings.text(
                    .permissionAccessibilityManage,
                    language: .simplifiedChinese
                )
            }
        )
    }

    @MainActor
    func testHotkeyTakeoverInactiveStatusUsesRegistrationEvidence() {
        let view = HotkeySettingsCardAppKitView()
        let statusLabel: NSTextField? = descendant(
            in: view,
            identifier: "flowtab.settings.hotkey.main-takeover-status"
        )

        view.update(
            with: makeHotkeySettingsState(
                commandTabTakeoverRegistrationState: .inactive
            )
        )

        XCTAssertFalse(statusLabel?.isHidden ?? true)
        XCTAssertEqual(statusLabel?.stringValue, AppStrings.text(.hotkeyCommandTabTakeoverInactive))
    }

    @MainActor
    func testHotkeyTakeoverPendingStateHidesUntilRegistrationEvidenceArrives() {
        let view = HotkeySettingsCardAppKitView()
        let statusLabel: NSTextField? = descendant(
            in: view,
            identifier: "flowtab.settings.hotkey.main-takeover-status"
        )

        view.update(
            with: makeHotkeySettingsState(
                commandTabTakeoverRegistrationState: .pending
            )
        )
        XCTAssertTrue(statusLabel?.isHidden ?? false)

        view.update(
            with: makeHotkeySettingsState(
                commandTabTakeoverRegistrationState: .active
            )
        )

        XCTAssertEqual(statusLabel?.stringValue, AppStrings.text(.hotkeyCommandTabTakeoverActive))
        XCTAssertFalse(statusLabel?.isHidden ?? true)
    }

    func testRuntimeLogLevelOrderingUsesPriority() {
        XCTAssertLessThan(RuntimeLogLevel.debug, .info)
        XCTAssertLessThan(RuntimeLogLevel.info, .warning)
        XCTAssertLessThan(RuntimeLogLevel.warning, .error)
    }

    func testDiagnosticsRefreshPolicyOwnsRuntimeLogsLineLimit() {
        let policy = DiagnosticsRefreshPolicy.runtimeLogs

        XCTAssertEqual(policy.lineLimit, 300)
    }

    func testRuntimeLogPreferencesLoadPersistsDefaultForInvalidValue() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        userDefaults.set("NOT_A_LEVEL", forKey: AppPreferenceKeys.runtimeLogLevel)

        let level = RuntimeLogPreferencesStore.loadMinimumLevel(userDefaults: userDefaults)

        XCTAssertEqual(level, .error)
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.runtimeLogLevel),
            RuntimeLogPreferencesStore.defaultLevel.rawValue
        )
    }

    func testThemePreferencesResolveFallsBackToFollowSystem() {
        XCTAssertEqual(ThemePreferencesStore.resolve(rawValue: ThemeMode.light.rawValue), .light)
        XCTAssertEqual(ThemePreferencesStore.resolve(rawValue: "invalid"), .followSystem)
    }

    func testFlowPresentationResolverNormalizesRawValuesAndResolvesAppearance() {
        let invalidResolution = FlowPresentationResolver.resolve(
            themeRaw: "unknown-theme",
            languageRaw: "unknown-language",
            systemColorScheme: .dark
        )
        XCTAssertEqual(invalidResolution.context.themeMode, .followSystem)
        XCTAssertEqual(invalidResolution.context.appLanguage, .simplifiedChinese)
        XCTAssertEqual(invalidResolution.context.resolvedColorScheme, .dark)
        XCTAssertEqual(invalidResolution.context.targetNSAppearanceName, .darkAqua)
        XCTAssertEqual(invalidResolution.normalizedThemeRaw, ThemeMode.followSystem.rawValue)
        XCTAssertEqual(invalidResolution.normalizedLanguageRaw, AppLanguage.simplifiedChinese.rawValue)

        let followSystemLight = FlowPresentationResolver.resolve(
            themeRaw: ThemeMode.followSystem.rawValue,
            languageRaw: AppLanguage.english.rawValue,
            systemColorScheme: .light
        )
        XCTAssertEqual(followSystemLight.context.resolvedColorScheme, .light)
        XCTAssertEqual(followSystemLight.context.targetNSAppearanceName, .aqua)

        let explicitLight = FlowPresentationResolver.resolve(
            themeRaw: ThemeMode.light.rawValue,
            languageRaw: AppLanguage.english.rawValue,
            systemColorScheme: .dark
        )
        XCTAssertEqual(explicitLight.context.resolvedColorScheme, .light)
        XCTAssertEqual(explicitLight.context.targetNSAppearanceName, .aqua)

        let explicitDark = FlowPresentationResolver.resolve(
            themeRaw: ThemeMode.dark.rawValue,
            languageRaw: AppLanguage.english.rawValue,
            systemColorScheme: .light
        )
        XCTAssertEqual(explicitDark.context.resolvedColorScheme, .dark)
        XCTAssertEqual(explicitDark.context.targetNSAppearanceName, .darkAqua)
    }

    @MainActor
    func testSystemThemeStateMatchesCurrentSystemAppearanceWhenAppDefaultsContainAppleInterfaceStyle() {
        let systemAppearanceKey = "AppleInterfaceStyle"
        let previousAppearance = NSApp.appearance
        let previousAppAppearanceRaw = currentAppScopedDefaultString(forKey: systemAppearanceKey)
        NSApp.appearance = nil
        SystemThemeState.shared.refreshColorScheme()
        let expectedSystemColorScheme = SystemThemeState.colorScheme(for: NSApp.effectiveAppearance)
        let appScopedContamination = expectedSystemColorScheme == .dark ? "Light" : "Dark"
        UserDefaults.standard.set(appScopedContamination, forKey: systemAppearanceKey)
        postSystemAppearanceChangedNotification()
        defer {
            NSApp.appearance = previousAppearance
            restoreUserDefaultsValue(previousAppAppearanceRaw, forKey: systemAppearanceKey)
            postSystemAppearanceChangedNotification()
        }

        let state = SystemThemeState.shared

        XCTAssertTrue(
            waitForRunLoopCondition(timeout: 1.0) {
                state.colorScheme == expectedSystemColorScheme
                    && SystemThemeState.colorScheme(for: NSApp.effectiveAppearance) == expectedSystemColorScheme
            },
            "Follow-system theme should match the current system appearance, not app-scoped AppleInterfaceStyle defaults."
        )
    }

    @MainActor
    func testFlowPresentationStateInitializesWithNormalizedWritebackWithoutLanguageNotification() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }
        userDefaults.set("unknown-theme", forKey: AppPreferenceKeys.themeMode)
        userDefaults.set("unknown-language", forKey: AppPreferenceKeys.appLanguage)
        let notificationCenter = NotificationCenter()
        let systemThemeProvider = FakeFlowPresentationSystemThemeProvider(colorScheme: .dark)
        var languageNotificationCount = 0
        let observer = notificationCenter.addObserver(
            forName: .flowTabLanguagePreferenceChanged,
            object: nil,
            queue: nil
        ) { _ in
            languageNotificationCount += 1
        }
        defer { notificationCenter.removeObserver(observer) }

        let state = FlowPresentationState(
            userDefaults: userDefaults,
            notificationCenter: notificationCenter,
            systemThemeProvider: systemThemeProvider
        )

        XCTAssertEqual(state.context.themeMode, .followSystem)
        XCTAssertEqual(state.context.appLanguage, .simplifiedChinese)
        XCTAssertEqual(state.context.resolvedColorScheme, .dark)
        XCTAssertEqual(userDefaults.string(forKey: AppPreferenceKeys.themeMode), ThemeMode.followSystem.rawValue)
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.appLanguage),
            AppLanguage.simplifiedChinese.rawValue
        )
        XCTAssertEqual(languageNotificationCount, 0)
    }

    @MainActor
    func testFlowPresentationStateKeepsInjectedStoresAndCentersIsolated() {
        guard let firstDefaults = makeIsolatedUserDefaults(),
              let secondDefaults = makeIsolatedUserDefaults()
        else { return }
        defer {
            clearIsolatedUserDefaults(firstDefaults)
            clearIsolatedUserDefaults(secondDefaults)
        }
        firstDefaults.set(ThemeMode.dark.rawValue, forKey: AppPreferenceKeys.themeMode)
        firstDefaults.set(AppLanguage.english.rawValue, forKey: AppPreferenceKeys.appLanguage)
        secondDefaults.set(ThemeMode.light.rawValue, forKey: AppPreferenceKeys.themeMode)
        secondDefaults.set(AppLanguage.simplifiedChinese.rawValue, forKey: AppPreferenceKeys.appLanguage)
        let firstCenter = NotificationCenter()
        let secondCenter = NotificationCenter()
        let firstProvider = FakeFlowPresentationSystemThemeProvider(colorScheme: .light)
        let secondProvider = FakeFlowPresentationSystemThemeProvider(colorScheme: .dark)
        var firstNotifications = 0
        var secondNotifications = 0
        let firstObserver = firstCenter.addObserver(
            forName: .flowTabLanguagePreferenceChanged,
            object: nil,
            queue: nil
        ) { _ in
            firstNotifications += 1
        }
        let secondObserver = secondCenter.addObserver(
            forName: .flowTabLanguagePreferenceChanged,
            object: nil,
            queue: nil
        ) { _ in
            secondNotifications += 1
        }
        defer {
            firstCenter.removeObserver(firstObserver)
            secondCenter.removeObserver(secondObserver)
        }
        let firstState = FlowPresentationState(
            userDefaults: firstDefaults,
            notificationCenter: firstCenter,
            systemThemeProvider: firstProvider
        )
        let secondState = FlowPresentationState(
            userDefaults: secondDefaults,
            notificationCenter: secondCenter,
            systemThemeProvider: secondProvider
        )

        firstState.setAppLanguage(rawValue: AppLanguage.simplifiedChinese.rawValue)

        XCTAssertEqual(firstState.context.appLanguage, .simplifiedChinese)
        XCTAssertEqual(secondState.context.appLanguage, .simplifiedChinese)
        XCTAssertEqual(firstNotifications, 1)
        XCTAssertEqual(secondNotifications, 0)
        XCTAssertEqual(firstDefaults.string(forKey: AppPreferenceKeys.appLanguage), AppLanguage.simplifiedChinese.rawValue)
        XCTAssertEqual(secondDefaults.string(forKey: AppPreferenceKeys.appLanguage), AppLanguage.simplifiedChinese.rawValue)
    }

    @MainActor
    func testFlowPresentationStateFollowSystemRespondsToSystemThemeWithoutWritingRawThemeOrLanguageNotification() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }
        userDefaults.set(ThemeMode.followSystem.rawValue, forKey: AppPreferenceKeys.themeMode)
        userDefaults.set(AppLanguage.simplifiedChinese.rawValue, forKey: AppPreferenceKeys.appLanguage)
        let notificationCenter = NotificationCenter()
        let systemThemeProvider = FakeFlowPresentationSystemThemeProvider(colorScheme: .light)
        var languageNotificationCount = 0
        let observer = notificationCenter.addObserver(
            forName: .flowTabLanguagePreferenceChanged,
            object: nil,
            queue: nil
        ) { _ in
            languageNotificationCount += 1
        }
        defer { notificationCenter.removeObserver(observer) }
        let state = FlowPresentationState(
            userDefaults: userDefaults,
            notificationCenter: notificationCenter,
            systemThemeProvider: systemThemeProvider
        )

        systemThemeProvider.pushColorScheme(.dark)

        XCTAssertEqual(state.context.systemColorScheme, .dark)
        XCTAssertEqual(state.context.resolvedColorScheme, .dark)
        XCTAssertEqual(state.context.targetNSAppearanceName, .darkAqua)
        XCTAssertEqual(userDefaults.string(forKey: AppPreferenceKeys.themeMode), ThemeMode.followSystem.rawValue)
        XCTAssertEqual(languageNotificationCount, 0)
    }

    @MainActor
    func testFlowPresentationThemeObservationCancelIsIdempotent() async {
        let systemThemeProvider = FakeFlowPresentationSystemThemeProvider(colorScheme: .light)
        var colorSchemeChanges: [ColorScheme] = []
        let observation = systemThemeProvider.observeColorSchemeChanges { colorScheme in
            colorSchemeChanges.append(colorScheme)
        }

        systemThemeProvider.pushColorScheme(.dark)
        observation.cancel()
        observation.cancel()
        await Task.yield()
        systemThemeProvider.pushColorScheme(.light)

        XCTAssertEqual(colorSchemeChanges, [.dark])
        XCTAssertEqual(systemThemeProvider.observerCount, 0)
    }

    @MainActor
    func testFlowPresentationStateSetAppLanguagePostsOnlyForEffectiveLanguageChanges() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }
        userDefaults.set(ThemeMode.followSystem.rawValue, forKey: AppPreferenceKeys.themeMode)
        userDefaults.set(AppLanguage.simplifiedChinese.rawValue, forKey: AppPreferenceKeys.appLanguage)
        let notificationCenter = NotificationCenter()
        let systemThemeProvider = FakeFlowPresentationSystemThemeProvider(colorScheme: .light)
        var languageNotificationCount = 0
        let observer = notificationCenter.addObserver(
            forName: .flowTabLanguagePreferenceChanged,
            object: nil,
            queue: nil
        ) { _ in
            languageNotificationCount += 1
        }
        defer { notificationCenter.removeObserver(observer) }
        let state = FlowPresentationState(
            userDefaults: userDefaults,
            notificationCenter: notificationCenter,
            systemThemeProvider: systemThemeProvider
        )

        state.setAppLanguage(rawValue: "unknown-language")
        state.setAppLanguage(rawValue: AppLanguage.english.rawValue)
        state.setAppLanguage(rawValue: AppLanguage.english.rawValue)

        XCTAssertEqual(state.context.appLanguage, .english)
        XCTAssertEqual(languageNotificationCount, 1)
        XCTAssertEqual(userDefaults.string(forKey: AppPreferenceKeys.appLanguage), AppLanguage.english.rawValue)
    }

    @MainActor
    func testUITestBootstrapResetRefreshesSharedPresentationState() {
        let previousContext = FlowPresentationState.shared.context
        let standardDefaults = UserDefaults.standard
        let previousValues = AppPreferenceKeys.allKeys.reduce(into: [String: Any]()) { values, key in
            values[key] = standardDefaults.object(forKey: key)
        }
        let takeoverMarkerValue = standardDefaults.object(
            forKey: CommandTabTakeoverController.takeoverMarkerKey
        )
        defer {
            for key in AppPreferenceKeys.allKeys {
                if let value = previousValues[key] {
                    standardDefaults.set(value, forKey: key)
                } else {
                    standardDefaults.removeObject(forKey: key)
                }
            }
            restoreUserDefaultsValue(
                takeoverMarkerValue,
                forKey: CommandTabTakeoverController.takeoverMarkerKey,
                userDefaults: standardDefaults
            )
            FlowPresentationState.shared.setThemeMode(rawValue: previousContext.themeMode.rawValue)
            FlowPresentationState.shared.setAppLanguage(rawValue: previousContext.appLanguage.rawValue)
        }

        standardDefaults.set(ThemeMode.dark.rawValue, forKey: AppPreferenceKeys.themeMode)
        standardDefaults.set(AppLanguage.english.rawValue, forKey: AppPreferenceKeys.appLanguage)
        FlowPresentationState.shared.refreshFromStoredPreferences()
        XCTAssertEqual(FlowPresentationState.shared.context.themeMode, .dark)
        XCTAssertEqual(FlowPresentationState.shared.context.appLanguage, .english)

        withLaunchArgumentsForTesting(["--flowtab-ui-reset-defaults"]) {
            FlowTabUITestBootstrapper.prepareIfNeeded(userDefaults: standardDefaults)
        }

        XCTAssertEqual(FlowPresentationState.shared.context.themeMode, .followSystem)
        XCTAssertEqual(FlowPresentationState.shared.context.appLanguage, .simplifiedChinese)
        XCTAssertEqual(
            standardDefaults.string(forKey: AppPreferenceKeys.themeMode),
            ThemeMode.followSystem.rawValue
        )
        XCTAssertEqual(
            standardDefaults.string(forKey: AppPreferenceKeys.appLanguage),
            AppLanguage.simplifiedChinese.rawValue
        )
    }

    func testFlowPresentationContextEqualityIgnoresNSAppearanceIdentity() {
        let firstContext = FlowPresentationContext(
            themeMode: .dark,
            appLanguage: .english,
            systemColorScheme: .light,
            resolvedColorScheme: .dark,
            targetNSAppearanceName: .darkAqua
        )
        let secondContext = FlowPresentationContext(
            themeMode: .dark,
            appLanguage: .english,
            systemColorScheme: .light,
            resolvedColorScheme: .dark,
            targetNSAppearanceName: .darkAqua
        )

        XCTAssertEqual(firstContext, secondContext)
        XCTAssertEqual(firstContext.targetNSAppearance.name, .darkAqua)
        XCTAssertEqual(secondContext.targetNSAppearance.name, .darkAqua)
    }

    func testWindowLayerNormalizedAutoEnterDelayClampsAndRounds() {
        XCTAssertEqual(WindowLayerPreferencesStore.normalizedAutoEnterDelay(-3.2), 0.0)
        XCTAssertEqual(WindowLayerPreferencesStore.normalizedAutoEnterDelay(0.345), 0.35)
        XCTAssertEqual(WindowLayerPreferencesStore.normalizedAutoEnterDelay(1000.0), 999.99)
        XCTAssertEqual(
            WindowLayerPreferencesStore.normalizedAutoEnterDelay(Double.infinity),
            WindowLayerPreferencesStore.defaultAutoEnterDelay
        )
    }

    func testWindowLayerSanitizeAutoEnterDelayTextNormalizesInputShape() {
        XCTAssertEqual(
            WindowLayerPreferencesStore.sanitizeAutoEnterDelayText(".1299"),
            "0.12"
        )
        XCTAssertEqual(
            WindowLayerPreferencesStore.sanitizeAutoEnterDelayText("ab12.3.4cd"),
            "12.34"
        )
    }

    func testWindowLayerSanitizeAutoEnterDelayTextClampsToMax() {
        XCTAssertEqual(
            WindowLayerPreferencesStore.sanitizeAutoEnterDelayText("1000.999"),
            "999.99"
        )
    }

    func testSearchInteractionDefaultsAndScopeNormalization() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        XCTAssertTrue(SearchInteractionPreferencesStore.loadIsEnabled(userDefaults: userDefaults))

        userDefaults.set(false, forKey: AppPreferenceKeys.searchEnabled)
        XCTAssertFalse(SearchInteractionPreferencesStore.loadIsEnabled(userDefaults: userDefaults))

        userDefaults.set("invalid", forKey: AppPreferenceKeys.searchDefaultScope)
        let resolvedScope = SearchInteractionPreferencesStore.loadDefaultScope(userDefaults: userDefaults)
        XCTAssertEqual(resolvedScope, .app)
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.searchDefaultScope),
            SearchInteractionPreferencesStore.defaultScope.rawValue
        )
    }

    func testSearchInteractionEffectiveDefaultScopeRequiresAccessibilityForWindowScope() {
        XCTAssertEqual(
            SearchInteractionPreferencesStore.effectiveDefaultScope(
                rawValue: SwitcherSearchScope.window.rawValue,
                accessibilityTrusted: false
            ),
            .app
        )
        XCTAssertEqual(
            SearchInteractionPreferencesStore.effectiveDefaultScope(
                rawValue: SwitcherSearchScope.window.rawValue,
                accessibilityTrusted: true
            ),
            .window
        )
    }

    func testSearchSettingsCardStateFallsBackToAppScopeWithoutAccessibilityPermission() {
        let state = SearchSettingsCardState(
            searchEnabled: true,
            searchDefaultScopeRaw: SwitcherSearchScope.window.rawValue,
            appLanguageRaw: AppLanguage.simplifiedChinese.rawValue,
            accessibilityTrusted: false
        )

        XCTAssertEqual(state.availableScopes, [.app])
        XCTAssertEqual(state.resolvedScope, .app)
        XCTAssertFalse(state.isScopeSelectEnabled)
        XCTAssertEqual(
            state.summaryText,
            AppStrings.text(.searchSummaryAccessibilityRequired, language: .simplifiedChinese)
        )
    }

    func testInAppWindowHotkeyResolveAndLoadNormalizeInvalidValues() {
        let resolved = InAppWindowHotkeyPreferencesStore.resolve(
            primaryModifierRaw: "invalid",
            mainKeyRaw: "invalid"
        )
        XCTAssertEqual(resolved.primaryModifier, .control)
        XCTAssertEqual(resolved.mainKey, .tab)

        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }
        userDefaults.set("invalid", forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier)
        userDefaults.set("invalid", forKey: AppPreferenceKeys.inAppWindowHotkeyMainKey)

        let configuration = InAppWindowHotkeyPreferencesStore.load(userDefaults: userDefaults)
        XCTAssertEqual(configuration.primaryModifier, .control)
        XCTAssertEqual(configuration.mainKey, .tab)
        XCTAssertEqual(configuration.quitKey, .q)
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier),
            InAppWindowHotkeyPreferencesStore.defaultPrimaryModifier.rawValue
        )
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.inAppWindowHotkeyMainKey),
            InAppWindowHotkeyPreferencesStore.defaultMainKey.rawValue
        )
    }

    func testInAppWindowHotkeyResolveAvoidingMainConflictFallsBackToNonConflictingModifier() {
        let mainConfiguration = SwitcherHotkeyConfiguration(
            primaryModifier: .control,
            mainKey: .tab,
            quitKey: .q
        )

        let resolved = InAppWindowHotkeyPreferencesStore.resolveAvoidingMainHotkeyConflict(
            primaryModifierRaw: SwitcherPrimaryModifier.control.rawValue,
            mainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            mainHotkeyConfiguration: mainConfiguration
        )
        XCTAssertEqual(resolved.primaryModifier, .option)
        XCTAssertEqual(resolved.mainKey, .tab)
    }

    func testInAppWindowHotkeyResolveAvoidingMainConflictKeepsNonConflictingShortcut() {
        let mainConfiguration = SwitcherHotkeyConfiguration(
            primaryModifier: .option,
            mainKey: .tab,
            quitKey: .q
        )

        let resolved = InAppWindowHotkeyPreferencesStore.resolveAvoidingMainHotkeyConflict(
            primaryModifierRaw: SwitcherPrimaryModifier.option.rawValue,
            mainKeyRaw: SwitcherHotkeyKey.space.rawValue,
            mainHotkeyConfiguration: mainConfiguration
        )
        XCTAssertEqual(resolved.primaryModifier, .option)
        XCTAssertEqual(resolved.mainKey, .space)
    }

    func testSwitcherBehaviorAndVisibilityPreferenceDefaults() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        XCTAssertFalse(AppVisibilityPreferencesStore.loadShowInCommandTab(userDefaults: userDefaults))
        userDefaults.set(true, forKey: AppPreferenceKeys.showInCommandTab)
        XCTAssertTrue(AppVisibilityPreferencesStore.loadShowInCommandTab(userDefaults: userDefaults))
        userDefaults.set(false, forKey: AppPreferenceKeys.showInCommandTab)
        XCTAssertFalse(AppVisibilityPreferencesStore.loadShowInCommandTab(userDefaults: userDefaults))

        let defaultPreferences = SwitcherBehaviorPreferencesStore.loadSwitcherPreferences(
            userDefaults: userDefaults
        )
        XCTAssertFalse(defaultPreferences.autoRestoreMinimizedWindowOnSwitch)
        XCTAssertEqual(defaultPreferences.mainSwitcherHotkey, .optionTab)

        userDefaults.set(true, forKey: AppPreferenceKeys.autoRestoreMinimizedWindowOnSwitch)
        let customPreferences = SwitcherBehaviorPreferencesStore.loadSwitcherPreferences(
            userDefaults: userDefaults
        )
        XCTAssertTrue(customPreferences.autoRestoreMinimizedWindowOnSwitch)
    }

    @MainActor
    func testCurrentAppActivationPolicyProjectsIntoHiddenAppIDs() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        let currentAppID = Bundle.main.bundleIdentifier ?? "pid:\(ProcessInfo.processInfo.processIdentifier)"

        userDefaults.set(false, forKey: AppPreferenceKeys.showInCommandTab)
        let hiddenModel = AppVisibilityManagerModel(userDefaults: userDefaults)

        XCTAssertTrue(hiddenModel.hiddenAppIDs.contains(currentAppID))
        XCTAssertEqual(hiddenModel.hiddenCount, 1)

        hiddenModel.setHidden(false, for: currentAppID)
        XCTAssertTrue(AppVisibilityPreferencesStore.loadShowInCommandTab(userDefaults: userDefaults))
        XCTAssertFalse(hiddenModel.hiddenAppIDs.contains(currentAppID))
        XCTAssertEqual(hiddenModel.hiddenCount, 0)

        hiddenModel.setHidden(true, for: currentAppID)
        XCTAssertFalse(AppVisibilityPreferencesStore.loadShowInCommandTab(userDefaults: userDefaults))
        XCTAssertTrue(hiddenModel.hiddenAppIDs.contains(currentAppID))
        XCTAssertEqual(hiddenModel.hiddenCount, 1)
    }

    func testAppVisibilityIconStateRefreshesWhenAppSourceChanges() {
        let firstApp = InstalledAppRecord(
            id: "com.example.first",
            displayName: "First",
            bundleIdentifier: "com.example.first",
            path: "/Applications/First.app",
            isRunning: false
        )
        let secondApp = InstalledAppRecord(
            id: "com.example.second",
            displayName: "Second",
            bundleIdentifier: "com.example.second",
            path: "/Applications/Second.app",
            isRunning: false
        )

        var resolvedAppIDs: [String] = []
        let resolveIcon: (InstalledAppRecord) -> NSImage? = { app in
            resolvedAppIDs.append(app.id)
            return NSImage(size: NSSize(width: 1, height: 1))
        }

        var state = AppVisibilityIconState.resolved(for: firstApp, resolveIcon: resolveIcon)
        XCTAssertEqual(resolvedAppIDs, [firstApp.id])
        XCTAssertNotNil(state.icon(matching: AppVisibilityIconSourceKey(app: firstApp)))
        XCTAssertNil(state.icon(matching: AppVisibilityIconSourceKey(app: secondApp)))

        state.refreshIfNeeded(for: firstApp, resolveIcon: resolveIcon)
        XCTAssertEqual(resolvedAppIDs, [firstApp.id])

        state.refreshIfNeeded(for: secondApp, resolveIcon: resolveIcon)
        XCTAssertEqual(resolvedAppIDs, [firstApp.id, secondApp.id])
        XCTAssertNil(state.icon(matching: AppVisibilityIconSourceKey(app: firstApp)))
        XCTAssertNotNil(state.icon(matching: AppVisibilityIconSourceKey(app: secondApp)))
    }

    @MainActor
    func testStatusItemOpenActionUnhidesAndRestoresFirstRegularWindow() {
        let panelWindow = TestAppWindow(isPanelWindow: true, isMiniaturized: true)
        let mainWindow = TestAppWindow(isPanelWindow: false, isMiniaturized: true)
        let application = TestAppWindowApplication(
            isHidden: true,
            appWindows: [panelWindow, mainWindow]
        )

        let delegate = AppDelegate()
        delegate.handleStatusItemOpenAction(application: application)

        XCTAssertEqual(application.activateCallCount, 1)
        XCTAssertEqual(application.lastActivateIgnoringOtherApps, true)
        XCTAssertEqual(application.unhideCallCount, 1)
        XCTAssertEqual(application.showSettingsWindowActionCount, 0)
        XCTAssertFalse(application.isHidden)

        XCTAssertEqual(panelWindow.deminiaturizeCallCount, 0)
        XCTAssertEqual(panelWindow.makeKeyAndOrderFrontCallCount, 0)
        XCTAssertEqual(panelWindow.orderFrontRegardlessCallCount, 0)

        XCTAssertEqual(mainWindow.deminiaturizeCallCount, 1)
        XCTAssertEqual(mainWindow.makeKeyAndOrderFrontCallCount, 1)
        XCTAssertEqual(mainWindow.orderFrontRegardlessCallCount, 1)
        XCTAssertFalse(mainWindow.isMiniaturized)
    }

    @MainActor
    func testStatusItemOpenActionOpensHomeSceneWhenNoRegularWindowExists() {
        let panelWindow = TestAppWindow(isPanelWindow: true, isMiniaturized: false)
        let application = TestAppWindowApplication(
            isHidden: false,
            appWindows: [panelWindow]
        )

        let delegate = AppDelegate()
        delegate.handleStatusItemOpenAction(application: application)

        XCTAssertEqual(application.activateCallCount, 1)
        XCTAssertEqual(application.lastActivateIgnoringOtherApps, true)
        XCTAssertEqual(application.unhideCallCount, 0)
        XCTAssertEqual(application.showSettingsWindowActionCount, 1)

        XCTAssertEqual(panelWindow.deminiaturizeCallCount, 0)
        XCTAssertEqual(panelWindow.makeKeyAndOrderFrontCallCount, 0)
        XCTAssertEqual(panelWindow.orderFrontRegardlessCallCount, 0)
    }

    @MainActor
    func testStatusItemOpenActionIgnoresStatusBarAndClosedWindows() {
        let statusBarWindow = TestAppWindow(
            isPanelWindow: false,
            isMiniaturized: false,
            flowTabWindowLevel: .statusBar
        )
        let appMenuWindow = TestAppWindow(
            isPanelWindow: false,
            isMiniaturized: false,
            canBecomeKeyWindow: true,
            isAppContentWindow: false
        )
        let closedMainWindow = TestAppWindow(
            isPanelWindow: false,
            isMiniaturized: false,
            isVisible: false
        )
        let application = TestAppWindowApplication(
            isHidden: false,
            appWindows: [statusBarWindow, appMenuWindow, closedMainWindow]
        )

        let delegate = AppDelegate()
        delegate.handleStatusItemOpenAction(application: application)

        XCTAssertEqual(application.activateCallCount, 1)
        XCTAssertEqual(application.lastActivateIgnoringOtherApps, true)
        XCTAssertEqual(application.showSettingsWindowActionCount, 1)

        XCTAssertEqual(statusBarWindow.makeKeyAndOrderFrontCallCount, 0)
        XCTAssertEqual(statusBarWindow.orderFrontRegardlessCallCount, 0)
        XCTAssertEqual(appMenuWindow.makeKeyAndOrderFrontCallCount, 0)
        XCTAssertEqual(appMenuWindow.orderFrontRegardlessCallCount, 0)
        XCTAssertEqual(closedMainWindow.makeKeyAndOrderFrontCallCount, 0)
        XCTAssertEqual(closedMainWindow.orderFrontRegardlessCallCount, 0)
    }

    @MainActor
    func testAppWindowCoordinatorSkipsActivationWhenSwitcherPanelIsVisible() {
        let switcherPanelWindow = TestAppWindow(
            isPanelWindow: true,
            isMiniaturized: false,
            isVisible: true,
            flowTabWindowIdentifier: AppWindowCoordinator.switcherPanelWindowIdentifier
        )
        let mainWindow = TestAppWindow(isPanelWindow: false, isMiniaturized: false)
        let application = TestAppWindowApplication(
            isHidden: true,
            appWindows: [switcherPanelWindow, mainWindow]
        )

        AppWindowCoordinator.activateMainWindowOrOpenHomeScene(application: application)

        XCTAssertEqual(application.activateCallCount, 0)
        XCTAssertEqual(application.unhideCallCount, 0)
        XCTAssertEqual(application.showSettingsWindowActionCount, 0)
        XCTAssertEqual(mainWindow.makeKeyAndOrderFrontCallCount, 0)
        XCTAssertEqual(mainWindow.orderFrontRegardlessCallCount, 0)
    }

    func testRuntimeDiagnosticsReadRecentLinesAppliesMinimumLevelFilter() async {
        await resetRuntimeLogsForTest()

        let category = "UnitTestFilter-\(UUID().uuidString)"

        RuntimeDiagnostics.shared.log(level: .info, category: category, message: "info")
        RuntimeDiagnostics.shared.log(level: .warning, category: category, message: "warning")
        RuntimeDiagnostics.shared.log(level: .error, category: category, message: "error")

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 50, minimumLevel: .warning)
        let scopedLines = lines.filter { $0.contains("[\(category)]") }

        XCTAssertEqual(scopedLines.count, 2)
        XCTAssertTrue(scopedLines.contains(where: { $0.contains("[WARN]") }))
        XCTAssertTrue(scopedLines.contains(where: { $0.contains("[ERROR]") }))
        XCTAssertFalse(scopedLines.contains(where: { $0.contains("[INFO]") }))
    }

    func testRuntimeDiagnosticsReadRecentLinesSinceSnapshotReturnsOnlyNewLines() async {
        await resetRuntimeLogsForTest()

        let oldCategory = "UnitTestDeltaOld-\(UUID().uuidString)"
        let newCategory = "UnitTestDeltaNew-\(UUID().uuidString)"

        RuntimeDiagnostics.shared.log(level: .info, category: oldCategory, message: "old")
        let snapshot = await RuntimeDiagnostics.shared.makeReadSnapshot()

        RuntimeDiagnostics.shared.log(level: .info, category: newCategory, message: "new-1")
        RuntimeDiagnostics.shared.log(level: .warning, category: newCategory, message: "new-2")

        let deltaLines = await RuntimeDiagnostics.shared.readRecentLines(
            limit: 50,
            minimumLevel: .info,
            since: snapshot
        )
        let scopedLines = deltaLines.filter { $0.contains("[\(newCategory)]") }

        XCTAssertEqual(scopedLines.count, 2)
        XCTAssertFalse(deltaLines.contains(where: { $0.contains("[\(oldCategory)]") }))
        XCTAssertTrue(scopedLines.contains(where: { $0.contains("[INFO]") }))
        XCTAssertTrue(scopedLines.contains(where: { $0.contains("[WARN]") }))
    }

    func testRuntimeDiagnosticsReadRecentLinesHonorsLimitAndKeepsNewestEntries() async {
        await resetRuntimeLogsForTest()

        let marker = "RuntimeDiagnosticsLimit\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        for index in 1...5 {
            RuntimeDiagnostics.shared.log(
                level: .info,
                category: "\(marker)\(index)",
                message: "entry"
            )
        }

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 2, minimumLevel: .info)
        let scopedLines = lines.filter { $0.contains(marker) }

        XCTAssertEqual(scopedLines.count, 2)
        XCTAssertTrue(scopedLines[0].contains("[\(marker)4]"))
        XCTAssertTrue(scopedLines[1].contains("[\(marker)5]"))
    }

    func testRuntimeLogSuppressesDebugAndInfoOutsideDiagnosticSession() async {
        let defaults = UserDefaults.standard
        let previousExpiration = defaults.object(forKey: AppPreferenceKeys.diagnosticSessionExpiration)
        let previousLevel = defaults.object(forKey: AppPreferenceKeys.runtimeLogLevel)
        defer {
            restoreUserDefaultsValue(
                previousExpiration,
                forKey: AppPreferenceKeys.diagnosticSessionExpiration,
                userDefaults: defaults
            )
            restoreUserDefaultsValue(
                previousLevel,
                forKey: AppPreferenceKeys.runtimeLogLevel,
                userDefaults: defaults
            )
        }

        RuntimeDiagnosticSessionStore.stop(userDefaults: defaults)
        defaults.set(RuntimeLogLevel.debug.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)
        await resetRuntimeLogsForTest()

        RuntimeLog.debug(.inputTrace, "debug")
        RuntimeLog.info(.inputTrace, "info")
        RuntimeLog.warning(.inputTrace, "warning")

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 50, minimumLevel: .debug)
        let scopedLines = lines.filter { $0.contains("[InputTrace]") }

        XCTAssertFalse(scopedLines.contains(where: { $0.contains("[DEBUG]") }))
        XCTAssertFalse(scopedLines.contains(where: { $0.contains("[INFO]") }))
        XCTAssertTrue(scopedLines.contains(where: { $0.contains("[WARN]") }))
    }

    func testRuntimeLogTypedCategoryKeepsWarningsAndErrorsOutsideDiagnosticSession() async {
        let defaults = UserDefaults.standard
        let previousExpiration = defaults.object(forKey: AppPreferenceKeys.diagnosticSessionExpiration)
        let previousLevel = defaults.object(forKey: AppPreferenceKeys.runtimeLogLevel)
        defer {
            restoreUserDefaultsValue(
                previousExpiration,
                forKey: AppPreferenceKeys.diagnosticSessionExpiration,
                userDefaults: defaults
            )
            restoreUserDefaultsValue(
                previousLevel,
                forKey: AppPreferenceKeys.runtimeLogLevel,
                userDefaults: defaults
            )
        }

        RuntimeDiagnosticSessionStore.stop(userDefaults: defaults)
        defaults.set(RuntimeLogLevel.debug.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)
        await resetRuntimeLogsForTest()

        RuntimeLog.debug(.activation, "debug")
        RuntimeLog.info(.activation, "info")
        RuntimeLog.warning(.activation, "warning")
        RuntimeLog.error(.activation, "error")

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 50, minimumLevel: .debug)
        let scopedLines = lines.filter { $0.contains("[Activation]") }

        XCTAssertFalse(scopedLines.contains(where: { $0.contains("[DEBUG]") }))
        XCTAssertFalse(scopedLines.contains(where: { $0.contains("[INFO]") }))
        XCTAssertTrue(scopedLines.contains(where: { $0.contains("[WARN]") }))
        XCTAssertTrue(scopedLines.contains(where: { $0.contains("[ERROR]") }))
    }

    func testRuntimeLogDiagnosticSessionAllowsDebugAndInfoWhenMinimumLevelAllows() async {
        let defaults = UserDefaults.standard
        let previousExpiration = defaults.object(forKey: AppPreferenceKeys.diagnosticSessionExpiration)
        let previousLevel = defaults.object(forKey: AppPreferenceKeys.runtimeLogLevel)
        defer {
            restoreUserDefaultsValue(
                previousExpiration,
                forKey: AppPreferenceKeys.diagnosticSessionExpiration,
                userDefaults: defaults
            )
            restoreUserDefaultsValue(
                previousLevel,
                forKey: AppPreferenceKeys.runtimeLogLevel,
                userDefaults: defaults
            )
        }

        RuntimeDiagnosticSessionStore.start(userDefaults: defaults)
        defaults.set(RuntimeLogLevel.debug.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)
        await resetRuntimeLogsForTest()

        let category = "UnitTestSession\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        RuntimeLog.debug(category, "debug")
        RuntimeLog.info(category, "info")

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 50, minimumLevel: .debug)
        let scopedLines = lines.filter { $0.contains("[\(category)]") }

        XCTAssertTrue(scopedLines.contains(where: { $0.contains("[DEBUG]") }))
        XCTAssertTrue(scopedLines.contains(where: { $0.contains("[INFO]") }))
    }

    func testRuntimeLogPermissionWarningRecordsOutsideDiagnosticSession() async {
        let defaults = UserDefaults.standard
        let previousExpiration = defaults.object(forKey: AppPreferenceKeys.diagnosticSessionExpiration)
        let previousLevel = defaults.object(forKey: AppPreferenceKeys.runtimeLogLevel)
        defer {
            restoreUserDefaultsValue(
                previousExpiration,
                forKey: AppPreferenceKeys.diagnosticSessionExpiration,
                userDefaults: defaults
            )
            restoreUserDefaultsValue(
                previousLevel,
                forKey: AppPreferenceKeys.runtimeLogLevel,
                userDefaults: defaults
            )
        }

        RuntimeDiagnosticSessionStore.stop(userDefaults: defaults)
        defaults.set(RuntimeLogLevel.debug.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)
        await resetRuntimeLogsForTest()

        RuntimeLog.warning(.permission, "permission-missing")

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 50, minimumLevel: .debug)
        let scopedLines = lines.filter { $0.contains("[WARN] [Permission]") }

        XCTAssertEqual(scopedLines.count, 1)
    }

    private func makeHotkeySettingsState(
        commandTabTakeoverRegistrationState: CommandTabTakeoverRegistrationState
    ) -> HotkeySettingsCardState {
        HotkeySettingsCardState(
            hotkeyPrimaryModifierRaw: SwitcherPrimaryModifier.command.rawValue,
            hotkeyMainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            hotkeyQuitKeyRaw: SwitcherHotkeyKey.q.rawValue,
            inAppWindowHotkeyPrimaryModifierRaw: SwitcherPrimaryModifier.option.rawValue,
            inAppWindowHotkeyMainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            commandTabTakeoverRegistrationState: commandTabTakeoverRegistrationState,
            accessibilityTrusted: true,
            appLanguageRaw: AppLanguage.simplifiedChinese.rawValue
        )
    }

    private func makeSettingsPageState(
        language: AppLanguage = .simplifiedChinese
    ) -> AppKitSettingsPageState {
        AppKitSettingsPageState(
            showShortcutHint: true,
            showInCommandTab: true,
            themeModeRaw: ThemeMode.followSystem.rawValue,
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
            targetNSAppearanceName: .aqua
        )
    }

    private func requiredFixedSettingsControlWidthConstraints(in view: NSView) -> [NSLayoutConstraint] {
        descendantViews(in: view)
            .flatMap(\.constraints)
            .filter { constraint in
                guard constraint.firstAttribute == .width,
                    constraint.relation == .equal,
                    constraint.secondItem == nil,
                    constraint.priority == .required
                else {
                    return false
                }

                return constraint.firstItem is FlowSettingsSegmentedControl
                    || constraint.firstItem is FlowSettingsSelectControl
                    || constraint.firstItem is FlowSettingsActionButton
            }
    }

    private func descendantViews(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendantViews(in: $0) }
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

    @MainActor
    private func hostedHomePermissionStatusTitleLabel(colorScheme: ColorScheme) throws -> NSTextField {
        let hostedView = NSHostingView(
            rootView: HomePermissionStatusCard(
                accessibilityTrusted: false,
                screenCaptureTrusted: false,
                language: .simplifiedChinese,
                colorScheme: colorScheme
            )
            .frame(width: 180, height: HomePageLayout.bottomStatusHeight)
        )
        hostedView.frame = NSRect(x: 0, y: 0, width: 180, height: HomePageLayout.bottomStatusHeight)
        hostedView.layoutSubtreeIfNeeded()

        let label: NSTextField? = descendant(
            in: hostedView,
            identifier: "flowtab.sidebar.permission.accessibility"
        )
        return try XCTUnwrap(label)
    }

    private func assertColor(
        _ actual: NSColor?,
        matches expected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actualColor = actual?.usingColorSpace(.sRGB),
            let expectedColor = expected.usingColorSpace(.sRGB)
        else {
            XCTFail("Expected comparable sRGB colors", file: file, line: line)
            return
        }

        XCTAssertEqual(actualColor.redComponent, expectedColor.redComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualColor.greenComponent, expectedColor.greenComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualColor.blueComponent, expectedColor.blueComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualColor.alphaComponent, expectedColor.alphaComponent, accuracy: 0.001, file: file, line: line)
    }

    private func waitForRunLoopCondition(
        timeout: TimeInterval,
        predicate: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
        return predicate()
    }

    private func restoreUserDefaultsValue(_ value: String?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func currentAppScopedDefaultString(forKey key: String) -> String? {
        guard let domainName = Bundle.main.bundleIdentifier else { return nil }
        return UserDefaults.standard.persistentDomain(forName: domainName)?[key] as? String
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
        guard let card = descendantViews(in: view).compactMap({ $0 as? FlowSettingsCardView }).first,
            let cgColor = card.layer?.backgroundColor,
            let color = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB)
        else {
            return false
        }
        return color.redComponent < 0.3 && color.greenComponent < 0.3 && color.blueComponent < 0.3
    }

}

@MainActor
private final class FakeFlowPresentationSystemThemeProvider: FlowPresentationSystemThemeProviding {
    private(set) var currentColorScheme: ColorScheme
    private var observers: [UUID: @MainActor (ColorScheme) -> Void] = [:]

    init(colorScheme: ColorScheme) {
        currentColorScheme = colorScheme
    }

    var observerCount: Int {
        observers.count
    }

    func observeColorSchemeChanges(
        _ handler: @escaping @MainActor (ColorScheme) -> Void
    ) -> FlowPresentationThemeObservation {
        let id = UUID()
        observers[id] = handler
        return FlowPresentationThemeObservation { [weak self] in
            Task { @MainActor [weak self] in
                self?.observers[id] = nil
            }
        }
    }

    func pushColorScheme(_ colorScheme: ColorScheme) {
        currentColorScheme = colorScheme
        for observer in observers.values {
            observer(colorScheme)
        }
    }
}
