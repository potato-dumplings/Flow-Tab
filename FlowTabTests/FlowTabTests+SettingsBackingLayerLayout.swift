import AppKit
import FlowTabCore
import SwiftUI
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

        XCTAssertEqual(gate.contentRevision, 0)
        XCTAssertTrue(gate.consume(initialState))
        XCTAssertEqual(gate.contentRevision, 1)
        XCTAssertFalse(gate.consume(initialState))
        XCTAssertEqual(gate.contentRevision, 1)

        let changedState = makeSettingsLayoutActivityState(hiddenAppCount: 2)
        XCTAssertTrue(gate.consume(changedState))
        XCTAssertEqual(gate.contentRevision, 2)
        XCTAssertFalse(gate.consume(changedState))
        XCTAssertEqual(gate.contentRevision, 2)
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
        XCTAssertEqual(gate.contentRevision, 3)
    }

    func testSettingsLayoutMeasurementCacheUsesCompleteLayoutSignature() {
        var cache = AppKitSettingsPageLayoutMeasurementCache()
        let signature = makeSettingsLayoutSignature()
        let fittedSize = CGSize(width: 1_152, height: 760)

        XCTAssertNil(cache.fittedSize(for: signature))
        cache.store(fittedSize: fittedSize, for: signature)
        XCTAssertEqual(cache.fittedSize(for: signature), fittedSize)
        XCTAssertNil(
            cache.fittedSize(
                for: makeSettingsLayoutSignature(
                    viewportSize: CGSize(width: 1_180, height: 820)
                )
            )
        )
        XCTAssertNil(
            cache.fittedSize(
                for: makeSettingsLayoutSignature(
                    safeAreaInsets: .init(
                        top: 24,
                        left: 0,
                        bottom: 0,
                        right: 0
                    )
                )
            )
        )
        XCTAssertNil(
            cache.fittedSize(
                for: makeSettingsLayoutSignature(
                    layoutDirection: .rightToLeft
                )
            )
        )
        XCTAssertNil(
            cache.fittedSize(
                for: makeSettingsLayoutSignature(backingScale: 2)
            )
        )
        XCTAssertNil(
            cache.fittedSize(
                for: makeSettingsLayoutSignature(
                    effectiveAppearanceName: .darkAqua
                )
            )
        )
        XCTAssertNil(
            cache.fittedSize(
                for: makeSettingsLayoutSignature(contentRevision: 5)
            )
        )

        cache.invalidate()
        XCTAssertNil(cache.fittedSize(for: signature))
    }

    func testFillViewportSizingUsesProposalAndMountedBounds() {
        XCTAssertEqual(
            FlowFillViewportSizing.resolve(
                proposal: ProposedViewSize(width: 640, height: 480),
                currentSize: CGSize(width: 900, height: 700)
            ),
            CGSize(width: 640, height: 480)
        )
        XCTAssertEqual(
            FlowFillViewportSizing.resolve(
                proposal: ProposedViewSize(width: 640, height: nil),
                currentSize: CGSize(width: 900, height: 700)
            ),
            CGSize(width: 640, height: 700)
        )
        XCTAssertEqual(
            FlowFillViewportSizing.resolve(
                proposal: ProposedViewSize(width: nil, height: 480),
                currentSize: CGSize(width: 900, height: 700)
            ),
            CGSize(width: 900, height: 480)
        )
    }

    func testFillViewportSizingFallsBackOnlyToValidMountedBounds() {
        XCTAssertNil(
            FlowFillViewportSizing.resolve(
                proposal: ProposedViewSize(width: nil, height: nil),
                currentSize: .zero
            )
        )
        XCTAssertEqual(
            FlowFillViewportSizing.resolve(
                proposal: ProposedViewSize(
                    width: .nan,
                    height: -1
                ),
                currentSize: CGSize(width: 900, height: 700)
            ),
            CGSize(width: 900, height: 700)
        )
        XCTAssertNil(
            FlowFillViewportSizing.resolve(
                proposal: ProposedViewSize(width: nil, height: 480),
                currentSize: CGSize(
                    width: CGFloat.infinity,
                    height: 700
                )
            )
        )
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

        container.update(with: state)
        container.setActive(true)
        await awaitSettingsLayoutMainQueueTurn()
        container.setActive(false)
        await awaitSettingsLayoutMainQueueTurn()

        let probe = SettingsActivityLayoutProbeView()
        container.addSubview(probe)
        probe.prepareForObservation()

        container.setActive(true)
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
    func testSettingsStateChangeDefersWhileInactiveAndRefreshesOnActivation() async throws {
        let container = AppKitSettingsPageContainerView()
        container.frame = NSRect(x: 0, y: 0, width: 1_200, height: 820)
        container.update(with: makeSettingsLayoutActivityState())
        container.setActive(true)
        await awaitSettingsLayoutMainQueueTurn()
        container.setActive(false)
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
            )
        )

        XCTAssertEqual(probe.layoutCount, 0)
        XCTAssertEqual(
            container.appearance?.bestMatch(from: [.darkAqua, .aqua]),
            .aqua
        )

        container.setActive(true)
        await awaitSettingsLayoutMainQueueTurn()

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
        container.update(with: makeSettingsLayoutActivityState())
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
        container.update(with: state)
        await awaitSettingsLayoutMainQueueTurn()

        let field = NSTextField(string: "editing")
        field.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
        container.pageView.addSubview(field)
        XCTAssertTrue(window.makeFirstResponder(field))

        container.setActive(true)
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

    private func makeSettingsLayoutSignature(
        viewportSize: CGSize = CGSize(width: 1_200, height: 820),
        safeAreaInsets: AppKitSettingsPageSafeAreaInsets = .init(
            top: 0,
            left: 0,
            bottom: 0,
            right: 0
        ),
        layoutDirection: NSUserInterfaceLayoutDirection = .leftToRight,
        backingScale: CGFloat = 1,
        effectiveAppearanceName: NSAppearance.Name = .aqua,
        contentRevision: UInt64 = 4
    ) -> AppKitSettingsPageLayoutSignature {
        AppKitSettingsPageLayoutSignature(
            viewportSize: viewportSize,
            safeAreaInsets: safeAreaInsets,
            layoutDirection: layoutDirection,
            backingScale: backingScale,
            effectiveAppearanceName: effectiveAppearanceName,
            contentRevision: contentRevision
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
