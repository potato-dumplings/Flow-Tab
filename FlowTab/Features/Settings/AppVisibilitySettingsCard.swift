import AppKit

struct AppVisibilitySettingsCardState: Equatable {
    let hiddenAppCount: Int
    let appLanguageRaw: String

    var language: AppLanguage {
        AppLanguagePreferencesStore.resolve(rawValue: appLanguageRaw)
    }

    var statusText: String {
        AppStrings.hiddenAppCount(hiddenAppCount, language: language)
    }

    var summaryText: String {
        AppStrings.text(.appVisibilitySummary, language: language)
    }
}

final class AppVisibilitySettingsCardAppKitView: AppKitSettingsCardBaseView {
    var onManageAppVisibility: (() -> Void)?

    private let summaryLabel = AppKitSettingsCardBaseView.makeBodyLabel(.body)
    private let manageButton = FlowCompactActionButtonControl()
    private var currentState: AppVisibilitySettingsCardState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override var intrinsicContentSize: NSSize {
        updateSummaryPreferredWidth()
        return super.intrinsicContentSize
    }

    override func layout() {
        updateSummaryPreferredWidth()
        super.layout()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshManageButtonAppearance()
    }

    func update(with state: AppVisibilitySettingsCardState) {
        guard currentState != state else { return }
        currentState = state
        summaryLabel.stringValue = state.summaryText
        refreshManageButtonAppearance()
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        manageButton.target = self
        manageButton.action = #selector(handleManagePressed)
        manageButton.setFlowTabTestingIdentifier("flowtab.settings.app-visibility.manage")
        manageButton.configure(
            title: AppStrings.text(.appVisibilityManage),
            accessibilityLabel: AppStrings.text(.appVisibilityManage),
            presentation: .compact(targetAppearance: effectiveAppearance)
        )

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [summaryLabel, spacer, manageButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.detachesHiddenViews = true
        row.translatesAutoresizingMaskIntoConstraints = false

        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        manageButton.setContentHuggingPriority(.required, for: .horizontal)
        manageButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        addFullWidthArrangedSubview(row)
    }

    private func updateSummaryPreferredWidth() {
        guard bounds.width > 0 else { return }
        let buttonWidth = max(manageButton.fittingSize.width, manageButton.intrinsicContentSize.width)
        let preferredWidth = max(0, bounds.width - buttonWidth - 12)
        guard abs(summaryLabel.preferredMaxLayoutWidth - preferredWidth) > 0.5 else { return }
        summaryLabel.preferredMaxLayoutWidth = preferredWidth
        summaryLabel.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
    }

    private func refreshManageButtonAppearance() {
        let title = currentState.map { AppStrings.text(.appVisibilityManage, language: $0.language) }
            ?? AppStrings.text(.appVisibilityManage)
        manageButton.configure(
            title: title,
            accessibilityLabel: title,
            presentation: .compact(targetAppearance: effectiveAppearance)
        )
    }

    @objc private func handleManagePressed() {
        onManageAppVisibility?()
    }
}
