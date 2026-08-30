import SwiftUI
import AppKit
import FlowTabCore

final class AppKitSettingsPageView: NSView {
    var onContentLayoutInvalidated: (() -> Void)?
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
    private var cardHeightConstraints: [(
        card: FlowSettingsCardView,
        constraint: NSLayoutConstraint
    )] = []

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
    private var appliedHotkeyState: HotkeySettingsCardState?
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
        updateCardHeightConstraints()
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
        let previousState = currentState
        guard previousState != state else { return }
        currentState = state

        let language = AppLanguagePreferencesStore.resolve(rawValue: state.appLanguageRaw)
        if previousState?.appLanguageRaw != state.appLanguageRaw {
            titleLabel.stringValue = AppStrings.text(
                .settingsPageTitle,
                language: language
            )
            subtitleLabel.stringValue = AppStrings.text(
                .settingsPageSubtitle,
                language: language
            )
            subtitleLabel.isHidden = subtitleLabel.stringValue.isEmpty
            subtitleLabel.invalidateIntrinsicContentSize()
            headerStack.invalidateIntrinsicContentSize()
            updateCardChrome(language: language)
        }

        let appearanceState = AppearanceSettingsCardState(
            showInCommandTab: state.showInCommandTab,
            themeModeRaw: state.themeModeRaw,
            appLanguageRaw: state.appLanguageRaw
        )
        if previousState.map(appearanceCardState(from:)) != appearanceState {
            appearanceContent.update(with: appearanceState)
            appearanceCard.invalidateIntrinsicContentSize()
        }

        let windowBehaviorState = WindowBehaviorSettingsCardState(
            windowLayerAutoEnterDelayText: state.windowLayerAutoEnterDelayText,
            autoRestoreMinimizedWindowOnSwitch:
                state.autoRestoreMinimizedWindowOnSwitch,
            hideMinimizedAppsFromAppLayer:
                state.hideMinimizedAppsFromAppLayer,
            appLanguageRaw: state.appLanguageRaw
        )
        if previousState.map(windowBehaviorCardState(from:))
            != windowBehaviorState
        {
            windowBehaviorContent.update(with: windowBehaviorState)
            windowBehaviorCard.invalidateIntrinsicContentSize()
        }

        let searchState = SearchSettingsCardState(
            searchEnabled: state.searchEnabled,
            searchDefaultScopeRaw: state.searchDefaultScopeRaw,
            appLanguageRaw: state.appLanguageRaw,
            accessibilityTrusted: state.accessibilityTrusted
        )
        if previousState.map(searchCardState(from:)) != searchState {
            searchContent.update(with: searchState)
            searchCard.invalidateIntrinsicContentSize()
        }

        let appVisibilityState = AppVisibilitySettingsCardState(
            hiddenAppCount: state.hiddenAppCount,
            appLanguageRaw: state.appLanguageRaw
        )
        if previousState.map(appVisibilityCardState(from:))
            != appVisibilityState
        {
            appVisibilityContent.update(with: appVisibilityState)
            appVisibilityCard.updateTitleAccessory(
                appVisibilityState.statusText,
                accessibilityIdentifier:
                    "flowtab.settings.app-visibility.effective-hidden-count",
                accessibilityValue: "\(appVisibilityState.hiddenAppCount)"
            )
            appVisibilityCard.invalidateIntrinsicContentSize()
        }

        let hotkeyState = hotkeyCardState(from: state)
        if appliedHotkeyState != hotkeyState {
            appliedHotkeyState = hotkeyState
            hotkeyContent.update(with: hotkeyState)
            hotkeyCard.invalidateIntrinsicContentSize()
        }

