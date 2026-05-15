import SwiftUI
import AppKit

struct AppKitSettingsPageState: Equatable {
    let showShortcutHint: Bool
    let showInCommandTab: Bool
    let themeModeRaw: String
    let appLanguageRaw: String
    let windowLayerAutoEnterDelayText: String
    let autoRestoreMinimizedWindowOnSwitch: Bool
    let hideMinimizedAppsFromAppLayer: Bool
    let showPermissionReminder: Bool
    let allowLaunchAtLogin: Bool
    let searchEnabled: Bool
    let searchDefaultScopeRaw: String
    let hiddenAppCount: Int
    let hotkeyPrimaryModifierRaw: String
    let hotkeyMainKeyRaw: String
    let hotkeyQuitKeyRaw: String
    let inAppWindowHotkeyPrimaryModifierRaw: String
    let inAppWindowHotkeyMainKeyRaw: String
    let commandTabTakeoverActive: Bool
    let accessibilityTrusted: Bool
    let screenCaptureTrusted: Bool
}

struct AppKitSettingsHotkeyRawValues: Equatable {
    let hotkeyPrimaryModifierRaw: String
    let hotkeyMainKeyRaw: String
    let hotkeyQuitKeyRaw: String
    let inAppWindowHotkeyPrimaryModifierRaw: String
    let inAppWindowHotkeyMainKeyRaw: String
}

final class AppKitFlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class AppKitSettingsPageContainerView: NSView {
    let pageView = AppKitSettingsPageView()

    private let scrollView = NSScrollView()
    private let documentView = AppKitFlippedDocumentView()
    private let horizontalContentInset: CGFloat = 24
    private let verticalContentInset = HomePageLayout.alignedTopInset
    private var wasActive = false
    private var pendingInitialFocusClear = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    func update(with state: AppKitSettingsPageState, isActive: Bool) {
        pageView.update(with: state)
        if isActive && !wasActive {
            clearInitialFirstResponderIfNeeded()
        }
        wasActive = isActive
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let viewportWidth = scrollView.contentView.bounds.width
        guard viewportWidth > 0 else { return }

        let pageWidth = max(viewportWidth - horizontalContentInset * 2, 320)
        let fittedSize = pageView.preferredFittingSize(forWidth: pageWidth)
        let topInset = verticalContentInset + safeAreaInsets.top
        let documentHeight = fittedSize.height + topInset + verticalContentInset

        documentView.frame = NSRect(
            x: 0,
            y: 0,
            width: viewportWidth,
            height: documentHeight
        )
        pageView.frame = NSRect(
            x: horizontalContentInset,
            y: topInset,
            width: pageWidth,
            height: fittedSize.height
        )
    }

    private func buildViewHierarchy() {
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        pageView.translatesAutoresizingMaskIntoConstraints = true
        documentView.translatesAutoresizingMaskIntoConstraints = true
        documentView.addSubview(pageView)
        scrollView.documentView = documentView

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func clearInitialFirstResponderIfNeeded() {
        guard !pendingInitialFocusClear else { return }
        pendingInitialFocusClear = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingInitialFocusClear = false
            self.resignPageFirstResponderIfNeeded()
        }
    }

    private func resignPageFirstResponderIfNeeded() {
        guard let window else { return }

        if let view = window.firstResponder as? NSView, view.isDescendant(of: pageView) {
            window.makeFirstResponder(nil)
            return
        }

        if let editor = window.firstResponder as? NSTextView,
            let editedView = editor.delegate as? NSView,
            editedView.isDescendant(of: pageView)
        {
            window.makeFirstResponder(nil)
        }
    }
}

