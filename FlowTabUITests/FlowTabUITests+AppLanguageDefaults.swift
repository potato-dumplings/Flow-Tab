import XCTest

extension FlowTabUITests {
    func testFirstLaunchUsesSimplifiedChineseForTraditionalChineseSystemLanguage() {
        let app = makeApp(
            additionalArguments: appLanguageDefaultArguments(
                systemLanguageIdentifier: "zh-Hant-HK"
            )
        )
        launchFlowTabUITestApplication(app)

        guard
            assertSettingsInitialAppearanceProjectionAfterNavigation(
                in: app,
                targetDescription: "Traditional Chinese system language default",
                trigger: { openSettingsTab(in: app) }
            )
        else {
            return
        }
        assertValue(
            of: element(
                in: app,
                identifier: Identifier.settingsAppearanceAppLanguage
            ),
            equals: AppLanguageIdentifier.simplifiedChinese
        )
    }

    func testFirstLaunchUsesEnglishForNonChineseSystemLanguage() {
        let app = makeApp(
            additionalArguments: appLanguageDefaultArguments(
                systemLanguageIdentifier: "fr-FR"
            )
        )
        launchFlowTabUITestApplication(app)

        guard
            assertSettingsEnglishAppearanceProjectionAfterNavigation(
                in: app,
                targetDescription: "Non-Chinese system language default",
                trigger: { openSettingsTab(in: app) }
            ) != nil
        else {
            return
        }
        assertValue(
            of: element(
                in: app,
                identifier: Identifier.settingsAppearanceAppLanguage
            ),
            equals: AppLanguageIdentifier.english
        )
    }

    private func appLanguageDefaultArguments(
        systemLanguageIdentifier: String
    ) -> [String] {
        [
            "-AppleLanguages",
            "(\(systemLanguageIdentifier))",
            "--flowtab-ui-reset-defaults",
            "--flowtab-ui-mock-runtime",
            "--flowtab-ui-ax-trusted",
            "YES",
            "--flowtab-ui-screen-trusted",
            "YES"
        ]
    }
}

private enum AppLanguageIdentifier {
    static let simplifiedChinese = "zh-Hans"
    static let english = "en"
}
