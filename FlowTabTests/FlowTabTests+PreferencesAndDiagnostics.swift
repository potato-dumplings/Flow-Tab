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
                as: FlowCapsuleSegmentedControl.self
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
            screenCaptureTrusted: false
        )

        XCTAssertEqual(state.accessibilityStatusText, AppStrings.text(.permissionAccessibilityDenied))
        XCTAssertEqual(state.accessibilityButtonTitle, AppStrings.text(.permissionAccessibilityRequest))
        XCTAssertEqual(state.screenCaptureStatusText, AppStrings.text(.permissionScreenDenied))
        XCTAssertEqual(state.screenCaptureButtonTitle, AppStrings.text(.permissionScreenRequest))
    }

    func testPermissionSettingsCardStateUsesGrantedCopyWhenPermissionsPresent() {
        let state = PermissionSettingsCardState(
            showPermissionReminder: false,
            allowLaunchAtLogin: true,
            accessibilityTrusted: true,
            screenCaptureTrusted: true
        )

        XCTAssertEqual(state.accessibilityStatusText, AppStrings.text(.permissionAccessibilityGranted))
        XCTAssertEqual(state.accessibilityButtonTitle, AppStrings.text(.permissionAccessibilityClose))
        XCTAssertEqual(state.screenCaptureStatusText, AppStrings.text(.permissionScreenGranted))
        XCTAssertEqual(state.screenCaptureButtonTitle, AppStrings.text(.permissionScreenClose))
    }

    @MainActor
    func testPermissionSettingsRowsStayCompactWhenVerticalStackGetsExtraHeight() throws {
        let accessibilityRow = PermissionStatusControlRowView(
            control: FlowGradientActionButton(),
            controlWidth: 166
        )
        let screenCaptureRow = PermissionStatusControlRowView(
            control: FlowGradientActionButton(),
            controlWidth: 166
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

        XCTAssertLessThanOrEqual(accessibilityRow.frame.height, 40)
        XCTAssertLessThanOrEqual(screenCaptureRow.frame.height, 40)
    }

    func testPermissionPollingPolicyBuildsTimeoutDescriptionFromCurrentLimits() {
        let policy = PermissionPollingPolicy.default

        XCTAssertEqual(policy.intervalNanoseconds, 500_000_000)
        XCTAssertEqual(policy.attemptLimit, 40)
        XCTAssertEqual(policy.timeoutSeconds, 20)
        XCTAssertEqual(policy.timeoutDescription, "20s")
    }

    func testPermissionPollingTaskRegistryTracksMultipleTargets() {
        var registry = PermissionPollingTaskRegistry()

        registry.markStarted(.accessibility)
        registry.markStarted(.screenCapture)
        registry.markStarted(.accessibility)

        XCTAssertTrue(registry.isActive(.accessibility))
        XCTAssertTrue(registry.isActive(.screenCapture))
        XCTAssertEqual(registry.activeTargets, [.accessibility, .screenCapture])

        registry.markStopped(.accessibility)

        XCTAssertFalse(registry.isActive(.accessibility))
        XCTAssertTrue(registry.isActive(.screenCapture))

        registry.markAllStopped()

        XCTAssertTrue(registry.activeTargets.isEmpty)
    }

    func testPermissionPollingDiagnosticIncludesAttemptElapsedAndFinalState() {
        let diagnostic = PermissionPollingDiagnostic(
            target: .screenCapture,
            attempt: 40,
            attemptLimit: 40,
            elapsedMs: 20_000,
            finalPermissionGranted: false,
            timeoutDescription: "20s",
            bundleIdentifier: "io.github.flowtab.tests",
            bundlePath: "/Applications/FlowTab.app",
            action: .timeout
        )

        XCTAssertTrue(diagnostic.logMessage.contains("target=screenCapture"))
        XCTAssertTrue(diagnostic.logMessage.contains("action=timeout"))
        XCTAssertTrue(diagnostic.logMessage.contains("attempt=40/40"))
        XCTAssertTrue(diagnostic.logMessage.contains("elapsedMs=20000.000"))
        XCTAssertTrue(diagnostic.logMessage.contains("finalPermissionGranted=false"))
        XCTAssertTrue(diagnostic.logMessage.contains("timeout=20s"))
    }

    @MainActor
    func testHotkeyTakeoverInactiveStatusShowsAfterConfirmationDelay() {
        let view = HotkeySettingsCardAppKitView(takeoverInactiveDisplayDelay: 0.01)
        let statusLabel: NSTextField? = descendant(
            in: view,
            identifier: "flowtab.settings.hotkey.main-takeover-status"
        )

        view.update(with: makeHotkeySettingsState(commandTabTakeoverActive: false))

        XCTAssertTrue(waitForRunLoopCondition(timeout: 0.5) {
            statusLabel?.isHidden == false
        })
        XCTAssertEqual(statusLabel?.stringValue, AppStrings.text(.hotkeyCommandTabTakeoverInactive))
    }

    @MainActor
    func testHotkeyTakeoverInactiveDelayDoesNotShowStaleStatusAfterRecovery() {
        let view = HotkeySettingsCardAppKitView(takeoverInactiveDisplayDelay: 0.01)
        let statusLabel: NSTextField? = descendant(
            in: view,
            identifier: "flowtab.settings.hotkey.main-takeover-status"
        )

        view.update(with: makeHotkeySettingsState(commandTabTakeoverActive: false))
        view.update(with: makeHotkeySettingsState(commandTabTakeoverActive: true))

        XCTAssertTrue(waitForRunLoopCondition(timeout: 0.5) {
            statusLabel?.stringValue == AppStrings.text(.hotkeyCommandTabTakeoverActive)
        })
        XCTAssertEqual(statusLabel?.stringValue, AppStrings.text(.hotkeyCommandTabTakeoverActive))
        XCTAssertFalse(statusLabel?.isHidden ?? true)
    }

    func testRuntimeLogLevelOrderingUsesPriority() {
        XCTAssertLessThan(RuntimeLogLevel.debug, .info)
        XCTAssertLessThan(RuntimeLogLevel.info, .warning)
        XCTAssertLessThan(RuntimeLogLevel.warning, .error)
    }

    func testDiagnosticsRefreshPolicyOwnsRuntimeLogsRefreshCadence() {
        let policy = DiagnosticsRefreshPolicy.runtimeLogs

        XCTAssertEqual(policy.intervalNanoseconds, 1_000_000_000)
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

    @MainActor
    func testAppVisibilityManagerShowsStoredHiddenAppIDsMissingFromInventory() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        let missingAppID = "com.flowtab.hidden.missing"
        userDefaults.set(true, forKey: AppPreferenceKeys.showInCommandTab)
        AppVisibilityPreferencesStore.saveHiddenAppIDs([missingAppID], userDefaults: userDefaults)

        await withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-mock-runtime"]) {
            let model = AppVisibilityManagerModel(userDefaults: userDefaults)
            model.filter = .hidden
            model.reload()

            let didFinishLoading = await waitUntil(
                "app visibility manager finishes loading hidden missing app ids",
                timeout: 5.0,
                pollIntervalNanoseconds: 20_000_000
            ) {
                !model.isLoading
            }
            XCTAssertTrue(didFinishLoading)

            XCTAssertFalse(model.isLoading)
            XCTAssertEqual(model.hiddenCount, 1)
            XCTAssertEqual(model.visibleApps.map(\.id), [missingAppID])
            XCTAssertEqual(model.selectedApp?.id, missingAppID)
        }
    }

    @MainActor
    func testAppVisibilityManagerSearchUsesSharedPinyinMatching() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        await withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-mock-runtime"]) {
            let model = AppVisibilityManagerModel(userDefaults: userDefaults)
            model.query = "ceshi"
            model.reload()

            let didFinishLoading = await waitUntil(
                "app visibility manager finishes loading searchable mock apps",
                timeout: 5.0,
                pollIntervalNanoseconds: 20_000_000
            ) {
                !model.isLoading
            }
            XCTAssertTrue(didFinishLoading)

            XCTAssertEqual(model.visibleApps.map(\.id), ["com.xxx.test"])
            XCTAssertEqual(model.selectedApp?.id, "com.xxx.test")
        }
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
        let closedMainWindow = TestAppWindow(
            isPanelWindow: false,
            isMiniaturized: false,
            isVisible: false
        )
        let application = TestAppWindowApplication(
            isHidden: false,
            appWindows: [statusBarWindow, closedMainWindow]
        )

        let delegate = AppDelegate()
        delegate.handleStatusItemOpenAction(application: application)

        XCTAssertEqual(application.activateCallCount, 1)
        XCTAssertEqual(application.lastActivateIgnoringOtherApps, true)
        XCTAssertEqual(application.showSettingsWindowActionCount, 1)

        XCTAssertEqual(statusBarWindow.makeKeyAndOrderFrontCallCount, 0)
        XCTAssertEqual(statusBarWindow.orderFrontRegardlessCallCount, 0)
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

        let marker = "RuntimeDiagnosticsFilter-\(UUID().uuidString)"
        let infoToken = "\(marker)-info"
        let warningToken = "\(marker)-warning"
        let errorToken = "\(marker)-error"

        RuntimeDiagnostics.shared.log(level: .info, category: "UnitTest", message: infoToken)
        RuntimeDiagnostics.shared.log(level: .warning, category: "UnitTest", message: warningToken)
        RuntimeDiagnostics.shared.log(level: .error, category: "UnitTest", message: errorToken)

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 50, minimumLevel: .warning)
        let scopedLines = lines.filter { $0.contains(marker) }

        XCTAssertTrue(scopedLines.contains(where: { $0.contains(warningToken) }))
        XCTAssertTrue(scopedLines.contains(where: { $0.contains(errorToken) }))
        XCTAssertFalse(scopedLines.contains(where: { $0.contains(infoToken) }))
    }

    func testRuntimeDiagnosticsReadRecentLinesSinceSnapshotReturnsOnlyNewLines() async {
        await resetRuntimeLogsForTest()

        let marker = "RuntimeDiagnosticsDelta-\(UUID().uuidString)"
        let oldToken = "\(marker)-old"
        let newToken1 = "\(marker)-new-1"
        let newToken2 = "\(marker)-new-2"

        RuntimeDiagnostics.shared.log(level: .info, category: "UnitTest", message: oldToken)
        let snapshot = await RuntimeDiagnostics.shared.makeReadSnapshot()

        RuntimeDiagnostics.shared.log(level: .info, category: "UnitTest", message: newToken1)
        RuntimeDiagnostics.shared.log(level: .warning, category: "UnitTest", message: newToken2)

        let deltaLines = await RuntimeDiagnostics.shared.readRecentLines(
            limit: 50,
            minimumLevel: .info,
            since: snapshot
        )
        let scopedLines = deltaLines.filter { $0.contains(marker) }

        XCTAssertFalse(scopedLines.contains(where: { $0.contains(oldToken) }))
        XCTAssertTrue(scopedLines.contains(where: { $0.contains(newToken1) }))
        XCTAssertTrue(scopedLines.contains(where: { $0.contains(newToken2) }))
    }

    func testRuntimeDiagnosticsReadRecentLinesHonorsLimitAndKeepsNewestEntries() async {
        await resetRuntimeLogsForTest()

        let marker = "RuntimeDiagnosticsLimit-\(UUID().uuidString)"
        for index in 1...5 {
            RuntimeDiagnostics.shared.log(
                level: .info,
                category: "UnitTest",
                message: "\(marker)-\(index)"
            )
        }

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 2, minimumLevel: .info)
        let scopedLines = lines.filter { $0.contains(marker) }

        XCTAssertEqual(scopedLines.count, 2)
        XCTAssertTrue(scopedLines[0].contains("\(marker)-4"))
        XCTAssertTrue(scopedLines[1].contains("\(marker)-5"))
    }

    func testRuntimeLogNoisyCategorySuppressesInfoWhenVerboseDisabled() async {
        let defaults = UserDefaults.standard
        let previousVerbose = defaults.object(forKey: AppPreferenceKeys.enableVerboseDiagnostics)
        let previousLevel = defaults.object(forKey: AppPreferenceKeys.runtimeLogLevel)
        defer {
            restoreUserDefaultsValue(
                previousVerbose,
                forKey: AppPreferenceKeys.enableVerboseDiagnostics,
                userDefaults: defaults
            )
            restoreUserDefaultsValue(
                previousLevel,
                forKey: AppPreferenceKeys.runtimeLogLevel,
                userDefaults: defaults
            )
        }

        defaults.set(false, forKey: AppPreferenceKeys.enableVerboseDiagnostics)
        defaults.set(RuntimeLogLevel.debug.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)
        await resetRuntimeLogsForTest()

        let marker = "RuntimeLogNoisy-\(UUID().uuidString)"
        RuntimeLog.debug("InputTrace", "\(marker)-debug")
        RuntimeLog.info("InputTrace", "\(marker)-info")
        RuntimeLog.warning("InputTrace", "\(marker)-warning")

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 50, minimumLevel: .debug)
        let scopedLines = lines.filter { $0.contains(marker) }

        XCTAssertFalse(scopedLines.contains(where: { $0.contains("\(marker)-debug") }))
        XCTAssertFalse(scopedLines.contains(where: { $0.contains("\(marker)-info") }))
        XCTAssertTrue(scopedLines.contains(where: { $0.contains("\(marker)-warning") }))
    }

    func testRuntimeLogTypedNoisyCategorySuppressesDebugAndInfoWhenVerboseDisabled() async {
        let defaults = UserDefaults.standard
        let previousVerbose = defaults.object(forKey: AppPreferenceKeys.enableVerboseDiagnostics)
        let previousLevel = defaults.object(forKey: AppPreferenceKeys.runtimeLogLevel)
        defer {
            restoreUserDefaultsValue(
                previousVerbose,
                forKey: AppPreferenceKeys.enableVerboseDiagnostics,
                userDefaults: defaults
            )
            restoreUserDefaultsValue(
                previousLevel,
                forKey: AppPreferenceKeys.runtimeLogLevel,
                userDefaults: defaults
            )
        }

        defaults.set(false, forKey: AppPreferenceKeys.enableVerboseDiagnostics)
        defaults.set(RuntimeLogLevel.debug.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)
        await resetRuntimeLogsForTest()

        let marker = "RuntimeLogTypedNoisy-\(UUID().uuidString)"
        RuntimeLog.debug(.activation, "\(marker)-debug")
        RuntimeLog.info(.activation, "\(marker)-info")
        RuntimeLog.warning(.activation, "\(marker)-warning")
        RuntimeLog.error(.activation, "\(marker)-error")

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 50, minimumLevel: .debug)
        let scopedLines = lines.filter { $0.contains(marker) }

        XCTAssertFalse(scopedLines.contains(where: { $0.contains("\(marker)-debug") }))
        XCTAssertFalse(scopedLines.contains(where: { $0.contains("\(marker)-info") }))
        XCTAssertTrue(scopedLines.contains(where: { $0.contains("\(marker)-warning") }))
        XCTAssertTrue(scopedLines.contains(where: { $0.contains("\(marker)-error") }))
    }

    func testRuntimeLogNonNoisyCategoryAllowsInfoWhenMinimumLevelAllows() async {
        let defaults = UserDefaults.standard
        let previousVerbose = defaults.object(forKey: AppPreferenceKeys.enableVerboseDiagnostics)
        let previousLevel = defaults.object(forKey: AppPreferenceKeys.runtimeLogLevel)
        defer {
            restoreUserDefaultsValue(
                previousVerbose,
                forKey: AppPreferenceKeys.enableVerboseDiagnostics,
                userDefaults: defaults
            )
            restoreUserDefaultsValue(
                previousLevel,
                forKey: AppPreferenceKeys.runtimeLogLevel,
                userDefaults: defaults
            )
        }

        defaults.set(false, forKey: AppPreferenceKeys.enableVerboseDiagnostics)
        defaults.set(RuntimeLogLevel.debug.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)
        await resetRuntimeLogsForTest()

        let marker = "RuntimeLogNormal-\(UUID().uuidString)"
        RuntimeLog.debug("UnitTest", "\(marker)-debug")
        RuntimeLog.info("UnitTest", "\(marker)-info")

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 50, minimumLevel: .debug)
        let scopedLines = lines.filter { $0.contains(marker) }

        XCTAssertTrue(scopedLines.contains(where: { $0.contains("\(marker)-debug") }))
        XCTAssertTrue(scopedLines.contains(where: { $0.contains("\(marker)-info") }))
    }

    func testRuntimeLogPermissionWarningRecordsWithoutVerboseDiagnostics() async {
        let defaults = UserDefaults.standard
        let previousVerbose = defaults.object(forKey: AppPreferenceKeys.enableVerboseDiagnostics)
        let previousLevel = defaults.object(forKey: AppPreferenceKeys.runtimeLogLevel)
        defer {
            restoreUserDefaultsValue(
                previousVerbose,
                forKey: AppPreferenceKeys.enableVerboseDiagnostics,
                userDefaults: defaults
            )
            restoreUserDefaultsValue(
                previousLevel,
                forKey: AppPreferenceKeys.runtimeLogLevel,
                userDefaults: defaults
            )
        }

        defaults.set(false, forKey: AppPreferenceKeys.enableVerboseDiagnostics)
        defaults.set(RuntimeLogLevel.debug.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)
        await resetRuntimeLogsForTest()

        let marker = "RuntimeLogPermission-\(UUID().uuidString)"
        RuntimeLog.warning(.permission, "\(marker)-permission-missing")

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 50, minimumLevel: .debug)
        let scopedLines = lines.filter { $0.contains(marker) }

        XCTAssertTrue(scopedLines.contains(where: { $0.contains("\(marker)-permission-missing") }))
    }

    private func makeHotkeySettingsState(commandTabTakeoverActive: Bool) -> HotkeySettingsCardState {
        HotkeySettingsCardState(
            hotkeyPrimaryModifierRaw: SwitcherPrimaryModifier.command.rawValue,
            hotkeyMainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            hotkeyQuitKeyRaw: SwitcherHotkeyKey.q.rawValue,
            inAppWindowHotkeyPrimaryModifierRaw: SwitcherPrimaryModifier.option.rawValue,
            inAppWindowHotkeyMainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            commandTabTakeoverActive: commandTabTakeoverActive,
            accessibilityTrusted: true
        )
    }

    private func makeSettingsPageState() -> AppKitSettingsPageState {
        AppKitSettingsPageState(
            showShortcutHint: true,
            showInCommandTab: true,
            themeModeRaw: ThemeMode.followSystem.rawValue,
            appLanguageRaw: AppLanguage.simplifiedChinese.rawValue,
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

                return constraint.firstItem is FlowCapsuleSegmentedControl
                    || constraint.firstItem is FlowFormSelectControl
                    || constraint.firstItem is FlowGradientActionButton
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

}
