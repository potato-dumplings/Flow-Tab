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
        view.layoutSubtreeIfNeeded()

        let localizedText = localizedTextValues(in: view)
        XCTAssertTrue(localizedText.contains("1 app hidden"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertFalse(localizedText.contains("1 apps hidden"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertTrue(localizedText.contains("System"), localizedText.sorted().joined(separator: "\n"))
        XCTAssertFalse(localizedText.contains("Follow System"), localizedText.sorted().joined(separator: "\n"))
        let fixedControlWidthConstraints = requiredFixedSettingsControlWidthConstraints(in: view)
            .filter { constraint in
                constraint.firstItem is FlowFormSelectControl
                    || constraint.firstItem is FlowGradientActionButton
            }
        XCTAssertTrue(
            fixedControlWidthConstraints.isEmpty,
            fixedControlWidthConstraints.map(\.description).joined(separator: "\n")
        )

        let languageSelect: FlowFormSelectControl = try XCTUnwrap(
            descendant(in: view, identifier: "flowtab.settings.appearance.app-language")
        )
        XCTAssertGreaterThanOrEqual(languageSelect.intrinsicContentSize.width, 140)

        let scopeSelect: FlowFormSelectControl = try XCTUnwrap(
            descendant(in: view, identifier: "flowtab.settings.search.default-scope")
        )
        XCTAssertGreaterThanOrEqual(scopeSelect.intrinsicContentSize.width, 84)

        let themeModeControl: FlowCapsuleSegmentedControl = try XCTUnwrap(
            descendant(in: view, identifier: "flowtab.settings.appearance.theme-mode")
        )
        XCTAssertLessThanOrEqual(themeModeControl.frame.width, themeModeControl.intrinsicContentSize.width + 1)
        XCTAssertLessThanOrEqual(themeModeControl.intrinsicContentSize.width, 260)

        let accessibilityButton: FlowGradientActionButton = try XCTUnwrap(
            descendant(in: view, identifier: "flowtab.settings.permission.accessibility-action")
        )
        let screenCaptureButton: FlowGradientActionButton = try XCTUnwrap(
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
            250
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

        let accessibilityButton: FlowGradientActionButton = try XCTUnwrap(
            descendant(in: view, identifier: "flowtab.settings.permission.accessibility-action")
        )
        let screenCaptureButton: FlowGradientActionButton = try XCTUnwrap(
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
        language: AppLanguage,
        hiddenAppCount: Int,
        accessibilityTrusted: Bool = false,
        screenCaptureTrusted: Bool = false
    ) -> AppKitSettingsPageState {
        AppKitSettingsPageState(
            showShortcutHint: true,
            showInCommandTab: true,
            themeModeRaw: ThemeMode.followSystem.rawValue,
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
            screenCaptureTrusted: screenCaptureTrusted
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

                return constraint.firstItem is FlowCapsuleSegmentedControl
                    || constraint.firstItem is FlowFormSelectControl
                    || constraint.firstItem is FlowGradientActionButton
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

    private func sectionCard(in view: NSView, containingText text: String) throws -> AppKitSectionCardView {
        try XCTUnwrap(
            descendantViews(in: view).compactMap { card in
                guard let sectionCard = card as? AppKitSectionCardView,
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
