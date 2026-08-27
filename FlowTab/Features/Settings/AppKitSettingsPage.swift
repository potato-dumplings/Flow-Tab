import SwiftUI
import AppKit
import FlowTabCore

final class AppKitFlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class AppKitSettingsPageContainerView: NSView {
    let pageView = AppKitSettingsPageView()

    private let scrollView = NSScrollView()
    private let documentView = AppKitFlippedDocumentView()
    private let horizontalContentInset = FlowPageLayout.horizontalInset
    private let verticalContentInset = FlowPageLayout.alignedTopInset
    private var wasActive = false
    private var pendingInitialFocusClear = false
    private var contentRefreshGate = AppKitSettingsPageContentRefreshGate()
    private var pageLeadingConstraint: NSLayoutConstraint?
    private var pageTopConstraint: NSLayoutConstraint?
    private var pageWidthConstraint: NSLayoutConstraint?
    private var pageHeightConstraint: NSLayoutConstraint?
    private let maximumLayoutSettlingPasses = 3
    private var hasDeferredLayoutRefresh = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    func update(with state: AppKitSettingsPageState, isActive: Bool) {
        let becameActive = isActive && !wasActive
        wasActive = isActive
        if becameActive {
            clearInitialFirstResponderIfNeeded()
        }

        guard contentRefreshGate.consume(state) else { return }

        let targetAppearance = FlowSettingsStyleResolver.targetAppearance(
            named: state.targetNSAppearanceName,
            fallback: inheritedAppearanceFallback
        )
        appearance = targetAppearance
        scrollView.appearance = targetAppearance
        documentView.appearance = targetAppearance
        pageView.appearance = targetAppearance
        pageView.applySettingsAppearance(targetAppearance)
        pageView.update(with: state)
        refreshLayoutAfterSettingsUpdate()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let previousSize = frame.size
        super.setFrameSize(newSize)
        if previousSize != newSize {
            needsLayout = true
        }
    }

    override func setBoundsSize(_ newSize: NSSize) {
        let previousSize = bounds.size
        super.setBoundsSize(newSize)
        if previousSize != newSize {
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()

        let containerSize = bounds.size
        scrollView.frame = NSRect(origin: .zero, size: containerSize)

        let viewportWidth = containerSize.width
        guard viewportWidth > 0 else { return }

        let pageWidth = max(viewportWidth - horizontalContentInset * 2, 320)
        pageLeadingConstraint?.constant = horizontalContentInset
        pageWidthConstraint?.constant = pageWidth
        let topInset = verticalContentInset + safeAreaInsets.top
        var previousHeight: CGFloat?
        for _ in 0..<maximumLayoutSettlingPasses {
            pageHeightConstraint?.isActive = false
            pageView.prepareLayout(forWidth: pageWidth)
            let fittedSize = pageView.preferredFittingSize(forWidth: pageWidth)
            let documentHeight = fittedSize.height + topInset + verticalContentInset

            documentView.frame = NSRect(
                x: 0,
                y: 0,
                width: viewportWidth,
                height: documentHeight
            )
            pageTopConstraint?.constant = topInset
            pageHeightConstraint?.constant = fittedSize.height
            pageHeightConstraint?.isActive = true
            documentView.layoutSubtreeIfNeeded()

            if let previousHeight, abs(previousHeight - fittedSize.height) <= 0.5 {
                break
            }
            previousHeight = fittedSize.height
        }
    }

    private func buildViewHierarchy() {
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        documentView.translatesAutoresizingMaskIntoConstraints = true
        documentView.addSubview(pageView)
        scrollView.documentView = documentView

        addSubview(scrollView)
        let pageLeadingConstraint = pageView.leadingAnchor.constraint(
            equalTo: documentView.leadingAnchor
        )
        let pageTopConstraint = pageView.topAnchor.constraint(equalTo: documentView.topAnchor)
        let pageWidthConstraint = pageView.widthAnchor.constraint(equalToConstant: 320)
        let pageHeightConstraint = pageView.heightAnchor.constraint(equalToConstant: 1)
        self.pageLeadingConstraint = pageLeadingConstraint
        self.pageTopConstraint = pageTopConstraint
        self.pageWidthConstraint = pageWidthConstraint
        self.pageHeightConstraint = pageHeightConstraint
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            pageLeadingConstraint,
            pageTopConstraint,
            pageWidthConstraint
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

    private func refreshLayoutAfterSettingsUpdate() {
        pageView.invalidateMeasuredContentHeight()
        pageView.needsLayout = true
        documentView.needsLayout = true
        needsLayout = true
        layoutSubtreeIfNeeded()
        scheduleDeferredLayoutRefresh()
    }

    private func scheduleDeferredLayoutRefresh() {
        guard !hasDeferredLayoutRefresh else { return }
        hasDeferredLayoutRefresh = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasDeferredLayoutRefresh = false
            self.pageView.invalidateMeasuredContentHeight()
            self.pageView.needsLayout = true
            self.documentView.needsLayout = true
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
        }
    }

    private var inheritedAppearanceFallback: NSAppearance {
        window?.effectiveAppearance
            ?? superview?.effectiveAppearance
            ?? NSApp.effectiveAppearance
    }

}

final class AppKitSettingsPageView: NSView {
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
    var onMainModifiersChanged: ((SwitcherHotkeyKeySet) -> Void)?
    var onMainReverseModifiersChanged: ((SwitcherHotkeyKeySet) -> Void)?
    var onMainKeyChanged: ((SwitcherHotkeyKeySet) -> Void)?
    var onQuitKeyChanged: ((SwitcherHotkeyKeySet) -> Void)?
    var onInAppBaseKeysChanged: ((SwitcherHotkeyKeySet) -> Void)?
    var onInAppReverseModifiersChanged: ((SwitcherHotkeyKeySet) -> Void)?
    var onInAppMainKeysChanged: ((SwitcherHotkeyKeySet) -> Void)?
    var onDismissHotkeyConflict: (() -> Void)?
    var onShowPermissionReminderChanged: ((Bool) -> Void)?
    var onAllowLaunchAtLoginChanged: ((Bool) -> Void)?
    var onAccessibilityAction: (() -> Void)?
    var onScreenCaptureAction: (() -> Void)?

