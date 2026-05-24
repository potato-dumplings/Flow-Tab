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

    private let summaryLabel = AppKitSettingsCardBaseView.makeBodyLabel(fontSize: 12)
    private let manageButton = AppVisibilityManageButton(title: AppStrings.text(.appVisibilityManage))
    private let manageButtonContainer = NSView()
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
        manageButton.updateTitle(AppStrings.text(.appVisibilityManage, language: state.language))
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        manageButton.target = self
        manageButton.action = #selector(handleManagePressed)
        manageButton.setFlowTabTestingIdentifier("flowtab.settings.app-visibility.manage")
        manageButtonContainer.translatesAutoresizingMaskIntoConstraints = false
        manageButtonContainer.addSubview(manageButton)
        NSLayoutConstraint.activate([
            manageButton.topAnchor.constraint(equalTo: manageButtonContainer.topAnchor, constant: -14),
            manageButton.leadingAnchor.constraint(equalTo: manageButtonContainer.leadingAnchor),
            manageButton.trailingAnchor.constraint(equalTo: manageButtonContainer.trailingAnchor),
            manageButtonContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 68),
            manageButtonContainer.heightAnchor.constraint(equalToConstant: 18)
        ])

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [summaryLabel, spacer, manageButtonContainer])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.detachesHiddenViews = true
        row.translatesAutoresizingMaskIntoConstraints = false

        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        manageButtonContainer.setContentHuggingPriority(.required, for: .horizontal)
        manageButtonContainer.setContentCompressionResistancePriority(.required, for: .horizontal)

        addFullWidthArrangedSubview(row)
    }

    @objc private func handleManagePressed() {
        onManageAppVisibility?()
    }
}

private final class AppVisibilityManageButton: NSButton {
    private var isHovering = false
    private var hoverTrackingArea: NSTrackingArea?
    private var buttonTitle: String

    init(title: String) {
        buttonTitle = title
        super.init(frame: .zero)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        buttonTitle = AppStrings.text(.appVisibilityManage)
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(68, ceil(attributedTitle.size().width) + 28), height: 32)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func updateTitle(_ title: String) {
        buttonTitle = title
        updateAppearance()
        invalidateIntrinsicContentSize()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
        updateAppearance()
    }

    private func buildViewHierarchy() {
        wantsLayer = true
        isBordered = false
        focusRingType = .none
        alignment = .center
        imagePosition = .noImage
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        widthAnchor.constraint(equalToConstant: 68).isActive = true
        heightAnchor.constraint(equalToConstant: 32).isActive = true
        updateAppearance()
    }

    private func updateAppearance() {
        guard let layer else { return }
        let isDark = effectiveAppearance.isFlowTabDarkInterface
        let baseAlpha: CGFloat = isHovering ? 1 : 0.96

        if isDark {
            layer.backgroundColor = NSColor.white.withAlphaComponent(isHovering ? 0.18 : 0.12).cgColor
            layer.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
            layer.shadowOpacity = 0
        } else {
            layer.backgroundColor = NSColor.white.withAlphaComponent(baseAlpha).cgColor
            layer.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
            layer.shadowColor = NSColor.black.withAlphaComponent(0.05).cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = 3
            layer.shadowOffset = CGSize(width: 0, height: 1)
        }

        layer.cornerRadius = 8
        layer.borderWidth = 1
        attributedTitle = NSAttributedString(
            string: buttonTitle,
            attributes: [
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    return style
                }(),
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor.withAlphaComponent(isDark ? 0.78 : 0.72)
            ]
        )
    }
}
