import Foundation
import XCTest

enum FlowTabUITestSettingsEnglishAppearanceProjectionPolicy {
    static let projectionWatchdog: TimeInterval = 17
    static let pageTitle = "Settings"
    static let pageSubtitle = "Display, hotkeys, and permissions"
    static let appearanceTitle = "Appearance"
    static let themeModeTitle = "Theme mode"
    static let priorPageSubtitle = "基础显示设置、快捷键与权限"
}

struct FlowTabUITestSettingsEnglishAppearanceProjectionSnapshot:
    Equatable
{
    let appState: XCUIApplication.State
    let settingsContentExists: Bool
    let pageTitleExists: Bool
    let pageTitleValue: String?
    let pageSubtitleExists: Bool
    let pageSubtitleValue: String?
    let appearanceTitleExists: Bool
    let appearanceTitleValue: String?
    let themeModeTitleExists: Bool
    let themeModeTitleValue: String?
    let priorPageSubtitleExists: Bool
    let priorPageSubtitleValue: String?

    var isExactProjection: Bool {
        appState == .runningForeground
            && settingsContentExists
            && pageTitleExists
            && pageSubtitleExists
            && appearanceTitleExists
            && themeModeTitleExists
            && !priorPageSubtitleExists
    }

    var diagnosticSummary: String {
        "isExactProjection=\(isExactProjection) "
            + "appState=\(String(describing: appState)) "
            + "settingsContentExists=\(settingsContentExists) "
            + "pageTitleExists=\(pageTitleExists) "
            + "pageTitleValue=\(String(reflecting: pageTitleValue)) "
            + "pageSubtitleExists=\(pageSubtitleExists) "
            + "pageSubtitleValue="
            + "\(String(reflecting: pageSubtitleValue)) "
            + "appearanceTitleExists=\(appearanceTitleExists) "
            + "appearanceTitleValue="
            + "\(String(reflecting: appearanceTitleValue)) "
            + "themeModeTitleExists=\(themeModeTitleExists) "
            + "themeModeTitleValue="
            + "\(String(reflecting: themeModeTitleValue)) "
            + "priorPageSubtitleExists=\(priorPageSubtitleExists) "
            + "priorPageSubtitleValue="
            + "\(String(reflecting: priorPageSubtitleValue))"
    }
}

struct FlowTabUITestSettingsEnglishAppearanceElements {
    let pageTitle: XCUIElement
    let pageSubtitle: XCUIElement
}

final class FlowTabUITestSettingsEnglishAppearanceProjectionObservationOwner {
    private let conditionOwner:
        FlowTabUITestConditionObservationOwner<
            FlowTabUITestSettingsEnglishAppearanceProjectionSnapshot
        >

    init(
        acceptsEvidence: @escaping () -> Bool = { true },
        observationRegistration:
            FlowTabUITestConditionObservationRegistration? =
                FlowTabUITestConditionReadbackScheduler
                    .mainRunLoopRegistration(
                        cadence:
                            FlowTabUITestConditionObservationPolicy
                                .xcuiReadbackCadence
                    ),
        readback: @escaping () ->
            FlowTabUITestSettingsEnglishAppearanceProjectionSnapshot
    ) {
        conditionOwner = FlowTabUITestConditionObservationOwner(
            observationRegistration: observationRegistration,
            readback: readback,
            isSatisfied: { snapshot in
                acceptsEvidence() && snapshot.isExactProjection
            },
            describe: { snapshot in
                "acceptanceEnabled=\(acceptsEvidence()) "
                    + snapshot.diagnosticSummary
            }
        )
    }

    func start() {
        conditionOwner.start()
    }

    func requestReadback(
        source: FlowTabUITestConditionObservationSource
    ) {
        conditionOwner.requestReadback(source: source)
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsEnglishAppearanceProjectionSnapshot
    >? {
        conditionOwner.waitForResolution(timeout: timeout)
    }

    var latestEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsEnglishAppearanceProjectionSnapshot
    >? {
        conditionOwner.latestEvidence
    }

    var resolvedEvidence: FlowTabUITestConditionEvidence<
        FlowTabUITestSettingsEnglishAppearanceProjectionSnapshot
    >? {
        conditionOwner.resolvedEvidence
    }

    var diagnosticSummary: String {
        conditionOwner.diagnosticSummary
    }

    func cancel() {
        conditionOwner.cancel()
    }
}

private struct FlowTabUITestSettingsEnglishAppearanceProjectionAllElements {
    let settingsContent: XCUIElement
    let exposed: FlowTabUITestSettingsEnglishAppearanceElements
    let appearanceTitle: XCUIElement
    let themeModeTitle: XCUIElement
    let priorPageSubtitle: XCUIElement
}

extension FlowTabUITests {
    func assertSettingsEnglishAppearanceProjectionAfterSelectingEnglish(
        in app: XCUIApplication,
        targetDescription: String
    ) -> FlowTabUITestSettingsEnglishAppearanceElements? {
        assertSettingsEnglishAppearanceProjection(
            in: app,
            targetDescription: targetDescription,
            trigger: {
                self.selectOption(
                    in: app,
                    controlIdentifier:
                        Identifier.settingsAppearanceAppLanguage,
                    optionIdentifier: "en"
                )
                self.assertValue(
                    of: self.element(
                        in: app,
                        identifier:
                            Identifier.settingsAppearanceAppLanguage
                    ),
                    equals: "en"
                )
            }
        )
    }