    private let contentStack = NSStackView()
    private let headerStack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: AppStrings.text(.settingsPageTitle))
    private let subtitleLabel = NSTextField(wrappingLabelWithString: AppStrings.text(.settingsPageSubtitle))
    private let columnsStack = NSStackView()
    private let leftColumn = NSStackView()
    private let rightColumn = NSStackView()
    private let columnFlexibleSpacers = [NSView(), NSView()]
    private let dismissEditingClickRecognizer = NSClickGestureRecognizer()

    private let appearanceContent = AppearanceSettingsCardAppKitView()
    private let windowBehaviorContent = WindowBehaviorSettingsCardAppKitView()
    private let permissionContent = PermissionSettingsCardAppKitView()
    private let searchContent = SearchSettingsCardAppKitView()
    private let appVisibilityContent = AppVisibilitySettingsCardAppKitView()
    private let hotkeyContent = HotkeySettingsCardAppKitView()
    private var columnWidthConstraints: [NSLayoutConstraint] = []
    private var isUsingSingleColumnLayout = false

    private lazy var appearanceCard = FlowSettingsCardView(
        title: AppStrings.text(.settingsCardAppearanceTitle),
        subtitle: AppStrings.text(.settingsCardAppearanceSubtitle),
        contentView: appearanceContent
    )
    private lazy var windowBehaviorCard = FlowSettingsCardView(
        title: AppStrings.text(.settingsCardWindowBehaviorTitle),
        subtitle: AppStrings.text(.settingsCardWindowBehaviorSubtitle),
        contentView: windowBehaviorContent
    )
    private lazy var permissionCard = FlowSettingsCardView(
        title: AppStrings.text(.settingsCardPermissionTitle),
        subtitle: AppStrings.text(.settingsCardPermissionSubtitle),
        contentView: permissionContent
    )
    private lazy var searchCard = FlowSettingsCardView(
        title: AppStrings.text(.settingsCardSearchTitle),
        subtitle: AppStrings.text(.settingsCardSearchSubtitle),
        contentView: searchContent
    )
    private lazy var appVisibilityCard = FlowSettingsCardView(
        title: AppStrings.text(.settingsCardAppVisibilityTitle),
        subtitle: nil,
        contentView: appVisibilityContent
    )
    private lazy var hotkeyCard = FlowSettingsCardView(
        title: AppStrings.text(.settingsCardHotkeyTitle),
        subtitle: AppStrings.text(.settingsCardHotkeySubtitle),
        contentView: hotkeyContent
    )