        let permissionState = PermissionSettingsCardState(
            showPermissionReminder: state.showPermissionReminder,
            allowLaunchAtLogin: state.allowLaunchAtLogin,
            accessibilityTrusted: state.accessibilityTrusted,
            screenCaptureTrusted: state.screenCaptureTrusted,
            appLanguageRaw: state.appLanguageRaw
        )
        if previousState.map(permissionCardState(from:)) != permissionState {
            permissionContent.update(with: permissionState)
            permissionCard.invalidateIntrinsicContentSize()
        }
        for stackView in [leftColumn, rightColumn, columnsStack, contentStack] {
            stackView.invalidateIntrinsicContentSize()
            stackView.needsLayout = true
        }
        notifyContentLayoutInvalidated()
    }

    func updateHotkeyContent(with values: AppKitSettingsHotkeyRawValues) {
        guard let currentState else { return }
        let hotkeyState = hotkeyCardState(
            from: currentState,
            overridingRawValuesWith: values
        )
        appliedHotkeyState = hotkeyState
        hotkeyContent.update(with: hotkeyState)
        hotkeyCard.invalidateIntrinsicContentSize()
        notifyContentLayoutInvalidated()
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
        guard targetSettingsAppearance.name != appearance.name
            || self.appearance?.name != appearance.name
        else {
            return
        }
        targetSettingsAppearance = appearance
        if self.appearance?.name != appearance.name {
            self.appearance = appearance
        }
        for subview in descendantViews(in: self) {
            if subview.appearance?.name != appearance.name {
                subview.appearance = appearance
            }
        }
        for view in descendantRefreshableViews(in: self) where view !== self {
            view.applySettingsAppearance(appearance)
        }
    }

    private func appearanceCardState(
        from state: AppKitSettingsPageState
    ) -> AppearanceSettingsCardState {
        AppearanceSettingsCardState(
            showInCommandTab: state.showInCommandTab,
            themeModeRaw: state.themeModeRaw,
            appLanguageRaw: state.appLanguageRaw
        )
    }

    private func windowBehaviorCardState(
        from state: AppKitSettingsPageState
    ) -> WindowBehaviorSettingsCardState {
        WindowBehaviorSettingsCardState(
            windowLayerAutoEnterDelayText:
                state.windowLayerAutoEnterDelayText,
            autoRestoreMinimizedWindowOnSwitch:
                state.autoRestoreMinimizedWindowOnSwitch,
            hideMinimizedAppsFromAppLayer:
                state.hideMinimizedAppsFromAppLayer,
            appLanguageRaw: state.appLanguageRaw
        )
    }

    private func searchCardState(
        from state: AppKitSettingsPageState
    ) -> SearchSettingsCardState {
        SearchSettingsCardState(
            searchEnabled: state.searchEnabled,
            searchDefaultScopeRaw: state.searchDefaultScopeRaw,
            appLanguageRaw: state.appLanguageRaw,
            accessibilityTrusted: state.accessibilityTrusted
        )
    }

    private func appVisibilityCardState(
        from state: AppKitSettingsPageState
    ) -> AppVisibilitySettingsCardState {
        AppVisibilitySettingsCardState(
            hiddenAppCount: state.hiddenAppCount,
            appLanguageRaw: state.appLanguageRaw
        )
    }

    private func permissionCardState(
        from state: AppKitSettingsPageState
    ) -> PermissionSettingsCardState {
        PermissionSettingsCardState(
            showPermissionReminder: state.showPermissionReminder,
            allowLaunchAtLogin: state.allowLaunchAtLogin,
            accessibilityTrusted: state.accessibilityTrusted,
            screenCaptureTrusted: state.screenCaptureTrusted,
            appLanguageRaw: state.appLanguageRaw
        )
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

    private func addCard(
        _ card: FlowSettingsCardView,
        to column: NSStackView
    ) {
        column.addArrangedSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        let heightConstraint = card.heightAnchor.constraint(
            equalToConstant: 0
        )
        cardHeightConstraints.append((card, heightConstraint))
    }

    private func updateCardHeightConstraints() {
        for binding in cardHeightConstraints {
            let height = binding.card.preferredLayoutHeight()
            guard abs(binding.constraint.constant - height) > 0.5 else {
                binding.constraint.isActive = true
                continue
            }
            binding.constraint.constant = height
            binding.constraint.isActive = true
        }
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

    private func notifyContentLayoutInvalidated() {
        invalidateMeasuredContentHeight()
        onContentLayoutInvalidated?()
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
