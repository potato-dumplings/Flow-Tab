import SwiftUI
import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testFirstLaunchLanguageMapsChineseIdentifiersToSimplifiedChinese() {
        let identifiers = [
            "zh",
            "zh-Hans-CN",
            "zh-Hans-MY",
            "zh-Hans-SG",
            "zh-Hant-HK",
            "zh-Hant-TW",
            "zh-Hant-MO",
            "zh_CN"
        ]

        for identifier in identifiers {
            XCTAssertEqual(
                AppLanguagePreferencesStore.firstLaunchLanguage(
                    preferredLanguageIdentifiers: [identifier]
                ),
                .simplifiedChinese,
                identifier
            )
        }
    }

    func testFirstLaunchLanguageMapsNonChinesePrimaryLanguageToEnglish() {
        XCTAssertEqual(
            AppLanguagePreferencesStore.firstLaunchLanguage(
                preferredLanguageIdentifiers: ["en-US"]
            ),
            .english
        )
        XCTAssertEqual(
            AppLanguagePreferencesStore.firstLaunchLanguage(
                preferredLanguageIdentifiers: ["fr-FR", "zh-Hant-TW"]
            ),
            .english
        )
        XCTAssertEqual(
            AppLanguagePreferencesStore.firstLaunchLanguage(
                preferredLanguageIdentifiers: []
            ),
            .english
        )
    }

    func testAppLanguageLoadPersistsSystemDerivedLanguageWhenPreferenceIsMissing() {
        guard let chineseDefaults = makeIsolatedUserDefaults(),
              let nonChineseDefaults = makeIsolatedUserDefaults()
        else { return }
        defer {
            clearIsolatedUserDefaults(chineseDefaults)
            clearIsolatedUserDefaults(nonChineseDefaults)
        }

        XCTAssertEqual(
            AppLanguagePreferencesStore.load(
                userDefaults: chineseDefaults,
                preferredLanguageIdentifiers: ["zh-Hant-HK"]
            ),
            .simplifiedChinese
        )
        XCTAssertEqual(
            chineseDefaults.string(forKey: AppPreferenceKeys.appLanguage),
            AppLanguage.simplifiedChinese.rawValue
        )

        XCTAssertEqual(
            AppLanguagePreferencesStore.load(
                userDefaults: nonChineseDefaults,
                preferredLanguageIdentifiers: ["fr-FR"]
            ),
            .english
        )
        XCTAssertEqual(
            nonChineseDefaults.string(forKey: AppPreferenceKeys.appLanguage),
            AppLanguage.english.rawValue
        )
    }

    func testAppLanguageLoadPreservesSavedLanguageAcrossSystemLanguages() {
        guard let englishDefaults = makeIsolatedUserDefaults(),
              let chineseDefaults = makeIsolatedUserDefaults()
        else { return }
        defer {
            clearIsolatedUserDefaults(englishDefaults)
            clearIsolatedUserDefaults(chineseDefaults)
        }
        englishDefaults.set(
            AppLanguage.english.rawValue,
            forKey: AppPreferenceKeys.appLanguage
        )
        chineseDefaults.set(
            AppLanguage.simplifiedChinese.rawValue,
            forKey: AppPreferenceKeys.appLanguage
        )

        XCTAssertEqual(
            AppLanguagePreferencesStore.load(
                userDefaults: englishDefaults,
                preferredLanguageIdentifiers: ["zh-Hant-TW"]
            ),
            .english
        )
        XCTAssertEqual(
            AppLanguagePreferencesStore.load(
                userDefaults: chineseDefaults,
                preferredLanguageIdentifiers: ["de-DE"]
            ),
            .simplifiedChinese
        )
    }

    @MainActor
    func testFlowPresentationStateUsesSystemDerivedLanguageWhenPreferenceIsMissing() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        let state = FlowPresentationState(
            userDefaults: userDefaults,
            notificationCenter: NotificationCenter(),
            systemThemeProvider: AppLanguageDefaultsThemeProvider(),
            preferredLanguageIdentifiers: ["ja-JP"]
        )

        XCTAssertEqual(state.context.appLanguage, .english)
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.appLanguage),
            AppLanguage.english.rawValue
        )
    }
}

@MainActor
private final class AppLanguageDefaultsThemeProvider:
    FlowPresentationSystemThemeProviding
{
    let currentColorScheme: ColorScheme = .light

    func observeColorSchemeChanges(
        _ handler: @escaping @MainActor (ColorScheme) -> Void
    ) -> FlowPresentationThemeObservation {
        FlowPresentationThemeObservation {}
    }
}