    private var currentState: AppKitSettingsPageState?
    private var intrinsicHeightCache =
        AppKitSettingsPageIntrinsicHeightCache()
    private var targetSettingsAppearance = FlowSettingsStyleResolver.defaultAppearance

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
        let width = bounds.width
        if let height = intrinsicHeightCache.height(forWidth: width) {
            return NSSize(width: NSView.noIntrinsicMetric, height: height)
        }

        let height = contentStack.fittingSize.height
        intrinsicHeightCache.store(height: height, forWidth: width)
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    func invalidateMeasuredContentHeight() {
        intrinsicHeightCache.invalidate()
        invalidateIntrinsicContentSize()
    }

    override func layout() {
        let needsSecondLayoutPass = updateHeaderWrappingLabelWidths(forWidth: bounds.width)
        super.layout()
        if needsSecondLayoutPass {
            super.layout()
        }
    }

    static func usesSingleColumnLayout(forWidth width: CGFloat) -> Bool {
        width < 680
    }

    func prepareLayout(forWidth width: CGFloat) {
        let useSingleColumn = Self.usesSingleColumnLayout(forWidth: width)
        guard useSingleColumn != isUsingSingleColumnLayout else { return }
        isUsingSingleColumnLayout = useSingleColumn

        columnsStack.orientation = useSingleColumn ? .vertical : .horizontal
        columnsStack.alignment = useSingleColumn ? .leading : .top
        columnsStack.distribution = useSingleColumn ? .fill : .fillEqually
        columnWidthConstraints.forEach { $0.isActive = useSingleColumn }
        invalidateMeasuredContentHeight()
    }

    func preferredFittingSize(forWidth width: CGFloat) -> CGSize {
        prepareLayout(forWidth: width)
        updateHeaderWrappingLabelWidths(forWidth: width)
        layoutSubtreeIfNeeded()

        let headerHeight = preferredHeight(for: headerStack)
        let leftColumnHeight = preferredColumnHeight(leftColumn)
        let rightColumnHeight = preferredColumnHeight(rightColumn)
        let columnsHeight: CGFloat
        if isUsingSingleColumnLayout {
            columnsHeight = leftColumnHeight + columnsStack.spacing + rightColumnHeight
        } else {
            columnsHeight = max(leftColumnHeight, rightColumnHeight)
        }

        let fittedSize = CGSize(
            width: width,
            height: ceil(headerHeight + contentStack.spacing + columnsHeight)
        )
        intrinsicHeightCache.store(height: fittedSize.height, forWidth: width)
        return fittedSize
    }

    func update(with state: AppKitSettingsPageState) {
        guard currentState != state else { return }
        currentState = state

        let language = AppLanguagePreferencesStore.resolve(rawValue: state.appLanguageRaw)
        titleLabel.stringValue = AppStrings.text(.settingsPageTitle, language: language)
        subtitleLabel.stringValue = AppStrings.text(.settingsPageSubtitle, language: language)
        subtitleLabel.isHidden = subtitleLabel.stringValue.isEmpty
        subtitleLabel.invalidateIntrinsicContentSize()
        headerStack.invalidateIntrinsicContentSize()
        updateCardChrome(language: language)

        appearanceContent.update(
            with: AppearanceSettingsCardState(
                showInCommandTab: state.showInCommandTab,
                themeModeRaw: state.themeModeRaw,
                appLanguageRaw: state.appLanguageRaw
            )
        )
        windowBehaviorContent.update(
            with: WindowBehaviorSettingsCardState(
                windowLayerAutoEnterDelayText: state.windowLayerAutoEnterDelayText,
                autoRestoreMinimizedWindowOnSwitch: state.autoRestoreMinimizedWindowOnSwitch,
                hideMinimizedAppsFromAppLayer: state.hideMinimizedAppsFromAppLayer,
                appLanguageRaw: state.appLanguageRaw
            )
        )
        searchContent.update(
            with: SearchSettingsCardState(
                searchEnabled: state.searchEnabled,
                searchDefaultScopeRaw: state.searchDefaultScopeRaw,
                appLanguageRaw: state.appLanguageRaw,
                accessibilityTrusted: state.accessibilityTrusted
            )
        )
        let appVisibilityState = AppVisibilitySettingsCardState(
            hiddenAppCount: state.hiddenAppCount,
            appLanguageRaw: state.appLanguageRaw
        )
        appVisibilityContent.update(
            with: appVisibilityState
        )
        appVisibilityCard.updateTitleAccessory(
            appVisibilityState.statusText,
            accessibilityIdentifier:
                "flowtab.settings.app-visibility.effective-hidden-count",
            accessibilityValue: "\(appVisibilityState.hiddenAppCount)"
        )
        hotkeyContent.update(with: hotkeyCardState(from: state))
        permissionContent.update(
            with: PermissionSettingsCardState(
                showPermissionReminder: state.showPermissionReminder,
                allowLaunchAtLogin: state.allowLaunchAtLogin,
                accessibilityTrusted: state.accessibilityTrusted,
                screenCaptureTrusted: state.screenCaptureTrusted,
                appLanguageRaw: state.appLanguageRaw
            )
        )
        appearanceCard.invalidateIntrinsicContentSize()
        windowBehaviorCard.invalidateIntrinsicContentSize()
        permissionCard.invalidateIntrinsicContentSize()
        searchCard.invalidateIntrinsicContentSize()
        appVisibilityCard.invalidateIntrinsicContentSize()
        hotkeyCard.invalidateIntrinsicContentSize()
        invalidateMeasuredContentHeight()
    }

