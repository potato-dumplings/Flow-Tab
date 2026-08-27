import AppKit
import FlowTabCore
import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testSettingsIntrinsicHeightCacheReusesWidthUntilInvalidated() {
        var cache = AppKitSettingsPageIntrinsicHeightCache()

        XCTAssertNil(cache.height(forWidth: 900))
        cache.store(height: 720, forWidth: 900)
        XCTAssertEqual(cache.height(forWidth: 900), 720)
        XCTAssertEqual(cache.height(forWidth: 900.4), 720)
        XCTAssertNil(cache.height(forWidth: 901))

        cache.invalidate()
        XCTAssertNil(cache.height(forWidth: 900))
    }

    func testSettingsContentRefreshGateConsumesOnlyDistinctStates() {
        var gate = AppKitSettingsPageContentRefreshGate()
        let initialState = makeSettingsLayoutActivityState()

        XCTAssertTrue(gate.consume(initialState))
        XCTAssertFalse(gate.consume(initialState))

        let changedState = makeSettingsLayoutActivityState(hiddenAppCount: 2)
        XCTAssertTrue(gate.consume(changedState))
        XCTAssertFalse(gate.consume(changedState))
    }

    func testSettingsContentRefreshGateIncludesLanguageAndAppearance() {
        var gate = AppKitSettingsPageContentRefreshGate()
        let initialState = makeSettingsLayoutActivityState()
        let languageState = makeSettingsLayoutActivityState(
            language: .simplifiedChinese
        )
        let appearanceState = makeSettingsLayoutActivityState(
            language: .simplifiedChinese,
            targetAppearanceName: .darkAqua
        )

        XCTAssertTrue(gate.consume(initialState))
        XCTAssertTrue(gate.consume(languageState))
        XCTAssertFalse(gate.consume(languageState))
        XCTAssertTrue(gate.consume(appearanceState))
        XCTAssertFalse(gate.consume(appearanceState))
    }

    @MainActor
    func testSettingsCardLayoutDoesNotResetBackingLayerOrigin() throws {
        let card = FlowSettingsCardView(
            title: "Card",
            subtitle: "Subtitle",
            contentView: NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        )
        try assertBackingLayerTracksViewFrame(card, size: NSSize(width: 320, height: 180))
    }

    @MainActor
    func testSettingsLayerBackedChromeControlsDoNotResetBackingLayerOrigin() throws {
        let segmented = FlowSettingsSegmentedControl(options: [
            (id: "light", title: "Light"),
            (id: "dark", title: "Dark")
        ])
        segmented.updateSelection(id: "dark")
        try assertBackingLayerTracksViewFrame(segmented, size: NSSize(width: 260, height: 32))

        let dropdown = FlowDropdownControl(frame: .zero)
        dropdown.configure(
            options: [
                FlowDropdownOption(id: "zh", title: "Simplified Chinese"),
                FlowDropdownOption(id: "en", title: "English")
            ],
            selectedID: "zh",
            presentation: .form(targetAppearance: NSAppearance(named: .darkAqua) ?? NSApp.effectiveAppearance)
        )
        try assertBackingLayerTracksViewFrame(dropdown, size: NSSize(width: 240, height: 32))
    }

    @MainActor
    func testSettingsActivityOnlyUpdateDoesNotForceContentLayout() async {
        let container = AppKitSettingsPageContainerView()
        container.frame = NSRect(x: 0, y: 0, width: 1_200, height: 820)
        let state = makeSettingsLayoutActivityState()

        container.update(with: state, isActive: false)
        await awaitSettingsLayoutMainQueueTurn()

        let probe = SettingsActivityLayoutProbeView()
        container.addSubview(probe)
        probe.prepareForObservation()

        container.update(with: state, isActive: true)
        XCTAssertEqual(
            probe.layoutCount,
            0,
            "Changing only Settings activity must not force synchronous content layout."
        )

        probe.prepareForObservation()
        await awaitSettingsLayoutMainQueueTurn()
        XCTAssertEqual(
            probe.layoutCount,
            0,
            "Changing only Settings activity must not schedule deferred content layout."
        )
    }

    @MainActor
    func testSettingsStateChangeStillRefreshesContentAndLayout() async throws {
        let container = AppKitSettingsPageContainerView()
        container.frame = NSRect(x: 0, y: 0, width: 1_200, height: 820)
        container.update(
            with: makeSettingsLayoutActivityState(),
            isActive: false
        )
        await awaitSettingsLayoutMainQueueTurn()

        let probe = SettingsActivityLayoutProbeView()
        container.addSubview(probe)
        probe.prepareForObservation()

        container.update(
            with: makeSettingsLayoutActivityState(
                themeMode: .dark,
                language: .simplifiedChinese,
                hiddenAppCount: 2,
                targetAppearanceName: .darkAqua
            ),
            isActive: false
        )

        XCTAssertGreaterThan(probe.layoutCount, 0)
        XCTAssertEqual(
            container.appearance?.bestMatch(from: [.darkAqua, .aqua]),
            .darkAqua
        )
        let subtitle = try XCTUnwrap(
            settingsLayoutDescendants(in: container.pageView)
                .compactMap { $0 as? NSTextField }
                .first {
                    $0.identifier?.rawValue == "flowtab.settings.page.subtitle"
                }
        )
        XCTAssertEqual(subtitle.stringValue, "基础显示设置、快捷键与权限")
    }

    @MainActor
    func testSettingsContainerSizeChangeStillTriggersLayout() async {
        let container = AppKitSettingsPageContainerView()
        container.frame = NSRect(x: 0, y: 0, width: 1_200, height: 820)
        container.update(
            with: makeSettingsLayoutActivityState(),
            isActive: false
        )
        await awaitSettingsLayoutMainQueueTurn()

        let probe = SettingsActivityLayoutProbeView()
        container.addSubview(probe)
        probe.prepareForObservation()

        container.setFrameSize(NSSize(width: 980, height: 820))
        container.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(probe.layoutCount, 0)
    }

    @MainActor
    func testSettingsActivationStillClearsPageFirstResponder() async {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 820),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        let container = AppKitSettingsPageContainerView()
        window.contentView = container
        container.frame = window.contentView?.bounds
            ?? NSRect(x: 0, y: 0, width: 1_200, height: 820)
        let state = makeSettingsLayoutActivityState()
        container.update(with: state, isActive: false)
        await awaitSettingsLayoutMainQueueTurn()

        let field = NSTextField(string: "editing")
        field.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
        container.pageView.addSubview(field)
        XCTAssertTrue(window.makeFirstResponder(field))

        container.update(with: state, isActive: true)
        await awaitSettingsLayoutMainQueueTurn()

        XCTAssertFalse(window.firstResponder === field)
    }

    private func assertBackingLayerTracksViewFrame(
        _ view: NSView,
        size: NSSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        parent.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = NSRect(x: 48, y: 72, width: size.width, height: size.height)
        parent.addSubview(view)
        view.needsLayout = true
        parent.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()

        let layer = try XCTUnwrap(view.layer, file: file, line: line)
        XCTAssertEqual(layer.frame.minX, view.frame.minX, accuracy: 1, file: file, line: line)
        XCTAssertEqual(layer.frame.minY, view.frame.minY, accuracy: 1, file: file, line: line)
        XCTAssertEqual(layer.frame.width, view.frame.width, accuracy: 1, file: file, line: line)
        XCTAssertEqual(layer.frame.height, view.frame.height, accuracy: 1, file: file, line: line)
    }

    private func makeSettingsLayoutActivityState(
        themeMode: ThemeMode = .followSystem,
        language: AppLanguage = .english,
        hiddenAppCount: Int = 1,
        targetAppearanceName: NSAppearance.Name = .aqua
    ) -> AppKitSettingsPageState {
        AppKitSettingsPageState(
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
            hotkeyPrimaryModifierRaw: SwitcherHotkeyKey.option.rawValue,
            hotkeyMainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            hotkeyQuitKeyRaw: SwitcherHotkeyKey.q.rawValue,
            inAppWindowHotkeyBaseKeysRaw: SwitcherHotkeyKey.control.rawValue,
            inAppWindowHotkeyMainKeysRaw: SwitcherHotkeyKey.tab.rawValue,
            commandTabTakeoverRegistrationState: .inactive,
            accessibilityTrusted: false,
            screenCaptureTrusted: false,
            targetNSAppearanceName: targetAppearanceName
        )
    }

    private func settingsLayoutDescendants(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(settingsLayoutDescendants(in:))
    }

    @MainActor
    private func awaitSettingsLayoutMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

private final class SettingsActivityLayoutProbeView: NSView {
    private(set) var layoutCount = 0

    override func layout() {
        layoutCount += 1
        super.layout()
    }

    func prepareForObservation() {
        layoutCount = 0
        needsLayout = true
    }
}
