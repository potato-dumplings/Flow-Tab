import AppKit
import FlowTabCore
import SwiftUI
import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testSettingsLanguageChangeRebuildsSettingsBridgeWithLocalizedText() async throws {
        let previousLanguageRaw = UserDefaults.standard.string(
            forKey: AppPreferenceKeys.appLanguage
        )
        let previousContext = FlowPresentationState.shared.context
        FlowPresentationState.shared.setAppLanguage(
            rawValue: AppLanguage.english.rawValue
        )
        defer {
            FlowPresentationState.shared.setAppLanguage(
                rawValue: previousContext.appLanguage.rawValue
            )
            restoreSettingsPresentationDefault(
                previousLanguageRaw,
                forKey: AppPreferenceKeys.appLanguage
            )
        }

        let recorder = SettingsPresentationUpdateRecorder()
        let hostedView = NSHostingView(
            rootView: SettingsPresentationObservedContent(
                content: AppSettingsView(isActive: true)
                    .frame(width: 1_440, height: 900, alignment: .topLeading),
                recorder: recorder
            )
        )
        hostedView.frame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        hostedView.layoutSubtreeIfNeeded()

        let baseline = try XCTUnwrap(recorder.latestEvidence)
        XCTAssertEqual(baseline.context.appLanguage, .english)
        let initialContainer = try singleSettingsPresentationContainer(
            in: hostedView
        )
        XCTAssertFalse(
            settingsPresentationTextValues(in: initialContainer.pageView)
                .contains("基础显示设置、快捷键与权限")
        )

        let update = await awaitSettingsPresentationUpdate(
            recorder: recorder,
            after: baseline.generation,
            description: "Settings language presentation update",
            trigger: {
                FlowPresentationState.shared.setAppLanguage(
                    rawValue: AppLanguage.simplifiedChinese.rawValue
                )
            },
            matches: { $0.context.appLanguage == .simplifiedChinese }
        )
        let evidence = try XCTUnwrap(update)

        hostedView.layoutSubtreeIfNeeded()
        let updatedContainer = try singleSettingsPresentationContainer(
            in: hostedView
        )
        XCTAssertEqual(evidence.context, FlowPresentationState.shared.context)
        XCTAssertTrue(
            settingsPresentationTextValues(in: updatedContainer.pageView)
                .contains("基础显示设置、快捷键与权限")
        )
    }

    @MainActor
    func testSettingsRootLanguageChangeRebuildsSettingsBridgeWithLocalizedText() async throws {
        let previousSelectedTab = HomeTabState.shared.selectedTab
        let previousLanguageRaw = UserDefaults.standard.string(
            forKey: AppPreferenceKeys.appLanguage
        )
        let previousThemeRaw = UserDefaults.standard.string(
            forKey: AppPreferenceKeys.themeMode
        )
        let previousContext = FlowPresentationState.shared.context
        HomeTabState.shared.selectedTab = .settings
        FlowPresentationState.shared.setAppLanguage(
            rawValue: AppLanguage.english.rawValue
        )
        FlowPresentationState.shared.setThemeMode(
            rawValue: ThemeMode.light.rawValue
        )
        defer {
            HomeTabState.shared.selectedTab = previousSelectedTab
            FlowPresentationState.shared.setAppLanguage(
                rawValue: previousContext.appLanguage.rawValue
            )
            FlowPresentationState.shared.setThemeMode(
                rawValue: previousContext.themeMode.rawValue
            )
            restoreSettingsPresentationDefault(
                previousLanguageRaw,
                forKey: AppPreferenceKeys.appLanguage
            )
            restoreSettingsPresentationDefault(
                previousThemeRaw,
                forKey: AppPreferenceKeys.themeMode
            )
        }

        let recorder = SettingsPresentationUpdateRecorder()
        let hostedView = NSHostingView(
            rootView: SettingsPresentationObservedContent(
                content: HomeRootView()
                    .frame(width: 1_440, height: 900, alignment: .topLeading),
                recorder: recorder
            )
        )
        hostedView.frame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        hostedView.layoutSubtreeIfNeeded()

        let baseline = try XCTUnwrap(recorder.latestEvidence)
        XCTAssertEqual(baseline.context.appLanguage, .english)
        _ = try singleSettingsPresentationContainer(in: hostedView)

        let update = await awaitSettingsPresentationUpdate(
            recorder: recorder,
            after: baseline.generation,
            description: "Settings root language presentation update",
            trigger: {
                FlowPresentationState.shared.setAppLanguage(
                    rawValue: AppLanguage.simplifiedChinese.rawValue
                )
            },
            matches: { $0.context.appLanguage == .simplifiedChinese }
        )
        let evidence = try XCTUnwrap(update)

        hostedView.layoutSubtreeIfNeeded()
        let updatedContainer = try singleSettingsPresentationContainer(
            in: hostedView
        )
        XCTAssertEqual(evidence.context, FlowPresentationState.shared.context)
        XCTAssertTrue(
            settingsPresentationTextValues(in: updatedContainer.pageView)
                .contains("基础显示设置、快捷键与权限")
        )
    }

    @MainActor
    func testSettingsRootThemeChangeRebuildsSettingsBridgeWithTargetAppearance() async throws {
        let previousSelectedTab = HomeTabState.shared.selectedTab
        let previousLanguageRaw = UserDefaults.standard.string(
            forKey: AppPreferenceKeys.appLanguage
        )
        let previousThemeRaw = UserDefaults.standard.string(
            forKey: AppPreferenceKeys.themeMode
        )
        let previousContext = FlowPresentationState.shared.context
        HomeTabState.shared.selectedTab = .settings
        FlowPresentationState.shared.setAppLanguage(
            rawValue: AppLanguage.simplifiedChinese.rawValue
        )
        FlowPresentationState.shared.setThemeMode(
            rawValue: ThemeMode.light.rawValue
        )
        defer {
            HomeTabState.shared.selectedTab = previousSelectedTab
            FlowPresentationState.shared.setAppLanguage(
                rawValue: previousContext.appLanguage.rawValue
            )
            FlowPresentationState.shared.setThemeMode(
                rawValue: previousContext.themeMode.rawValue
            )
            restoreSettingsPresentationDefault(
                previousLanguageRaw,
                forKey: AppPreferenceKeys.appLanguage
            )
            restoreSettingsPresentationDefault(
                previousThemeRaw,
                forKey: AppPreferenceKeys.themeMode
            )
        }

        let recorder = SettingsPresentationUpdateRecorder()
        let hostedView = NSHostingView(
            rootView: SettingsPresentationObservedContent(
                content: HomeRootView()
                    .frame(width: 1_440, height: 900, alignment: .topLeading),
                recorder: recorder
            )
        )
        hostedView.frame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        hostedView.layoutSubtreeIfNeeded()

        let baseline = try XCTUnwrap(recorder.latestEvidence)
        XCTAssertEqual(baseline.context.resolvedColorScheme, .light)
        let initialContainer = try singleSettingsPresentationContainer(
            in: hostedView
        )
        XCTAssertFalse(
            settingsPresentationCardBackgroundIsDark(
                in: initialContainer.pageView
            )
        )

        let update = await awaitSettingsPresentationUpdate(
            recorder: recorder,
            after: baseline.generation,
            description: "Settings root theme presentation update",
            trigger: {
                FlowPresentationState.shared.setThemeMode(
                    rawValue: ThemeMode.dark.rawValue
                )
            },
            matches: {
                $0.context.themeMode == .dark
                    && $0.context.resolvedColorScheme == .dark
            }
        )
        let evidence = try XCTUnwrap(update)

        hostedView.layoutSubtreeIfNeeded()
        let updatedContainer = try singleSettingsPresentationContainer(
            in: hostedView
        )
        XCTAssertEqual(evidence.context, FlowPresentationState.shared.context)
        XCTAssertTrue(
            updatedContainer.appearance?.isFlowTabDarkInterface == true
        )
        XCTAssertTrue(
            settingsPresentationCardBackgroundIsDark(
                in: updatedContainer.pageView
            )
        )
    }

    @MainActor
    private func singleSettingsPresentationContainer(
        in root: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AppKitSettingsPageContainerView {
        let containers = settingsPresentationDescendants(in: root)
            .compactMap { $0 as? AppKitSettingsPageContainerView }
        XCTAssertEqual(containers.count, 1, file: file, line: line)
        return try XCTUnwrap(containers.first, file: file, line: line)
    }

    private func settingsPresentationTextValues(in view: NSView) -> Set<String> {
        Set(
            settingsPresentationDescendants(in: view).compactMap { descendant in
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

    private func settingsPresentationCardBackgroundIsDark(
        in view: NSView
    ) -> Bool {
        settingsPresentationDescendants(in: view)
            .compactMap { $0 as? FlowSettingsCardView }
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

    private func settingsPresentationDescendants(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(settingsPresentationDescendants)
    }

    private func restoreSettingsPresentationDefault(
        _ value: String?,
        forKey key: String
    ) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