    func updateHotkeyContent(with values: AppKitSettingsHotkeyRawValues) {
        guard let currentState else { return }
        hotkeyContent.update(
            with: hotkeyCardState(from: currentState, overridingRawValuesWith: values)
        )
        hotkeyCard.invalidateIntrinsicContentSize()
        invalidateMeasuredContentHeight()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applySettingsAppearance(targetSettingsAppearance)
    }

    private func hotkeyCardState(
        from state: AppKitSettingsPageState,
        overridingRawValuesWith values: AppKitSettingsHotkeyRawValues? = nil
    ) -> HotkeySettingsCardState {
        HotkeySettingsCardState(
            hotkeyPrimaryModifierRaw: values?.hotkeyPrimaryModifierRaw
                ?? state.hotkeyPrimaryModifierRaw,
            hotkeyReverseModifiersRaw: values?.hotkeyReverseModifiersRaw
                ?? state.hotkeyReverseModifiersRaw,
            hotkeyMainKeyRaw: values?.hotkeyMainKeyRaw
                ?? state.hotkeyMainKeyRaw,
            hotkeyQuitKeyRaw: values?.hotkeyQuitKeyRaw
                ?? state.hotkeyQuitKeyRaw,
            inAppWindowHotkeyBaseKeysRaw:
                values?.inAppWindowHotkeyBaseKeysRaw
                ?? state.inAppWindowHotkeyBaseKeysRaw,
            inAppWindowHotkeyReverseKeysRaw:
                values?.inAppWindowHotkeyReverseKeysRaw
                ?? state.inAppWindowHotkeyReverseKeysRaw,
            inAppWindowHotkeyMainKeysRaw:
                values?.inAppWindowHotkeyMainKeysRaw
                ?? state.inAppWindowHotkeyMainKeysRaw,
            commandTabTakeoverRegistrationState: state.commandTabTakeoverRegistrationState,
            accessibilityTrusted: state.accessibilityTrusted,
            appLanguageRaw: state.appLanguageRaw,
            hotkeyConflict: state.hotkeyConflict,
            hotkeyPermissionRequirement:
                state.hotkeyPermissionRequirement
        )
    }

    func applySettingsAppearance(_ appearance: NSAppearance) {
        targetSettingsAppearance = appearance
        self.appearance = appearance
        for subview in descendantViews(in: self) {
            subview.appearance = appearance
        }
        for view in descendantRefreshableViews(in: self) where view !== self {
            view.applySettingsAppearance(appearance)
        }
    }