struct AppKitSettingsPageContent: NSViewRepresentable {
    let isActive: Bool
    @Binding var showShortcutHint: Bool
    @Binding var showInCommandTab: Bool
    @Binding var themeModeRaw: String
    @Binding var appLanguageRaw: String
    let windowLayerAutoEnterDelayText: String
    @Binding var autoRestoreMinimizedWindowOnSwitch: Bool
    @Binding var hideMinimizedAppsFromAppLayer: Bool
    @Binding var showPermissionReminder: Bool
    @Binding var allowLaunchAtLogin: Bool
    @Binding var searchEnabled: Bool
    @Binding var searchDefaultScopeRaw: String
    let hiddenAppCount: Int
    @Binding var hotkeyPrimaryModifierRaw: String
    @Binding var hotkeyMainKeyRaw: String
    @Binding var hotkeyQuitKeyRaw: String
    @Binding var inAppWindowHotkeyPrimaryModifierRaw: String
    @Binding var inAppWindowHotkeyMainKeyRaw: String
    let commandTabTakeoverActive: Bool
    let accessibilityTrusted: Bool
    let screenCaptureTrusted: Bool
    let onWindowLayerAutoEnterDelayTextChanged: (String) -> Void
    let onWindowLayerAutoEnterDelayTextCommitted: () -> Void
    let onWindowLayerAutoEnterDelayEditingChanged: (Bool) -> Void
    let onMainHotkeyChanged: (AppKitSettingsHotkeyRawValues) -> Void
    let onQuitHotkeyChanged: (AppKitSettingsHotkeyRawValues) -> Void
    let onInAppWindowHotkeyChanged: (AppKitSettingsHotkeyRawValues) -> Void
    let onLaunchAtLoginChanged: (Bool) -> Void
    let onManageAppVisibility: () -> Void
    let onAccessibilityAction: () -> Void
    let onScreenCaptureAction: () -> Void

    func makeNSView(context: Context) -> AppKitSettingsPageContainerView {
        AppKitSettingsPageContainerView()
    }

