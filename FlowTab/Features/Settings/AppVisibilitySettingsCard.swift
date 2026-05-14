import AppKit

struct AppVisibilitySettingsCardState: Equatable {
    let hiddenAppCount: Int

    var summaryText: String {
        AppStrings.text(
            .appVisibilitySummary,
            replacements: ["count": "\(hiddenAppCount)"]
        )
    }
}

final class AppVisibilitySettingsCardAppKitView: AppKitSettingsCardBaseView {
    var onManageAppVisibility: (() -> Void)?

    private let summaryLabel = AppKitSettingsCardBaseView.makeBodyLabel()
    private let manageButton = NSButton(title: AppStrings.text(.appVisibilityManage), target: nil, action: nil)
    private var currentState: AppVisibilitySettingsCardState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    func update(with state: AppVisibilitySettingsCardState) {
        guard currentState != state else { return }
        currentState = state
        summaryLabel.stringValue = state.summaryText
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        manageButton.bezelStyle = .rounded
        manageButton.controlSize = .regular
        manageButton.target = self
        manageButton.action = #selector(handleManagePressed)
        manageButton.setFlowTabTestingIdentifier("flowtab.settings.app-visibility.manage")

        let row = NSStackView(views: [summaryLabel, manageButton])
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

    @objc private func handleManagePressed() {
        onManageAppVisibility?()
    }
}