    private func updateCardChrome(language: AppLanguage) {
        appearanceCard.updateChrome(
            title: AppStrings.text(.settingsCardAppearanceTitle, language: language),
            subtitle: AppStrings.text(.settingsCardAppearanceSubtitle, language: language)
        )
        windowBehaviorCard.updateChrome(
            title: AppStrings.text(.settingsCardWindowBehaviorTitle, language: language),
            subtitle: AppStrings.text(.settingsCardWindowBehaviorSubtitle, language: language)
        )
        permissionCard.updateChrome(
            title: AppStrings.text(.settingsCardPermissionTitle, language: language),
            subtitle: AppStrings.text(.settingsCardPermissionSubtitle, language: language)
        )
        searchCard.updateChrome(
            title: AppStrings.text(.settingsCardSearchTitle, language: language),
            subtitle: AppStrings.text(.settingsCardSearchSubtitle, language: language)
        )
        appVisibilityCard.updateChrome(
            title: AppStrings.text(.settingsCardAppVisibilityTitle, language: language),
            subtitle: nil
        )
        hotkeyCard.updateChrome(
            title: AppStrings.text(.settingsCardHotkeyTitle, language: language),
            subtitle: AppStrings.text(.settingsCardHotkeySubtitle, language: language)
        )
    }

    private func buildViewHierarchy() {
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        dismissEditingClickRecognizer.target = self
        dismissEditingClickRecognizer.action = #selector(handlePageClickToDismissEditing(_:))
        dismissEditingClickRecognizer.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(dismissEditingClickRecognizer)

        titleLabel.font = FlowTypography.appKit(.pageTitle)
        subtitleLabel.font = FlowTypography.appKit(.pageSubtitle)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.setContentHuggingPriority(.required, for: .vertical)
        subtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.setFlowTabTestingIdentifier("flowtab.settings.page.subtitle")

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
        columnWidthConstraints = [
            leftColumn.widthAnchor.constraint(equalTo: columnsStack.widthAnchor),
            rightColumn.widthAnchor.constraint(equalTo: columnsStack.widthAnchor)
        ]

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
        for (column, spacer) in zip(
            [leftColumn, rightColumn],
            columnFlexibleSpacers
        ) {
            spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
            column.addArrangedSubview(spacer)
        }
        leftColumn.setCustomSpacing(0, after: permissionCard)
        rightColumn.setCustomSpacing(0, after: hotkeyCard)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    private func wireCallbacks() {
        appearanceContent.onShowInCommandTabChanged = { [weak self] in
            self?.notifyPageInteraction()
            self?.onShowInCommandTabChanged?($0)
        }
        appearanceContent.onThemeModeChanged = { [weak self] in
            self?.notifyPageInteraction()
            self?.onThemeModeChanged?($0)
        }
        appearanceContent.onAppLanguageChanged = { [weak self] in
            self?.notifyPageInteraction()
            self?.onAppLanguageChanged?($0)
        }

        windowBehaviorContent.onWindowLayerAutoEnterDelayTextChanged = { [weak self] in
            self?.notifyPageInteraction()
            self?.onWindowLayerAutoEnterDelayTextChanged?($0)
        }
        windowBehaviorContent.onWindowLayerAutoEnterDelayTextCommitted = { [weak self] in
            self?.notifyPageInteraction()
            self?.onWindowLayerAutoEnterDelayTextCommitted?()
        }
        windowBehaviorContent.onWindowLayerAutoEnterDelayEditingChanged = { [weak self] in
            self?.notifyPageInteraction()
            self?.onWindowLayerAutoEnterDelayEditingChanged?($0)
        }
        windowBehaviorContent.onAutoRestoreMinimizedWindowOnSwitchChanged = { [weak self] in
            self?.notifyPageInteraction()
            self?.onAutoRestoreMinimizedWindowOnSwitchChanged?($0)
        }
        windowBehaviorContent.onHideMinimizedAppsFromAppLayerChanged = { [weak self] in
            self?.notifyPageInteraction()
            self?.onHideMinimizedAppsFromAppLayerChanged?($0)
        }

        searchContent.onSearchEnabledChanged = { [weak self] in
            self?.notifyPageInteraction()
            self?.onSearchEnabledChanged?($0)
        }
        searchContent.onSearchDefaultScopeChanged = { [weak self] in
            self?.notifyPageInteraction()
            self?.onSearchDefaultScopeChanged?($0)
        }
        appVisibilityContent.onManageAppVisibility = { [weak self] in
            self?.notifyPageInteraction()
            self?.onManageAppVisibility?()
        }

        hotkeyContent.onInteraction = { [weak self] in
            self?.notifyPageInteraction()
        }
        hotkeyContent.onMainModifiersChanged = { [weak self] in
            self?.notifyPageInteraction()
            self?.onMainModifiersChanged?($0)
        }
        hotkeyContent.onMainReverseModifiersChanged = { [weak self] in
            self?.notifyPageInteraction()
            self?.onMainReverseModifiersChanged?($0)
        }
        hotkeyContent.onMainKeyChanged = { [weak self] in
            self?.notifyPageInteraction()
            self?.onMainKeyChanged?($0)
        }
        hotkeyContent.onQuitKeyChanged = { [weak self] in
            self?.notifyPageInteraction()
            self?.onQuitKeyChanged?($0)
        }
        hotkeyContent.onInAppBaseKeysChanged = { [weak self] in
            self?.notifyPageInteraction()
            self?.onInAppBaseKeysChanged?($0)
        }
        hotkeyContent.onInAppReverseModifiersChanged = { [weak self] in
            self?.notifyPageInteraction()
            self?.onInAppReverseModifiersChanged?($0)
        }
        hotkeyContent.onInAppMainKeysChanged = { [weak self] in
            self?.notifyPageInteraction()
            self?.onInAppMainKeysChanged?($0)
        }

        permissionContent.onShowPermissionReminderChanged = { [weak self] in
            self?.notifyPageInteraction()
            self?.onShowPermissionReminderChanged?($0)
        }
        permissionContent.onAllowLaunchAtLoginChanged = { [weak self] in
            self?.notifyPageInteraction()
            self?.onAllowLaunchAtLoginChanged?($0)
        }
        permissionContent.onAccessibilityAction = { [weak self] in
            self?.notifyPageInteraction()
            self?.onAccessibilityAction?()
        }
        permissionContent.onScreenCaptureAction = { [weak self] in
            self?.notifyPageInteraction()
            self?.onScreenCaptureAction?()
        }
    }

    @objc private func handlePageClickToDismissEditing(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended else { return }

        notifyPageInteraction()

        let location = recognizer.location(in: self)
        let hitView = hitTest(location)
        guard !windowBehaviorContent.containsDelayInputDescendant(hitView) else { return }
        guard windowBehaviorContent.ownsDelayInputFirstResponder(window?.firstResponder) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(nil)
        }
    }