    func updateNSView(_ nsView: AppKitSettingsPageContainerView, context: Context) {
        let showShortcutHint = $showShortcutHint
        let showInCommandTab = $showInCommandTab
        let themeModeRaw = $themeModeRaw
        let appLanguageRaw = $appLanguageRaw
        let autoRestoreMinimizedWindowOnSwitch = $autoRestoreMinimizedWindowOnSwitch
        let hideMinimizedAppsFromAppLayer = $hideMinimizedAppsFromAppLayer
        let showPermissionReminder = $showPermissionReminder
        let allowLaunchAtLogin = $allowLaunchAtLogin
        let searchEnabled = $searchEnabled
        let searchDefaultScopeRaw = $searchDefaultScopeRaw
        let hotkeyPrimaryModifierRaw = $hotkeyPrimaryModifierRaw
        let hotkeyMainKeyRaw = $hotkeyMainKeyRaw
        let hotkeyQuitKeyRaw = $hotkeyQuitKeyRaw
        let inAppWindowHotkeyPrimaryModifierRaw = $inAppWindowHotkeyPrimaryModifierRaw
        let inAppWindowHotkeyMainKeyRaw = $inAppWindowHotkeyMainKeyRaw
        let pageView = nsView.pageView
        let currentHotkeyValues = {
            AppKitSettingsHotkeyRawValues(
                hotkeyPrimaryModifierRaw: hotkeyPrimaryModifierRaw.wrappedValue,
                hotkeyMainKeyRaw: hotkeyMainKeyRaw.wrappedValue,
                hotkeyQuitKeyRaw: hotkeyQuitKeyRaw.wrappedValue,
                inAppWindowHotkeyPrimaryModifierRaw: inAppWindowHotkeyPrimaryModifierRaw.wrappedValue,
                inAppWindowHotkeyMainKeyRaw: inAppWindowHotkeyMainKeyRaw.wrappedValue
            )
        }

        pageView.onShowShortcutHintChanged = { showShortcutHint.wrappedValue = $0 }
        pageView.onShowInCommandTabChanged = { showInCommandTab.wrappedValue = $0 }
        pageView.onThemeModeChanged = { themeModeRaw.wrappedValue = $0 }
        pageView.onAppLanguageChanged = { appLanguageRaw.wrappedValue = $0 }
        pageView.onWindowLayerAutoEnterDelayTextChanged = onWindowLayerAutoEnterDelayTextChanged
        pageView.onWindowLayerAutoEnterDelayTextCommitted = onWindowLayerAutoEnterDelayTextCommitted
        pageView.onWindowLayerAutoEnterDelayEditingChanged = onWindowLayerAutoEnterDelayEditingChanged
        pageView.onAutoRestoreMinimizedWindowOnSwitchChanged = {
            autoRestoreMinimizedWindowOnSwitch.wrappedValue = $0
        }
        pageView.onHideMinimizedAppsFromAppLayerChanged = {
            hideMinimizedAppsFromAppLayer.wrappedValue = $0
        }
        pageView.onSearchEnabledChanged = { searchEnabled.wrappedValue = $0 }
        pageView.onSearchDefaultScopeChanged = { searchDefaultScopeRaw.wrappedValue = $0 }
        pageView.onManageAppVisibility = onManageAppVisibility
        pageView.onHotkeyPrimaryModifierChanged = {
            hotkeyPrimaryModifierRaw.wrappedValue = $0
            let values = currentHotkeyValues()
            onMainHotkeyChanged(values)
        }
        pageView.onHotkeyMainKeyChanged = {
            hotkeyMainKeyRaw.wrappedValue = $0
            let values = currentHotkeyValues()
            onMainHotkeyChanged(values)
        }
        pageView.onHotkeyQuitKeyChanged = {
            hotkeyQuitKeyRaw.wrappedValue = $0
            let values = currentHotkeyValues()
            onQuitHotkeyChanged(values)
        }
        pageView.onInAppWindowPrimaryModifierChanged = {
            inAppWindowHotkeyPrimaryModifierRaw.wrappedValue = $0
            let values = currentHotkeyValues()
            onInAppWindowHotkeyChanged(values)
        }
        pageView.onInAppWindowMainKeyChanged = {
            inAppWindowHotkeyMainKeyRaw.wrappedValue = $0
            let values = currentHotkeyValues()
            onInAppWindowHotkeyChanged(values)
        }
        pageView.onShowPermissionReminderChanged = { showPermissionReminder.wrappedValue = $0 }
        pageView.onAllowLaunchAtLoginChanged = {
            allowLaunchAtLogin.wrappedValue = $0
            onLaunchAtLoginChanged($0)
        }
        pageView.onAccessibilityAction = onAccessibilityAction
        pageView.onScreenCaptureAction = onScreenCaptureAction
        nsView.update(
            with: AppKitSettingsPageState(
                showShortcutHint: showShortcutHint.wrappedValue,
                showInCommandTab: showInCommandTab.wrappedValue,
                themeModeRaw: themeModeRaw.wrappedValue,
                appLanguageRaw: appLanguageRaw.wrappedValue,
                windowLayerAutoEnterDelayText: windowLayerAutoEnterDelayText,
                autoRestoreMinimizedWindowOnSwitch: autoRestoreMinimizedWindowOnSwitch.wrappedValue,
                hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer.wrappedValue,
                showPermissionReminder: showPermissionReminder.wrappedValue,
                allowLaunchAtLogin: allowLaunchAtLogin.wrappedValue,
                searchEnabled: searchEnabled.wrappedValue,
                searchDefaultScopeRaw: searchDefaultScopeRaw.wrappedValue,
                hiddenAppCount: hiddenAppCount,
                hotkeyPrimaryModifierRaw: hotkeyPrimaryModifierRaw.wrappedValue,
                hotkeyMainKeyRaw: hotkeyMainKeyRaw.wrappedValue,
                hotkeyQuitKeyRaw: hotkeyQuitKeyRaw.wrappedValue,
                inAppWindowHotkeyPrimaryModifierRaw: inAppWindowHotkeyPrimaryModifierRaw.wrappedValue,
                inAppWindowHotkeyMainKeyRaw: inAppWindowHotkeyMainKeyRaw.wrappedValue,
                commandTabTakeoverActive: commandTabTakeoverActive,
                accessibilityTrusted: accessibilityTrusted,
                screenCaptureTrusted: screenCaptureTrusted
            ),
            isActive: isActive
        )
    }
}