    private func assertSettingsEnglishAppearanceProjection(
        in app: XCUIApplication,
        targetDescription: String,
        trigger: () -> Void
    ) -> FlowTabUITestSettingsEnglishAppearanceElements? {
        let elements = settingsEnglishAppearanceProjectionElements(in: app)
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration:
                    FlowTabUITestConditionReadbackScheduler
                        .mainRunLoopRegistration(
                            cadence:
                                FlowTabUITestConditionObservationPolicy
                                    .xcuiReadbackCadence
                        )
            )
        var acceptsEvidence = false
        let owner =
            FlowTabUITestSettingsEnglishAppearanceProjectionObservationOwner(
                acceptsEvidence: { acceptsEvidence },
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                readback: settingsEnglishAppearanceProjectionReadback(
                    in: app,
                    elements: elements
                )
            )
        owner.start()
        defer {
            owner.cancel()
            deferredReadbacks.cancel()
        }

        guard owner.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "Settings English Appearance projection did not "
                    + "establish its initial readback. "
                    + "target=\(targetDescription) "
                    + owner.diagnosticSummary
            )
            return nil
        }

        trigger()
        acceptsEvidence = true
        owner.requestReadback(source: .triggerReadback)
        if owner.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }

        guard
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsEnglishAppearanceProjectionPolicy
                        .projectionWatchdog
            ) != nil
        else {
            XCTFail(
                "Settings English Appearance projection watchdog expired. "
                    + "target=\(targetDescription) "
                    + "expectedPageTitle="
                    + String(
                        reflecting:
                            FlowTabUITestSettingsEnglishAppearanceProjectionPolicy
                                .pageTitle
                    )
                    + " expectedPageSubtitle="
                    + String(
                        reflecting:
                            FlowTabUITestSettingsEnglishAppearanceProjectionPolicy
                                .pageSubtitle
                    )
                    + " expectedAppearanceTitle="
                    + String(
                        reflecting:
                            FlowTabUITestSettingsEnglishAppearanceProjectionPolicy
                                .appearanceTitle
                    )
                    + " expectedThemeModeTitle="
                    + String(
                        reflecting:
                            FlowTabUITestSettingsEnglishAppearanceProjectionPolicy
                                .themeModeTitle
                    )
                    + " expectedAbsentSubtitle="
                    + String(
                        reflecting:
                            FlowTabUITestSettingsEnglishAppearanceProjectionPolicy
                                .priorPageSubtitle
                    )
                    + " "
                    + owner.diagnosticSummary
            )
            return nil
        }
        return elements.exposed
    }

    private func settingsEnglishAppearanceProjectionElements(
        in app: XCUIApplication
    ) -> FlowTabUITestSettingsEnglishAppearanceProjectionAllElements {
        FlowTabUITestSettingsEnglishAppearanceProjectionAllElements(
            settingsContent: element(
                in: app,
                identifier: Identifier.settingsTabContent
            ),
            exposed: FlowTabUITestSettingsEnglishAppearanceElements(
                pageTitle: app.staticTexts[
                    FlowTabUITestSettingsEnglishAppearanceProjectionPolicy
                        .pageTitle
                ],
                pageSubtitle: app.staticTexts[
                    FlowTabUITestSettingsEnglishAppearanceProjectionPolicy
                        .pageSubtitle
                ]
            ),
            appearanceTitle: app.staticTexts[
                FlowTabUITestSettingsEnglishAppearanceProjectionPolicy
                    .appearanceTitle
            ],
            themeModeTitle: app.staticTexts[
                FlowTabUITestSettingsEnglishAppearanceProjectionPolicy
                    .themeModeTitle
            ],
            priorPageSubtitle: app.staticTexts[
                FlowTabUITestSettingsEnglishAppearanceProjectionPolicy
                    .priorPageSubtitle
            ]
        )
    }

    private func settingsEnglishAppearanceProjectionReadback(
        in app: XCUIApplication,
        elements: FlowTabUITestSettingsEnglishAppearanceProjectionAllElements
    ) -> () -> FlowTabUITestSettingsEnglishAppearanceProjectionSnapshot {
        {
            let pageTitleExists = elements.exposed.pageTitle.exists
            let pageSubtitleExists = elements.exposed.pageSubtitle.exists
            let appearanceTitleExists = elements.appearanceTitle.exists
            let themeModeTitleExists = elements.themeModeTitle.exists
            let priorPageSubtitleExists = elements.priorPageSubtitle.exists
            return FlowTabUITestSettingsEnglishAppearanceProjectionSnapshot(
                appState: app.state,
                settingsContentExists: elements.settingsContent.exists,
                pageTitleExists: pageTitleExists,
                pageTitleValue:
                    pageTitleExists
                        ? self.elementStringValue(elements.exposed.pageTitle)
                        : nil,
                pageSubtitleExists: pageSubtitleExists,
                pageSubtitleValue:
                    pageSubtitleExists
                        ? self.elementStringValue(
                            elements.exposed.pageSubtitle
                        )
                        : nil,
                appearanceTitleExists: appearanceTitleExists,
                appearanceTitleValue:
                    appearanceTitleExists
                        ? self.elementStringValue(elements.appearanceTitle)
                        : nil,
                themeModeTitleExists: themeModeTitleExists,
                themeModeTitleValue:
                    themeModeTitleExists
                        ? self.elementStringValue(elements.themeModeTitle)
                        : nil,
                priorPageSubtitleExists: priorPageSubtitleExists,
                priorPageSubtitleValue:
                    priorPageSubtitleExists
                        ? self.elementStringValue(elements.priorPageSubtitle)
                        : nil
            )
        }
    }
}