    private func notifyPageInteraction() {
        onDismissHotkeyConflict?()
    }

    private func addCard(_ card: NSView, to column: NSStackView) {
        column.addArrangedSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
    }

    @discardableResult
    private func updateHeaderWrappingLabelWidths(forWidth width: CGFloat) -> Bool {
        guard width > 0 else { return false }
        let preferredWidth = floor(width)
        guard abs(subtitleLabel.preferredMaxLayoutWidth - preferredWidth) > 0.5 else { return false }
        subtitleLabel.preferredMaxLayoutWidth = preferredWidth
        subtitleLabel.invalidateIntrinsicContentSize()
        headerStack.invalidateIntrinsicContentSize()
        return true
    }

    private func preferredColumnHeight(_ stackView: NSStackView) -> CGFloat {
        let visibleSubviews = stackView.arrangedSubviews.filter { view in
            !view.isHidden
                && !columnFlexibleSpacers.contains { $0 === view }
        }
        guard !visibleSubviews.isEmpty else { return 0 }
        let contentHeight = visibleSubviews
            .map { preferredHeight(for: $0) }
            .reduce(0, +)
        return ceil(contentHeight + stackView.spacing * CGFloat(visibleSubviews.count - 1))
    }

    private func preferredHeight(for view: NSView) -> CGFloat {
        FlowSettingsLayoutMetrics.preferredHeight(for: view)
    }

    private func descendantRefreshableViews(in view: NSView) -> [NSView & FlowSettingsAppearanceRefreshable] {
        view.subviews.flatMap { subview -> [NSView & FlowSettingsAppearanceRefreshable] in
            var matches: [NSView & FlowSettingsAppearanceRefreshable] = []
            if let refreshable = subview as? NSView & FlowSettingsAppearanceRefreshable {
                matches.append(refreshable)
            }
            matches.append(contentsOf: descendantRefreshableViews(in: subview))
            return matches
        }
    }

    private func descendantViews(in view: NSView) -> [NSView] {
        view.subviews.flatMap { subview in
            [subview] + descendantViews(in: subview)
        }
    }
}