final class AppKitSettingsPageView: NSView {
    var onShowShortcutHintChanged: ((Bool) -> Void)?
    var onShowInCommandTabChanged: ((Bool) -> Void)?
    var onThemeModeChanged: ((String) -> Void)?
    var onAppLanguageChanged: ((String) -> Void)?
    var onWindowLayerAutoEnterDelayTextChanged: ((String) -> Void)?
    var onWindowLayerAutoEnterDelayTextCommitted: (() -> Void)?
    var onWindowLayerAutoEnterDelayEditingChanged: ((Bool) -> Void)?
    var onAutoRestoreMinimizedWindowOnSwitchChanged: ((Bool) -> Void)?
    var onHideMinimizedAppsFromAppLayerChanged: ((Bool) -> Void)?
    var onSearchEnabledChanged: ((Bool) -> Void)?
    var onSearchDefaultScopeChanged: ((String) -> Void)?
    var onManageAppVisibility: (() -> Void)?
    var onHotkeyPrimaryModifierChanged: ((String) -> Void)?
    var onHotkeyMainKeyChanged: ((String) -> Void)?
    var onHotkeyQuitKeyChanged: ((String) -> Void)?
    var onInAppWindowPrimaryModifierChanged: ((String) -> Void)?
    var onInAppWindowMainKeyChanged: ((String) -> Void)?
    var onShowPermissionReminderChanged: ((Bool) -> Void)?
    var onAllowLaunchAtLoginChanged: ((Bool) -> Void)?
    var onAccessibilityAction: (() -> Void)?
    var onScreenCaptureAction: (() -> Void)?

