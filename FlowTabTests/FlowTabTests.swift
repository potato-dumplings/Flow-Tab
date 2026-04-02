import AppKit
import XCTest
@testable import FlowTab
import FlowTabCore
import Carbon

final class FlowTabTests: XCTestCase {
    func testResolveKeepsCommandWhenMainShortcutIsCommandTab() {
        let configuration = SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: SwitcherPrimaryModifier.command.rawValue,
            mainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            quitKeyRaw: SwitcherHotkeyKey.q.rawValue
        )

        XCTAssertEqual(configuration.primaryModifier, .command)
        XCTAssertEqual(configuration.mainKey, .tab)
        XCTAssertEqual(configuration.quitKey, .q)
    }

    func testResolveFallsBackQuitKeyWhenQuitEqualsMainKey() {
        let configuration = SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: SwitcherPrimaryModifier.option.rawValue,
            mainKeyRaw: SwitcherHotkeyKey.q.rawValue,
            quitKeyRaw: SwitcherHotkeyKey.q.rawValue
        )

        XCTAssertEqual(configuration.mainKey, .q)
        XCTAssertEqual(configuration.quitKey, .w)
    }

    func testLoadPersistsNormalizedHotkeyValues() {
        let suiteName = "FlowTabTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated user defaults suite")
            return
        }

        userDefaults.set(
            SwitcherPrimaryModifier.command.rawValue,
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier
        )
        userDefaults.set(
            SwitcherHotkeyKey.tab.rawValue,
            forKey: AppPreferenceKeys.hotkeyMainKey
        )
        userDefaults.set(
            SwitcherHotkeyKey.tab.rawValue,
            forKey: AppPreferenceKeys.hotkeyQuitKey
        )

        let configuration = SwitcherHotkeyPreferencesStore.load(userDefaults: userDefaults)

        XCTAssertEqual(configuration.primaryModifier, .command)
        XCTAssertEqual(configuration.mainKey, .tab)
        XCTAssertEqual(configuration.quitKey, .q)
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.hotkeyPrimaryModifier),
            SwitcherPrimaryModifier.command.rawValue
        )
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.hotkeyMainKey),
            SwitcherHotkeyKey.tab.rawValue
        )
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.hotkeyQuitKey),
            SwitcherHotkeyKey.q.rawValue
        )

        userDefaults.removePersistentDomain(forName: suiteName)
    }

    func testResolveFallsBackToDefaultValuesForInvalidHotkeyRawInputs() {
        let configuration = SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: "invalid-modifier",
            mainKeyRaw: "invalid-main",
            quitKeyRaw: "invalid-quit"
        )

        XCTAssertEqual(configuration.primaryModifier, SwitcherHotkeyPreferencesStore.defaultPrimaryModifier)
        XCTAssertEqual(configuration.mainKey, SwitcherHotkeyPreferencesStore.defaultMainKey)
        XCTAssertEqual(configuration.quitKey, SwitcherHotkeyPreferencesStore.defaultQuitKey)
    }

    func testRuntimeActivatorOpenConfigurationActivatesTargetApp() {
        let configuration = RuntimeActivator.makeOpenConfiguration()

        XCTAssertTrue(configuration.activates)
    }

    func testRuntimeActivatorOpenConfigurationReusesRunningAppInstance() {
        let configuration = RuntimeActivator.makeOpenConfiguration()

        XCTAssertFalse(configuration.createsNewApplicationInstance)
    }

    func testHotkeyConfigurationDerivedFieldsAreConsistent() {
        let configuration = SwitcherHotkeyConfiguration(
            primaryModifier: .command,
            mainKey: .space,
            quitKey: .w
        )

        XCTAssertEqual(configuration.forwardKeyCode, UInt32(SwitcherHotkeyKey.space.keyCode))
        XCTAssertEqual(configuration.forwardModifiers, UInt32(cmdKey))
        XCTAssertEqual(configuration.backwardModifiers, UInt32(cmdKey) | UInt32(shiftKey))
        XCTAssertEqual(configuration.quitKeyCode, SwitcherHotkeyKey.w.keyCode)
        XCTAssertEqual(configuration.mainShortcutText, "Command + Space")
        XCTAssertEqual(configuration.backwardShortcutText, "Command + Shift + Space")
        XCTAssertEqual(configuration.quitShortcutText, "Command + W")
    }

    func testSwitcherPanelWindowConfigurationSupportsFullscreenSpaces() {
        let behavior = SwitcherPanelWindowConfiguration.collectionBehavior
        let styleMask = SwitcherPanelWindowConfiguration.styleMask

        XCTAssertEqual(SwitcherPanelWindowConfiguration.level, .statusBar)
        XCTAssertTrue(styleMask.contains(.borderless))
        XCTAssertTrue(styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behavior.contains(.ignoresCycle))
        XCTAssertTrue(behavior.contains(.stationary))
        XCTAssertTrue(behavior.contains(.canJoinAllApplications))
        XCTAssertFalse(behavior.contains(.moveToActiveSpace))
        XCTAssertFalse(behavior.contains(.transient))
    }

    func testSwitcherPanelWindowConfigurationElevatesLevelForFullscreenPresentation() {
        let normalLevel = SwitcherPanelWindowConfiguration.presentationLevel(
            frontmostWindowIsFullScreen: false
        )
        let fullScreenLevel = SwitcherPanelWindowConfiguration.presentationLevel(
            frontmostWindowIsFullScreen: true
        )

        XCTAssertEqual(normalLevel, .statusBar)
        XCTAssertGreaterThan(fullScreenLevel.rawValue, normalLevel.rawValue)
    }

    func testSwitcherPanelWindowConfigurationElevatesLevelWhenFullscreenDetectionFallsBack() {
        let fallbackLevel = SwitcherPanelWindowConfiguration.presentationLevel(
            frontmostWindowIsFullScreen: false,
            requiresFallbackElevation: true
        )

        XCTAssertEqual(SwitcherPanelWindowConfiguration.level, .statusBar)
        XCTAssertGreaterThan(
            fallbackLevel.rawValue,
            SwitcherPanelWindowConfiguration.level.rawValue
        )
    }

    func testSwitcherPanelWindowConfigurationAddsMoveToActiveSpaceOnlyForRecovery() {
        let defaultBehavior = SwitcherPanelWindowConfiguration.presentationCollectionBehavior()
        let recoveryBehavior = SwitcherPanelWindowConfiguration.presentationCollectionBehavior(
            requiresActiveSpaceMove: true
        )

        XCTAssertFalse(defaultBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(recoveryBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(recoveryBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(recoveryBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(recoveryBehavior.contains(.stationary))
        XCTAssertTrue(recoveryBehavior.contains(.canJoinAllApplications))
        XCTAssertFalse(recoveryBehavior.contains(.transient))
    }

    func testSwitcherPanelWindowConfigurationUsesNonActivatingBorderlessPanelStyle() {
        let styleMask = SwitcherPanelWindowConfiguration.styleMask

        XCTAssertTrue(styleMask.contains(.borderless))
        XCTAssertTrue(styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(styleMask.contains(.titled))
        XCTAssertFalse(styleMask.contains(.resizable))
    }

    @MainActor
    func testSearchSystemTextInputBridgeConfiguresVisiblePlainTextResponder() {
        let harness = SearchSystemTextInputBridgeTestHarness()
        let textView = harness.textView
        let scrollView = harness.enclosingScrollView

        XCTAssertEqual(harness.containerAccessibilityIdentifier, "flowtab.switcher.search.input")
        XCTAssertNotNil(scrollView)
        XCTAssertEqual(scrollView?.drawsBackground, false)
        XCTAssertEqual(scrollView?.hasHorizontalScroller, false)
        XCTAssertEqual(scrollView?.hasVerticalScroller, false)
        XCTAssertTrue(textView.acceptsFirstResponder)
        XCTAssertFalse(textView.drawsBackground)
        XCTAssertEqual(textView.backgroundColor, .clear)
        XCTAssertEqual(textView.textColor, .labelColor)
        XCTAssertEqual(textView.insertionPointColor, .controlAccentColor)
        XCTAssertTrue(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertFalse(textView.isRichText)
        XCTAssertFalse(textView.importsGraphics)
        XCTAssertFalse(textView.allowsUndo)
        XCTAssertFalse(textView.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticDataDetectionEnabled)
        XCTAssertFalse(textView.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticLinkDetectionEnabled)
        XCTAssertFalse(textView.isAutomaticSpellingCorrectionEnabled)
        XCTAssertFalse(textView.isAutomaticTextReplacementEnabled)
        XCTAssertFalse(textView.isContinuousSpellCheckingEnabled)
        XCTAssertFalse(textView.isGrammarCheckingEnabled)
        XCTAssertEqual(textView.textContainerInset, .zero)
        XCTAssertTrue(textView.isHorizontallyResizable)
        XCTAssertFalse(textView.isVerticallyResizable)
        XCTAssertEqual(textView.textContainer?.lineFragmentPadding, 0)
        XCTAssertEqual(textView.textContainer?.maximumNumberOfLines, 1)
        XCTAssertEqual(textView.textContainer?.lineBreakMode, .byClipping)
        XCTAssertEqual(textView.textContainer?.widthTracksTextView, false)
        XCTAssertEqual(textView.textContainer?.heightTracksTextView, true)
    }

    @MainActor
    func testSearchSystemTextInputBridgeSynchronizeClampsQueryAndCursor() {
        let harness = SearchSystemTextInputBridgeTestHarness()

        harness.synchronize(query: "wechat", cursorPosition: 99, showsInsertionPoint: true)

        XCTAssertEqual(harness.textView.string, "wechat")
        XCTAssertEqual(harness.textView.selectedRange(), NSRange(location: 6, length: 0))
        XCTAssertEqual(harness.textView.insertionPointColor, .controlAccentColor)
        XCTAssertTrue(harness.inputChanges.isEmpty)
        XCTAssertGreaterThanOrEqual(harness.markedTextChanges.count, 1)
        XCTAssertEqual(harness.markedTextChanges.last, false)

        harness.synchronize(query: "wechat", cursorPosition: -4, showsInsertionPoint: false)

        XCTAssertEqual(harness.textView.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertEqual(harness.textView.insertionPointColor, .clear)
        XCTAssertEqual(harness.markedTextChanges.last, false)
    }

    @MainActor
    func testSearchSystemTextInputBridgePublishesQueryAndCursorFromTextInput() {
        let harness = SearchSystemTextInputBridgeTestHarness()
        harness.synchronize(query: "abc", cursorPosition: 3)
        harness.resetRecordedChanges()

        harness.textView.insertText("d", replacementRange: NSRange(location: 3, length: 0))
        harness.notifyTextDidChange()

        XCTAssertEqual(
            harness.inputChanges.last,
            SearchSystemTextInputBridgeTestHarness.InputChange(
                query: "abcd",
                cursorPosition: 4
            )
        )
        XCTAssertEqual(harness.markedTextChanges.last, false)

        harness.textView.setSelectedRange(NSRange(location: 2, length: 0))
        harness.notifySelectionDidChange()

        XCTAssertEqual(
            harness.inputChanges.last,
            SearchSystemTextInputBridgeTestHarness.InputChange(
                query: "abcd",
                cursorPosition: 2
            )
        )
    }

    @MainActor
    func testSearchSystemTextInputBridgePreservesSelectAllAndDoesNotPublishCollapsedCursor() {
        let harness = SearchSystemTextInputBridgeTestHarness()
        harness.synchronize(query: "abcdef", cursorPosition: 6)
        harness.resetRecordedChanges()

        harness.textView.setSelectedRange(NSRange(location: 0, length: 6))
        harness.notifySelectionDidChange()

        XCTAssertTrue(harness.inputChanges.isEmpty)
        XCTAssertEqual(harness.textView.selectedRange(), NSRange(location: 0, length: 6))

        harness.synchronize(query: "abcdef", cursorPosition: 6)

        XCTAssertEqual(harness.textView.selectedRange(), NSRange(location: 0, length: 6))
    }

    @MainActor
    func testSearchSystemTextInputBridgeTracksMarkedTextCompositionLifecycle() {
        let harness = SearchSystemTextInputBridgeTestHarness()
        harness.resetRecordedChanges()

        harness.textView.setMarkedText(
            "ni",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        harness.notifyTextDidChange()

        XCTAssertTrue(harness.textView.hasMarkedText())
        XCTAssertEqual(harness.inputChanges.last?.query, "ni")
        XCTAssertEqual(harness.markedTextChanges.last, true)

        harness.textView.unmarkText()
        harness.notifyTextDidChange()

        XCTAssertFalse(harness.textView.hasMarkedText())
        XCTAssertEqual(harness.inputChanges.last?.query, "ni")
        XCTAssertEqual(harness.markedTextChanges.last, false)
    }

    @MainActor
    func testSearchSystemTextInputBridgeDetachClearsMarkedStateAndIgnoresUntrackedViews() {
        let harness = SearchSystemTextInputBridgeTestHarness()
        let untrackedTextView = NSTextView()

        untrackedTextView.string = "ignored"
        untrackedTextView.setSelectedRange(NSRange(location: 7, length: 0))
        harness.notifyTextDidChange(for: untrackedTextView)
        harness.notifySelectionDidChange(for: untrackedTextView)

        XCTAssertTrue(harness.inputChanges.isEmpty)
        XCTAssertTrue(harness.markedTextChanges.isEmpty)

        harness.detachTrackedTextView()

        XCTAssertEqual(harness.markedTextChanges, [false])
    }

    @MainActor
    func testTerminateSelectedAppBehaviorKeepsAppUntilProcessActuallyExits() async {
        let model = LiveSwitcherModel()
        let initialApps = terminateScenarioApps()
        var snapshots: [RuntimeSnapshot] = [makeRuntimeSnapshot(apps: initialApps)]
        var snapshotReadCount = 0
        model.snapshotProviderOverride = {
            snapshotReadCount += 1
            XCTAssertFalse(snapshots.isEmpty)
            return snapshots.removeFirst()
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        guard let terminatedAppID = model.session?.selectedApp.id else {
            XCTFail("Expected an active session before terminate flow")
            return
        }

        let appsAfterTermination = initialApps.filter { $0.id != terminatedAppID }
        snapshots.append(makeRuntimeSnapshot(apps: appsAfterTermination))

        model.terminateRequestOverride = { _ in (sent: true, pid: 42_000) }
        model.terminateRefreshPollIntervalNs = 2_000_000
        model.terminateRefreshTimeoutNs = 100_000_000

        var processCheckCount = 0
        model.isProcessRunningOverride = { _ in
            processCheckCount += 1
            return processCheckCount < 2
        }

        let layoutRefreshed = expectation(description: "post terminate layout refreshed")
        model.onSessionLayoutChanged = { layoutRefreshed.fulfill() }

        let result = model.terminateSelectedApp()
        XCTAssertEqual(result, .updatedSession)
        XCTAssertEqual(snapshotReadCount, 1)
        XCTAssertEqual(model.appCount, initialApps.count)
        XCTAssertTrue(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? false)
        XCTAssertEqual(model.terminatingAppID, terminatedAppID)

        await fulfillment(of: [layoutRefreshed], timeout: 1.0)
        XCTAssertEqual(snapshotReadCount, 2)
        XCTAssertGreaterThanOrEqual(processCheckCount, 2)
        XCTAssertEqual(model.appCount, appsAfterTermination.count)
        XCTAssertFalse(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? true)
        XCTAssertNil(model.terminatingAppID)
        model.cancelSelection()
    }

    @MainActor
    func testTerminateSelectedAppUnitStopsPollingAfterTimeoutWhenAppStillRunning() async {
        let model = LiveSwitcherModel()
        let initialApps = terminateScenarioApps()
        var snapshots: [RuntimeSnapshot] = [makeRuntimeSnapshot(apps: initialApps)]
        var snapshotReadCount = 0
        model.snapshotProviderOverride = {
            snapshotReadCount += 1
            XCTAssertFalse(snapshots.isEmpty)
            return snapshots.removeFirst()
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        guard let terminatedAppID = model.session?.selectedApp.id else {
            XCTFail("Expected an active session before terminate flow")
            return
        }

        model.terminateRequestOverride = { _ in (sent: true, pid: 42_001) }
        model.terminateRefreshPollIntervalNs = 2_000_000
        model.terminateRefreshTimeoutNs = 12_000_000
        var processCheckCount = 0
        model.isProcessRunningOverride = { _ in
            processCheckCount += 1
            return true
        }

        let noDeferredLayoutRefresh = expectation(description: "no deferred layout refresh")
        noDeferredLayoutRefresh.isInverted = true
        model.onSessionLayoutChanged = { noDeferredLayoutRefresh.fulfill() }

        let result = model.terminateSelectedApp()
        XCTAssertEqual(result, .updatedSession)
        XCTAssertEqual(snapshotReadCount, 1)
        XCTAssertEqual(model.appCount, initialApps.count)
        XCTAssertTrue(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? false)
        XCTAssertEqual(model.terminatingAppID, terminatedAppID)

        await fulfillment(of: [noDeferredLayoutRefresh], timeout: 0.08)
        XCTAssertGreaterThan(processCheckCount, 0)
        XCTAssertEqual(snapshotReadCount, 1)
        XCTAssertEqual(model.appCount, initialApps.count)
        XCTAssertTrue(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? false)
        XCTAssertNil(model.terminatingAppID)
        model.cancelSelection()
    }

    @MainActor
    func testTerminateSelectedAppUnitRefreshesOnWorkspaceTerminateAfterPollingTimeout() async {
        let model = LiveSwitcherModel()
        let initialApps = terminateScenarioApps()
        var snapshots: [RuntimeSnapshot] = [makeRuntimeSnapshot(apps: initialApps)]
        var snapshotReadCount = 0
        model.snapshotProviderOverride = {
            snapshotReadCount += 1
            XCTAssertFalse(snapshots.isEmpty)
            return snapshots.removeFirst()
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        guard let terminatedAppID = model.session?.selectedApp.id else {
            XCTFail("Expected an active session before terminate flow")
            return
        }

        let appsAfterTermination = initialApps.filter { $0.id != terminatedAppID }
        snapshots.append(makeRuntimeSnapshot(apps: appsAfterTermination))

        model.terminateRequestOverride = { _ in (sent: true, pid: 42_002) }
        model.terminateRefreshPollIntervalNs = 2_000_000
        model.terminateRefreshTimeoutNs = 12_000_000

        var processCheckCount = 0
        model.isProcessRunningOverride = { _ in
            processCheckCount += 1
            return true
        }

        let deferredLayoutRefresh = expectation(description: "deferred layout refresh")
        var layoutRefreshCount = 0
        model.onSessionLayoutChanged = {
            layoutRefreshCount += 1
            deferredLayoutRefresh.fulfill()
        }

        let result = model.terminateSelectedApp()
        XCTAssertEqual(result, .updatedSession)
        XCTAssertEqual(snapshotReadCount, 1)
        XCTAssertEqual(model.appCount, initialApps.count)
        XCTAssertTrue(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? false)

        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertGreaterThan(processCheckCount, 0)
        XCTAssertEqual(layoutRefreshCount, 0)
        XCTAssertEqual(snapshotReadCount, 1)
        XCTAssertNil(model.terminatingAppID)

        model.handleApplicationTerminated(appID: terminatedAppID, pid: 42_002)

        await fulfillment(of: [deferredLayoutRefresh], timeout: 1.0)
        XCTAssertEqual(layoutRefreshCount, 1)
        XCTAssertEqual(snapshotReadCount, 2)
        XCTAssertEqual(model.appCount, appsAfterTermination.count)
        XCTAssertFalse(model.session?.apps.contains(where: { $0.id == terminatedAppID }) ?? true)
        model.cancelSelection()
    }

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
        XCTAssertEqual(AppStrings.text(.tabSettings, language: .english), "Settings")
    }

    func testPermissionSettingsCardStateUsesDeniedCopyWhenPermissionsMissing() {
        let state = PermissionSettingsCardState(
            showPermissionReminder: true,
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
            accessibilityTrusted: true,
            screenCaptureTrusted: true
        )

        XCTAssertEqual(state.accessibilityStatusText, AppStrings.text(.permissionAccessibilityGranted))
        XCTAssertEqual(state.accessibilityButtonTitle, AppStrings.text(.permissionAccessibilityClose))
        XCTAssertEqual(state.screenCaptureStatusText, AppStrings.text(.permissionScreenGranted))
        XCTAssertEqual(state.screenCaptureButtonTitle, AppStrings.text(.permissionScreenClose))
    }

    func testRuntimeLogLevelOrderingUsesPriority() {
        XCTAssertLessThan(RuntimeLogLevel.debug, .info)
        XCTAssertLessThan(RuntimeLogLevel.info, .warning)
        XCTAssertLessThan(RuntimeLogLevel.warning, .error)
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
        RuntimeLog.info("InputTrace", "\(marker)-info")
        RuntimeLog.warning("InputTrace", "\(marker)-warning")

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 50, minimumLevel: .debug)
        let scopedLines = lines.filter { $0.contains(marker) }

        XCTAssertFalse(scopedLines.contains(where: { $0.contains("\(marker)-info") }))
        XCTAssertTrue(scopedLines.contains(where: { $0.contains("\(marker)-warning") }))
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
        RuntimeLog.info("UnitTest", "\(marker)-info")

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 50, minimumLevel: .debug)
        let scopedLines = lines.filter { $0.contains(marker) }

        XCTAssertTrue(scopedLines.contains(where: { $0.contains("\(marker)-info") }))
    }

    func testSearchMatchesAppByPartialName() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("fari"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["Safari"])
    }

    func testSearchMatchesCamelCaseAppBySegmentedWords() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("flow search"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["FlowTabSearch"])
    }

    func testSearchQuerySupportsMiddleInsertionViaCursorMovement() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryTextWithoutRebuild("abcd"))
        XCTAssertTrue(coordinator.moveQueryCursor(by: -1))
        XCTAssertTrue(coordinator.appendQueryTextWithoutRebuild("e"))

        XCTAssertEqual(coordinator.state.query, "abced")
        XCTAssertEqual(coordinator.state.queryCursorPosition, 4)
    }

    func testSearchDeleteBackwardRespectsCursorPosition() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryTextWithoutRebuild("abced"))
        XCTAssertTrue(coordinator.moveQueryCursor(by: -2))
        XCTAssertTrue(coordinator.deleteBackwardInQueryWithoutRebuild())

        XCTAssertEqual(coordinator.state.query, "abed")
        XCTAssertEqual(coordinator.state.queryCursorPosition, 2)
    }

    func testSearchAppendWhileResultsFocusedUsesQueryTail() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryTextWithoutRebuild("abcd"))
        XCTAssertTrue(coordinator.moveQueryCursor(by: -2))
        XCTAssertTrue(coordinator.focusResults())
        XCTAssertTrue(coordinator.appendQueryTextWithoutRebuild("e"))

        XCTAssertEqual(coordinator.state.query, "abcde")
        XCTAssertEqual(coordinator.state.queryCursorPosition, 5)
    }

    func testSearchDeleteWhileResultsFocusedUsesQueryTail() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryTextWithoutRebuild("abcd"))
        XCTAssertTrue(coordinator.moveQueryCursor(by: -2))
        XCTAssertTrue(coordinator.focusResults())
        XCTAssertTrue(coordinator.deleteBackwardInQueryWithoutRebuild())

        XCTAssertEqual(coordinator.state.query, "abc")
        XCTAssertEqual(coordinator.state.queryCursorPosition, 3)
    }

    func testSearchReplaceQueryWithoutRebuildUpdatesQueryAndCursor() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.replaceQueryWithoutRebuild("微信", cursorPosition: 1))

        XCTAssertEqual(coordinator.state.query, "微信")
        XCTAssertEqual(coordinator.state.queryCursorPosition, 1)
    }

    func testSearchMatchesChineseAppByPinyinInitialsAndFullSpelling() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("wx"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["微信"])

        _ = coordinator.handleEscape()
        XCTAssertTrue(coordinator.appendQueryText("weixin"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["微信"])
    }

    func testSearchMatchesChineseCompoundAppBySegmentedQueryWithoutSpaces() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("文件助手"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["文件传输助手"])
    }

    func testSearchMatchesEnglishAbbreviation() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("vsc"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["Visual Studio Code"])
    }

    func testSearchMatchesByBundleIDButNotGenericComPrefix() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("wechat"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["微信"])

        _ = coordinator.handleEscape()
        XCTAssertTrue(coordinator.appendQueryText("com"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertTrue(coordinator.state.results.isEmpty)
    }

    func testSearchLocksChineseTestAppByPinyinInitials() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("c"))
        XCTAssertTrue(coordinator.appendQueryText("s"))
        drainPendingSearchRebuild(on: coordinator)

        XCTAssertEqual(coordinator.state.results.first?.primaryText, "测试")
        XCTAssertEqual(coordinator.state.selectedResult?.primaryText, "测试")
        XCTAssertEqual(coordinator.state.selectedResult?.kind, .app(appID: "com.xxx.test"))
    }

    func testSearchLocksChineseTestAppByBundleIDPrefixes() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        let expectedKind = SwitcherSearchResultKind.app(appID: "com.xxx.test")
        XCTAssertTrue(coordinator.appendQueryText("t"))
        drainPendingSearchRebuild(on: coordinator)
        let firstStepResults = Set(coordinator.state.results.map(\.primaryText))
        XCTAssertTrue(firstStepResults.contains("FlowTabSearch"), "Query \(coordinator.state.query)")
        XCTAssertTrue(firstStepResults.contains("测试"), "Query \(coordinator.state.query)")

        for suffix in ["e", "s", "t"] {
            XCTAssertTrue(coordinator.appendQueryText(suffix))
            drainPendingSearchRebuild(on: coordinator)
            XCTAssertEqual(coordinator.state.results.first?.primaryText, "测试", "Query \(coordinator.state.query)")
            XCTAssertEqual(coordinator.state.selectedResult?.primaryText, "测试", "Query \(coordinator.state.query)")
            XCTAssertEqual(coordinator.state.selectedResult?.kind, expectedKind, "Query \(coordinator.state.query)")
        }
    }

    func testSearchQueryCsMatchesBothCSGOAndChineseTestApp() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleAppsForSharedCSQuery())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("c"))
        XCTAssertTrue(coordinator.appendQueryText("s"))
        drainPendingSearchRebuild(on: coordinator)

        XCTAssertEqual(
            Set(coordinator.state.results.map(\.primaryText)),
            Set(["CSGO", "测试"])
        )
    }

    func testSearchRecoversResultsWhenIncrementalCandidateCacheMisses() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchCacheMissSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .app))

        XCTAssertTrue(coordinator.appendQueryText("t"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.primaryText), ["Tool"])

        XCTAssertTrue(coordinator.appendQueryText("e"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertTrue(
            coordinator.state.results.map(\.primaryText).contains("终端"),
            "Expected te to recover 终端 via full-scan fallback, got \(coordinator.state.results.map(\.primaryText))"
        )
    }

    func testWindowSearchCanMatchByAppNamePinyinInitials() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .window))

        XCTAssertTrue(coordinator.appendQueryText("wx"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(coordinator.state.results.map(\.secondaryText), ["微信", "微信"])
    }

    func testWindowSearchMatchesCamelCaseTitleBySegmentedWords() {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: searchSampleApps())
        XCTAssertTrue(coordinator.activate(defaultScope: .window))

        XCTAssertTrue(coordinator.appendQueryText("search coordinator"))
        drainPendingSearchRebuild(on: coordinator)
        XCTAssertEqual(
            coordinator.state.results.map(\.primaryText),
            ["FlowTab - SwitcherSearchCoordinator.swift"]
        )
    }

    func testSearchPerformanceWindowScope() {
        let apps = makeBenchmarkApps(appCount: 400, windowsPerApp: 25)
        let queries = benchmarkQueries()

        let buildNanos = measureNanos {
            let coordinator = SwitcherSearchCoordinator()
            coordinator.rebuildIndex(with: apps)
            _ = coordinator.activate(defaultScope: .window)
        }

        let rounds = 3
        let queryNanos = measureNanos {
            let coordinator = SwitcherSearchCoordinator()
            coordinator.rebuildIndex(with: apps)
            _ = coordinator.activate(defaultScope: .window)
            runBaselineQueries(queries, on: coordinator, rounds: rounds)
        }
        let buildMs = nanosToMilliseconds(buildNanos)
        let queryMs = nanosToMilliseconds(queryNanos)
        let queryCount = queries.count * rounds
        let qps = Double(queryCount) / max(0.001, queryMs / 1000.0)

        print(
            String(
                format: "[SearchPerformanceWindowScope] dataset=%d apps / %d windows, rounds=%d, build=%.2fms, query=%.2fms, queries=%d, throughput=%.2f qps",
                apps.count,
                apps.reduce(0) { $0 + $1.windows.count },
                rounds,
                buildMs,
                queryMs,
                queryCount,
                qps
            )
        )

        let probe = runBaselineProbe(query: "weixin", apps: apps, scope: .window)
        XCTAssertFalse(probe.isEmpty)
    }

    func testSearchPressureWindowScopeUnified() {
        let apps = makeBenchmarkApps(appCount: 400, windowsPerApp: 25)
        let queries = benchmarkQueries()
        let rounds = 3

        let buildNanos = measureNanos {
            let coordinator = SwitcherSearchCoordinator()
            coordinator.rebuildIndex(with: apps)
        }

        let queryNanos = measureNanos {
            let coordinator = SwitcherSearchCoordinator()
            coordinator.rebuildIndex(with: apps)
            _ = coordinator.activate(defaultScope: .window)
            runBaselineQueries(queries, on: coordinator, rounds: rounds)
        }

        let buildMs = nanosToMilliseconds(buildNanos)
        let queryMs = nanosToMilliseconds(queryNanos)
        let queryCount = queries.count * rounds
        let qps = Double(queryCount) / max(0.001, queryMs / 1000.0)

        print(
            String(
                format: "[SearchPressureUnified] dataset=%d apps / %d windows, rounds=%d, build=%.2fms, query=%.2fms, queries=%d, throughput=%.2f qps",
                apps.count,
                apps.reduce(0) { $0 + $1.windows.count },
                rounds,
                buildMs,
                queryMs,
                queryCount,
                qps
            )
        )

        let probe = runBaselineProbe(query: "weixin", apps: apps, scope: .window)
        XCTAssertFalse(probe.isEmpty)
    }

    func testSearchPressureWindowScopeSegmentedQueries() {
        let apps = makeBenchmarkApps(appCount: 400, windowsPerApp: 25)
        let queries = segmentedBenchmarkQueries()
        let rounds = 3

        let buildNanos = measureNanos {
            let coordinator = SwitcherSearchCoordinator()
            coordinator.rebuildIndex(with: apps)
        }

        let queryNanos = measureNanos {
            let coordinator = SwitcherSearchCoordinator()
            coordinator.rebuildIndex(with: apps)
            _ = coordinator.activate(defaultScope: .window)
            runBaselineQueries(queries, on: coordinator, rounds: rounds)
        }

        let buildMs = nanosToMilliseconds(buildNanos)
        let queryMs = nanosToMilliseconds(queryNanos)
        let queryCount = queries.count * rounds
        let qps = Double(queryCount) / max(0.001, queryMs / 1000.0)

        print(
            String(
                format: "[SearchPressureSegmented] dataset=%d apps / %d windows, rounds=%d, build=%.2fms, query=%.2fms, queries=%d, throughput=%.2f qps",
                apps.count,
                apps.reduce(0) { $0 + $1.windows.count },
                rounds,
                buildMs,
                queryMs,
                queryCount,
                qps
            )
        )

        XCTAssertFalse(runBaselineProbe(query: "flow search", apps: apps, scope: .window).isEmpty)
        XCTAssertFalse(runBaselineProbe(query: "文件助手", apps: apps, scope: .window).isEmpty)
    }

    private func searchSampleApps() -> [AppSwitchCandidate] {
        [
            AppSwitchCandidate(
                id: "com.tencent.xinWeChat",
                displayName: "微信",
                groupID: "social",
                lastActiveAt: 310,
                windows: [
                    WindowCandidate(id: "wechat-1", title: "工作群", isMinimized: false, lastActiveAt: 310),
                    WindowCandidate(id: "wechat-2", title: "文件传输助手", isMinimized: false, lastActiveAt: 280)
                ]
            ),
            AppSwitchCandidate(
                id: "com.microsoft.VSCode",
                displayName: "Visual Studio Code",
                groupID: "dev",
                lastActiveAt: 300,
                windows: [
                    WindowCandidate(
                        id: "vscode-1",
                        title: "FlowTab - SwitcherSearchCoordinator.swift",
                        isMinimized: false,
                        lastActiveAt: 300
                    )
                ]
            ),
            AppSwitchCandidate(
                id: "com.apple.Safari",
                displayName: "Safari",
                groupID: "web",
                lastActiveAt: 200,
                windows: [
                    WindowCandidate(id: "safari-1", title: "Apple", isMinimized: false, lastActiveAt: 200)
                ]
            ),
            AppSwitchCandidate(
                id: "com.xxx.test",
                displayName: "测试",
                groupID: "qa",
                lastActiveAt: 190,
                windows: [
                    WindowCandidate(id: "test-1", title: "用例", isMinimized: false, lastActiveAt: 190)
                ]
            ),
            AppSwitchCandidate(
                id: "com.flowtab.search",
                displayName: "FlowTabSearch",
                groupID: "dev",
                lastActiveAt: 180,
                windows: [
                    WindowCandidate(
                        id: "flow-search-1",
                        title: "FlowTabSearchGuide",
                        isMinimized: false,
                        lastActiveAt: 180
                    )
                ]
            ),
            AppSwitchCandidate(
                id: "com.flowtab.file-transfer-assistant",
                displayName: "文件传输助手",
                groupID: "tools",
                lastActiveAt: 170,
                windows: [
                    WindowCandidate(
                        id: "file-transfer-1",
                        title: "最近文件",
                        isMinimized: false,
                        lastActiveAt: 170
                    )
                ]
            )
        ]
    }

    private func searchSampleAppsForSharedCSQuery() -> [AppSwitchCandidate] {
        [
            AppSwitchCandidate(
                id: "com.xxx.csgo",
                displayName: "CSGO",
                groupID: "games",
                lastActiveAt: 200,
                windows: [
                    WindowCandidate(id: "csgo-1", title: "Dust2", isMinimized: false, lastActiveAt: 200)
                ]
            ),
            AppSwitchCandidate(
                id: "com.xxx.test",
                displayName: "测试",
                groupID: "qa",
                lastActiveAt: 190,
                windows: [
                    WindowCandidate(id: "test-1", title: "用例", isMinimized: false, lastActiveAt: 190)
                ]
            ),
            AppSwitchCandidate(
                id: "com.apple.Safari",
                displayName: "Safari",
                groupID: "web",
                lastActiveAt: 180,
                windows: [
                    WindowCandidate(id: "safari-1", title: "Apple", isMinimized: false, lastActiveAt: 180)
                ]
            )
        ]
    }

    private func terminateScenarioApps() -> [AppSwitchCandidate] {
        [
            AppSwitchCandidate(
                id: "com.example.mail",
                displayName: "Mail",
                groupID: "office",
                lastActiveAt: 300,
                windows: [
                    WindowCandidate(id: "mail-1", title: "Inbox", isMinimized: false, lastActiveAt: 300)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.code",
                displayName: "Code",
                groupID: "dev",
                lastActiveAt: 290,
                windows: [
                    WindowCandidate(id: "code-1", title: "FlowTab", isMinimized: false, lastActiveAt: 290)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.browser",
                displayName: "Browser",
                groupID: "web",
                lastActiveAt: 280,
                windows: [
                    WindowCandidate(id: "browser-1", title: "Docs", isMinimized: false, lastActiveAt: 280)
                ]
            )
        ]
    }

    private func makeRuntimeSnapshot(apps: [AppSwitchCandidate]) -> RuntimeSnapshot {
        RuntimeSnapshot(apps: apps, contextsByID: [:])
    }

    private func makeBenchmarkApps(appCount: Int, windowsPerApp: Int) -> [AppSwitchCandidate] {
        precondition(appCount > 0)
        precondition(windowsPerApp > 0)

        let windowTopics = ["dashboard", "meeting", "design", "review", "bugfix", "roadmap", "notes"]
        var apps: [AppSwitchCandidate] = []
        apps.reserveCapacity(appCount)

        for appIndex in 0..<appCount {
            let app: (name: String, bundleID: String, windowBaseTitle: String?)
            switch appIndex % 7 {
            case 0:
                app = ("微信\(appIndex)", "com.tencent.xinWeChat\(appIndex)", nil)
            case 1:
                app = ("Visual Studio Code \(appIndex)", "com.microsoft.VSCode\(appIndex)", nil)
            case 2:
                app = ("Safari \(appIndex)", "com.apple.Safari\(appIndex)", nil)
            case 3:
                app = ("Chrome \(appIndex)", "com.google.Chrome\(appIndex)", nil)
            case 4:
                app = (
                    "FlowTabSearch\(appIndex)",
                    "com.flowtab.search\(appIndex)",
                    "FlowTabSearchCoordinator"
                )
            case 5:
                app = (
                    "文件传输助手\(appIndex)",
                    "com.flowtab.fileTransferAssistant\(appIndex)",
                    "文件传输助手归档"
                )
            default:
                app = ("Notion \(appIndex)", "notion.id.\(appIndex)", nil)
            }

            var windows: [WindowCandidate] = []
            windows.reserveCapacity(windowsPerApp)
            for windowIndex in 0..<windowsPerApp {
                let topic = windowTopics[(appIndex + windowIndex) % windowTopics.count]
                let title: String
                if let windowBaseTitle = app.windowBaseTitle {
                    title = "\(windowBaseTitle)\(windowIndex) - \(topic)"
                } else {
                    title = "\(app.name) - \(topic) - w\(windowIndex)"
                }
                windows.append(
                    WindowCandidate(
                        id: "w-\(appIndex)-\(windowIndex)",
                        title: title,
                        isMinimized: false,
                        lastActiveAt: TimeInterval(appCount * windowsPerApp - appIndex * windowsPerApp - windowIndex)
                    )
                )
            }

            apps.append(
                AppSwitchCandidate(
                    id: app.bundleID,
                    displayName: app.name,
                    groupID: "bench-\(appIndex % 12)",
                    lastActiveAt: TimeInterval(appCount - appIndex),
                    windows: windows
                )
            )
        }
        return apps
    }

    private func benchmarkQueries() -> [String] {
        [
            "w", "wx", "we", "wei", "weix", "weixi", "weixin", "weixi", "wei", "we",
            "vs", "vsc", "vscode", "vscode 1", "vscode",
            "sa", "saf", "safa", "safari", "safari 2",
            "de", "des", "desi", "design", "design w2",
            "com", "tencent", "chrome", "road", "review",
            "flow", "flow search", "文件", "文件助手",
            "wx9", "wx", "not", "notion", "meeting",
            "bug", "bugf", "bugfix", "notes", ""
        ]
    }

    private func segmentedBenchmarkQueries() -> [String] {
        [
            "f", "fl", "flow", "flow ", "flow s", "flow se", "flow search",
            "flow sea", "flow", "flow search",
            "文", "文件", "文件助", "文件助手", "文件 助手",
            "文件助", "文件", "",
            "search", "search coor", "search coordinator", ""
        ]
    }

    private func searchCacheMissSampleApps() -> [AppSwitchCandidate] {
        var apps: [AppSwitchCandidate] = []
        apps.reserveCapacity(1_105)
        apps.append(
            AppSwitchCandidate(
                id: "com.sample.tool",
                displayName: "Tool",
                groupID: "cache-miss",
                lastActiveAt: 2_000,
                windows: []
            )
        )

        for index in 1...1_103 {
            apps.append(
                AppSwitchCandidate(
                    id: "com.sample.app\(index)",
                    displayName: "应用\(index)",
                    groupID: "cache-miss",
                    lastActiveAt: TimeInterval(2_000 - index),
                    windows: []
                )
            )
        }

        apps.append(
            AppSwitchCandidate(
                id: "com.apple.Terminal",
                displayName: "终端",
                groupID: "cache-miss",
                lastActiveAt: 1,
                windows: []
            )
        )
        return apps
    }

    private func runBaselineQueries(
        _ queries: [String],
        on coordinator: SwitcherSearchCoordinator,
        rounds: Int
    ) {
        var currentQuery = ""
        for _ in 0..<rounds {
            for query in queries {
                let prefixLength = commonPrefixLength(currentQuery, query)
                let deletes = currentQuery.count - prefixLength
                if deletes > 0 {
                    for _ in 0..<deletes {
                        _ = coordinator.deleteBackwardInQuery()
                    }
                }

                let suffix = String(query.dropFirst(prefixLength))
                if !suffix.isEmpty {
                    _ = coordinator.appendQueryText(suffix)
                } else if query.isEmpty && !coordinator.state.query.isEmpty {
                    while coordinator.deleteBackwardInQuery() {}
                }
                drainPendingSearchRebuild(on: coordinator)

                currentQuery = query
            }
        }
    }

    private func runBaselineProbe(
        query: String,
        apps: [AppSwitchCandidate],
        scope: SwitcherSearchScope
    ) -> [String] {
        let coordinator = SwitcherSearchCoordinator()
        coordinator.rebuildIndex(with: apps)
        _ = coordinator.activate(defaultScope: scope)
        _ = coordinator.appendQueryText(query)
        drainPendingSearchRebuild(on: coordinator)
        return coordinator.state.results.prefix(10).map(\.id)
    }

    private func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        var count = 0
        for (left, right) in zip(lhs, rhs) {
            if left == right {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    private func measureNanos(_ block: () -> Void) -> UInt64 {
        let start = DispatchTime.now().uptimeNanoseconds
        block()
        return DispatchTime.now().uptimeNanoseconds - start
    }

    private func nanosToMilliseconds(_ nanos: UInt64) -> Double {
        Double(nanos) / 1_000_000.0
    }

    private func drainPendingSearchRebuild(on coordinator: SwitcherSearchCoordinator) {
        coordinator.flushPendingRebuild()
    }

    private func makeIsolatedUserDefaults() -> UserDefaults? {
        let suiteName = "FlowTabTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated user defaults suite")
            return nil
        }
        userDefaults.set(suiteName, forKey: "FlowTabTestsSuiteName")
        return userDefaults
    }

    private func clearIsolatedUserDefaults(_ userDefaults: UserDefaults) {
        guard let suiteName = userDefaults.string(forKey: "FlowTabTestsSuiteName") else { return }
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    private func restoreUserDefaultsValue(
        _ value: Any?,
        forKey key: String,
        userDefaults: UserDefaults
    ) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    private func resetRuntimeLogsForTest() async {
        RuntimeDiagnostics.shared.clear()
        _ = await RuntimeDiagnostics.shared.makeReadSnapshot()
    }
}

private final class TestAppWindow: AppWindowOpeningWindow {
    let isPanelWindow: Bool
    var isMiniaturized: Bool

    private(set) var deminiaturizeCallCount = 0
    private(set) var makeKeyAndOrderFrontCallCount = 0
    private(set) var orderFrontRegardlessCallCount = 0

    init(isPanelWindow: Bool, isMiniaturized: Bool) {
        self.isPanelWindow = isPanelWindow
        self.isMiniaturized = isMiniaturized
    }

    func deminiaturize(_ sender: Any?) {
        deminiaturizeCallCount += 1
        isMiniaturized = false
    }

    func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyAndOrderFrontCallCount += 1
    }

    func orderFrontRegardless() {
        orderFrontRegardlessCallCount += 1
    }
}

private final class TestAppWindowApplication: AppWindowOpeningApplication {
    var isHidden: Bool
    let appWindows: [any AppWindowOpeningWindow]

    private(set) var activateCallCount = 0
    private(set) var lastActivateIgnoringOtherApps: Bool?
    private(set) var unhideCallCount = 0
    private(set) var showSettingsWindowActionCount = 0

    init(isHidden: Bool, appWindows: [any AppWindowOpeningWindow]) {
        self.isHidden = isHidden
        self.appWindows = appWindows
    }

    func activate(ignoringOtherApps flag: Bool) {
        activateCallCount += 1
        lastActivateIgnoringOtherApps = flag
    }

    func unhide(_ sender: Any?) {
        unhideCallCount += 1
        isHidden = false
    }

    func sendShowSettingsWindowAction() -> Bool {
        showSettingsWindowActionCount += 1
        return true
    }
}
