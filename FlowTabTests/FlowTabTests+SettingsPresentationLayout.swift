import AppKit
import FlowTabCore
import SwiftUI
import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testSettingsRootThemeSwitchMatchesColdDarkLayoutInSwiftUIHost() async throws {
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
            restoreSettingsPresentationLayoutDefault(
                previousLanguageRaw,
                forKey: AppPreferenceKeys.appLanguage
            )
            restoreSettingsPresentationLayoutDefault(
                previousThemeRaw,
                forKey: AppPreferenceKeys.themeMode
            )
        }

        let recorder = SettingsPresentationUpdateRecorder()
        let hostedView = makeSettingsPresentationLayoutHost(recorder: recorder)
        let baseline = try XCTUnwrap(recorder.latestEvidence)
        XCTAssertEqual(baseline.context.resolvedColorScheme, .light)
        let initialContainer = try settingsPresentationLayoutContainer(
            in: hostedView
        )
        settleSettingsPresentationLayout(initialContainer)

        let update = await awaitSettingsPresentationUpdate(
            recorder: recorder,
            after: baseline.generation,
            description: "Settings layout explicit dark presentation update",
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
        _ = try XCTUnwrap(update)

        hostedView.layoutSubtreeIfNeeded()
        let switchedContainer = try settingsPresentationLayoutContainer(
            in: hostedView
        )
        XCTAssertTrue(settingsPresentationLayoutIsDark(switchedContainer))
        settleSettingsPresentationLayout(switchedContainer)
        let switchedFrames = settingsPresentationLayoutCardFrames(
            in: switchedContainer.pageView,
            relativeTo: hostedView
        )

        let coldRecorder = SettingsPresentationUpdateRecorder()
        let coldDarkHostedView = makeSettingsPresentationLayoutHost(
            recorder: coldRecorder
        )
        let coldEvidence = try XCTUnwrap(coldRecorder.latestEvidence)
        XCTAssertEqual(coldEvidence.context.resolvedColorScheme, .dark)
        let coldDarkContainer = try settingsPresentationLayoutContainer(
            in: coldDarkHostedView
        )
        XCTAssertTrue(settingsPresentationLayoutIsDark(coldDarkContainer))
        settleSettingsPresentationLayout(coldDarkContainer)
        let coldDarkFrames = settingsPresentationLayoutCardFrames(
            in: coldDarkContainer.pageView,
            relativeTo: coldDarkHostedView
        )

        XCTAssertEqual(switchedFrames.keys.sorted(), coldDarkFrames.keys.sorted())
        for (title, switchedFrame) in switchedFrames {
            let coldFrame = try XCTUnwrap(
                coldDarkFrames[title],
                "Missing cold dark card frame for \(title)"
            )
            assertSettingsPresentationLayoutFrame(
                switchedFrame,
                equals: coldFrame,
                message: "Hot theme switch differs from cold dark layout for \(title)"
            )
        }
        try assertSettingsPresentationCardsStayNearHeader(
            in: switchedContainer.pageView
        )
    }

    @MainActor
    func testSettingsRootFollowSystemThemeChangeRebuildsSettingsBridgeLikeExplicitSwitch() async throws {
        let aquaAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let previousSelectedTab = HomeTabState.shared.selectedTab
        let previousLanguageRaw = UserDefaults.standard.string(
            forKey: AppPreferenceKeys.appLanguage
        )
        let previousThemeRaw = UserDefaults.standard.string(
            forKey: AppPreferenceKeys.themeMode
        )
        let previousAppearance = NSApp.appearance
        let previousContext = FlowPresentationState.shared.context
        HomeTabState.shared.selectedTab = .settings
        NSApp.appearance = aquaAppearance
        postSettingsPresentationSystemAppearanceChanged()
        FlowPresentationState.shared.setAppLanguage(
            rawValue: AppLanguage.english.rawValue
        )
        FlowPresentationState.shared.setThemeMode(
            rawValue: ThemeMode.followSystem.rawValue
        )
        XCTAssertEqual(
            FlowPresentationState.shared.context.resolvedColorScheme,
            .light
        )
        defer {
            HomeTabState.shared.selectedTab = previousSelectedTab
            NSApp.appearance = previousAppearance
            postSettingsPresentationSystemAppearanceChanged()
            FlowPresentationState.shared.setAppLanguage(
                rawValue: previousContext.appLanguage.rawValue
            )
            FlowPresentationState.shared.setThemeMode(
                rawValue: previousContext.themeMode.rawValue
            )
            restoreSettingsPresentationLayoutDefault(
                previousLanguageRaw,
                forKey: AppPreferenceKeys.appLanguage
            )
            restoreSettingsPresentationLayoutDefault(
                previousThemeRaw,
                forKey: AppPreferenceKeys.themeMode
            )
        }

        let recorder = SettingsPresentationUpdateRecorder()
        let hostedView = makeSettingsPresentationLayoutHost(recorder: recorder)
        let baseline = try XCTUnwrap(recorder.latestEvidence)
        XCTAssertEqual(baseline.context.resolvedColorScheme, .light)
        let initialContainer = try settingsPresentationLayoutContainer(
            in: hostedView
        )
        settleSettingsPresentationLayout(initialContainer)
        let initialContainerID = ObjectIdentifier(initialContainer)

        let update = await awaitSettingsPresentationUpdate(
            recorder: recorder,
            after: baseline.generation,
            description: "Settings follow-system dark presentation update",
            trigger: {
                NSApp.appearance = darkAppearance
                postSettingsPresentationSystemAppearanceChanged()
            },
            matches: {
                $0.context.themeMode == .followSystem
                    && $0.context.resolvedColorScheme == .dark
            }
        )
        let evidence = try XCTUnwrap(update)

        hostedView.layoutSubtreeIfNeeded()
        let rebuiltContainer = try settingsPresentationLayoutContainer(
            in: hostedView
        )
        XCTAssertEqual(evidence.context, FlowPresentationState.shared.context)
        XCTAssertNotEqual(
            ObjectIdentifier(rebuiltContainer),
            initialContainerID
        )
        XCTAssertTrue(settingsPresentationLayoutIsDark(rebuiltContainer))
        settleSettingsPresentationLayout(rebuiltContainer)
        try assertSettingsPresentationCardsStayNearHeader(
            in: rebuiltContainer.pageView
        )
        assertSettingsPresentationCardsDoNotOverlap(
            settingsPresentationLayoutCards(in: rebuiltContainer.pageView),
            in: rebuiltContainer.pageView
        )
        assertSettingsPresentationArrangedSubviewsDoNotOverlap(
            in: rebuiltContainer.pageView
        )
    }
}