    private let contentStack = NSStackView()
    private let headerStack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: AppStrings.text(.settingsPageTitle))
    private let subtitleLabel = NSTextField(labelWithString: AppStrings.text(.settingsPageSubtitle))
    private let columnsStack = NSStackView()
    private let leftColumn = NSStackView()
    private let rightColumn = NSStackView()
    private let dismissEditingClickRecognizer = NSClickGestureRecognizer()

    private let appearanceContent = AppearanceSettingsCardAppKitView()
    private let windowBehaviorContent = WindowBehaviorSettingsCardAppKitView()
    private let permissionContent = PermissionSettingsCardAppKitView()
    private let searchContent = SearchSettingsCardAppKitView()
    private let appVisibilityContent = AppVisibilitySettingsCardAppKitView()
    private let hotkeyContent = HotkeySettingsCardAppKitView()

    private lazy var appearanceCard = AppKitSectionCardView(
        title: AppStrings.text(.settingsCardAppearanceTitle),
        subtitle: AppStrings.text(.settingsCardAppearanceSubtitle),
        contentView: appearanceContent
    )
    private lazy var windowBehaviorCard = AppKitSectionCardView(
        title: AppStrings.text(.settingsCardWindowBehaviorTitle),
        subtitle: AppStrings.text(.settingsCardWindowBehaviorSubtitle),
        contentView: windowBehaviorContent
    )
    private lazy var permissionCard = AppKitSectionCardView(
        title: AppStrings.text(.settingsCardPermissionTitle),
        subtitle: AppStrings.text(.settingsCardPermissionSubtitle),
        contentView: permissionContent
    )
    private lazy var searchCard = AppKitSectionCardView(
        title: AppStrings.text(.settingsCardSearchTitle),
        subtitle: AppStrings.text(.settingsCardSearchSubtitle),
        contentView: searchContent
    )
    private lazy var appVisibilityCard = AppKitSectionCardView(
        title: AppStrings.text(.settingsCardAppVisibilityTitle),
        subtitle: nil,
        contentView: appVisibilityContent
    )
    private lazy var hotkeyCard = AppKitSectionCardView(
        title: AppStrings.text(.settingsCardHotkeyTitle),
        subtitle: AppStrings.text(.settingsCardHotkeySubtitle),
        contentView: hotkeyContent
    )

    private var currentState: AppKitSettingsPageState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
        wireCallbacks()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
        wireCallbacks()
    }

    override var intrinsicContentSize: NSSize {
        layoutSubtreeIfNeeded()
        return NSSize(width: NSView.noIntrinsicMetric, height: contentStack.fittingSize.height)
    }

    func update(with state: AppKitSettingsPageState) {
        guard currentState != state else { return }
        currentState = state

        appearanceContent.update(
            with: AppearanceSettingsCardState(
                showShortcutHint: state.showShortcutHint,
                showInCommandTab: state.showInCommandTab,
                themeModeRaw: state.themeModeRaw,
                appLanguageRaw: state.appLanguageRaw
            )
        )
        windowBehaviorContent.update(
            with: WindowBehaviorSettingsCardState(
                windowLayerAutoEnterDelayText: state.windowLayerAutoEnterDelayText,
                autoRestoreMinimizedWindowOnSwitch: state.autoRestoreMinimizedWindowOnSwitch,
                hideMinimizedAppsFromAppLayer: state.hideMinimizedAppsFromAppLayer
            )
        )
        searchContent.update(
            with: SearchSettingsCardState(
                searchEnabled: state.searchEnabled,
                searchDefaultScopeRaw: state.searchDefaultScopeRaw
            )
        )
        appVisibilityContent.update(
            with: AppVisibilitySettingsCardState(hiddenAppCount: state.hiddenAppCount)
        )
        appVisibilityCard.updateTitleAccessory(
            AppVisibilitySettingsCardState(hiddenAppCount: state.hiddenAppCount).statusText
        )
        hotkeyContent.update(
            with: HotkeySettingsCardState(
                hotkeyPrimaryModifierRaw: state.hotkeyPrimaryModifierRaw,
                hotkeyMainKeyRaw: state.hotkeyMainKeyRaw,
                hotkeyQuitKeyRaw: state.hotkeyQuitKeyRaw,
                inAppWindowHotkeyPrimaryModifierRaw: state.inAppWindowHotkeyPrimaryModifierRaw,
                inAppWindowHotkeyMainKeyRaw: state.inAppWindowHotkeyMainKeyRaw,
                commandTabTakeoverActive: state.commandTabTakeoverActive,
                accessibilityTrusted: state.accessibilityTrusted
            )
        )
        permissionContent.update(
            with: PermissionSettingsCardState(
                showPermissionReminder: state.showPermissionReminder,
                allowLaunchAtLogin: state.allowLaunchAtLogin,
                accessibilityTrusted: state.accessibilityTrusted,
                screenCaptureTrusted: state.screenCaptureTrusted
            )
        )
        appearanceCard.invalidateIntrinsicContentSize()
        windowBehaviorCard.invalidateIntrinsicContentSize()
        permissionCard.invalidateIntrinsicContentSize()
        searchCard.invalidateIntrinsicContentSize()
        appVisibilityCard.invalidateIntrinsicContentSize()
        hotkeyCard.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        dismissEditingClickRecognizer.target = self
        dismissEditingClickRecognizer.action = #selector(handlePageClickToDismissEditing(_:))
        dismissEditingClickRecognizer.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(dismissEditingClickRecognizer)

        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor

        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 2
        headerStack.detachesHiddenViews = true
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(subtitleLabel)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.detachesHiddenViews = true
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        columnsStack.orientation = .horizontal
        columnsStack.alignment = .top
        columnsStack.distribution = .fillEqually
        columnsStack.spacing = 12
        columnsStack.translatesAutoresizingMaskIntoConstraints = false
        columnsStack.setContentHuggingPriority(.required, for: .vertical)
        columnsStack.setContentCompressionResistancePriority(.required, for: .vertical)

        leftColumn.orientation = .vertical
        leftColumn.alignment = .leading
        leftColumn.spacing = 12
        leftColumn.detachesHiddenViews = true
        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        leftColumn.setContentHuggingPriority(.required, for: .vertical)
        leftColumn.setContentCompressionResistancePriority(.required, for: .vertical)

        rightColumn.orientation = .vertical
        rightColumn.alignment = .leading
        rightColumn.spacing = 12
        rightColumn.detachesHiddenViews = true
        rightColumn.translatesAutoresizingMaskIntoConstraints = false
        rightColumn.setContentHuggingPriority(.required, for: .vertical)
        rightColumn.setContentCompressionResistancePriority(.required, for: .vertical)

        contentStack.addArrangedSubview(headerStack)
        contentStack.addArrangedSubview(columnsStack)
        headerStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        columnsStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        columnsStack.addArrangedSubview(leftColumn)
        columnsStack.addArrangedSubview(rightColumn)

        addCard(appearanceCard, to: leftColumn)
        addCard(windowBehaviorCard, to: leftColumn)
        addCard(permissionCard, to: leftColumn)
        addCard(searchCard, to: rightColumn)
        addCard(appVisibilityCard, to: rightColumn)
        addCard(hotkeyCard, to: rightColumn)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func wireCallbacks() {
        appearanceContent.onShowShortcutHintChanged = { [weak self] in
            self?.onShowShortcutHintChanged?($0)
        }
        appearanceContent.onShowInCommandTabChanged = { [weak self] in
            self?.onShowInCommandTabChanged?($0)
        }
        appearanceContent.onThemeModeChanged = { [weak self] in
            self?.onThemeModeChanged?($0)
        }
        appearanceContent.onAppLanguageChanged = { [weak self] in
            self?.onAppLanguageChanged?($0)
        }

        windowBehaviorContent.onWindowLayerAutoEnterDelayTextChanged = { [weak self] in
            self?.onWindowLayerAutoEnterDelayTextChanged?($0)
        }
        windowBehaviorContent.onWindowLayerAutoEnterDelayTextCommitted = { [weak self] in
            self?.onWindowLayerAutoEnterDelayTextCommitted?()
        }
        windowBehaviorContent.onWindowLayerAutoEnterDelayEditingChanged = { [weak self] in
            self?.onWindowLayerAutoEnterDelayEditingChanged?($0)
        }
        windowBehaviorContent.onAutoRestoreMinimizedWindowOnSwitchChanged = { [weak self] in
            self?.onAutoRestoreMinimizedWindowOnSwitchChanged?($0)
        }
        windowBehaviorContent.onHideMinimizedAppsFromAppLayerChanged = { [weak self] in
            self?.onHideMinimizedAppsFromAppLayerChanged?($0)
        }

        searchContent.onSearchEnabledChanged = { [weak self] in
            self?.onSearchEnabledChanged?($0)
        }
        searchContent.onSearchDefaultScopeChanged = { [weak self] in
            self?.onSearchDefaultScopeChanged?($0)
        }
        appVisibilityContent.onManageAppVisibility = { [weak self] in
            self?.onManageAppVisibility?()
        }

        hotkeyContent.onHotkeyPrimaryModifierChanged = { [weak self] in
            self?.onHotkeyPrimaryModifierChanged?($0)
        }
        hotkeyContent.onHotkeyMainKeyChanged = { [weak self] in
            self?.onHotkeyMainKeyChanged?($0)
        }
        hotkeyContent.onHotkeyQuitKeyChanged = { [weak self] in
            self?.onHotkeyQuitKeyChanged?($0)
        }
        hotkeyContent.onInAppWindowPrimaryModifierChanged = { [weak self] in
            self?.onInAppWindowPrimaryModifierChanged?($0)
        }
        hotkeyContent.onInAppWindowMainKeyChanged = { [weak self] in
            self?.onInAppWindowMainKeyChanged?($0)
        }

        permissionContent.onShowPermissionReminderChanged = { [weak self] in
            self?.onShowPermissionReminderChanged?($0)
        }
        permissionContent.onAllowLaunchAtLoginChanged = { [weak self] in
            self?.onAllowLaunchAtLoginChanged?($0)
        }
        permissionContent.onAccessibilityAction = { [weak self] in
            self?.onAccessibilityAction?()
        }
        permissionContent.onScreenCaptureAction = { [weak self] in
            self?.onScreenCaptureAction?()
        }
    }

    @objc private func handlePageClickToDismissEditing(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended else { return }

        let location = recognizer.location(in: self)
        let hitView = hitTest(location)
        guard !windowBehaviorContent.containsDelayInputDescendant(hitView) else { return }
        guard windowBehaviorContent.ownsDelayInputFirstResponder(window?.firstResponder) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(nil)
        }
    }

    private func addCard(_ card: NSView, to column: NSStackView) {
        column.addArrangedSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
    }
}
