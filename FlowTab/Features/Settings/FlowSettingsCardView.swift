import AppKit

enum FlowSettingsLayoutMetrics {
    static func preferredStackHeight(_ stackView: NSStackView) -> CGFloat {
        let visibleSubviews = stackView.arrangedSubviews.filter { !$0.isHidden }
        guard !visibleSubviews.isEmpty else { return 0 }

        switch stackView.orientation {
        case .horizontal:
            return ceil(visibleSubviews.map { preferredHeight(for: $0) }.max() ?? 0)
        case .vertical:
            let contentHeight = visibleSubviews
                .map { preferredHeight(for: $0) }
                .reduce(0, +)
            return ceil(contentHeight + stackView.spacing * CGFloat(visibleSubviews.count - 1))
        @unknown default:
            return ceil(stackView.fittingSize.height)
        }
    }

    static func preferredHeight(for view: NSView) -> CGFloat {
        if let cardView = view as? FlowSettingsCardView {
            return cardView.preferredLayoutHeight()
        }
        if let cardBaseView = view as? AppKitSettingsCardBaseView {
            return cardBaseView.preferredLayoutHeight()
        }
        if let stackView = view as? NSStackView {
            return preferredStackHeight(stackView)
        }
        let intrinsicHeight = view.intrinsicContentSize.height
        if intrinsicHeight != NSView.noIntrinsicMetric, intrinsicHeight.isFinite {
            return ceil(intrinsicHeight)
        }
        return ceil(view.fittingSize.height)
    }
}

final class FlowSettingsCardView: NSView, FlowSettingsAppearanceRefreshable {
    private let stackView = NSStackView()
    private let titleRow = NSStackView()
    private let titleLabel: NSTextField
    private let subtitleLabel: NSTextField
    private let titleAccessoryLabel = NSTextField(labelWithString: "")
    private let contentPadding = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
    private var targetAppearance = FlowSettingsStyleResolver.defaultAppearance

    init(title: String, subtitle: String?, contentView: NSView) {
        titleLabel = NSTextField(labelWithString: title)
        subtitleLabel = NSTextField(labelWithString: subtitle ?? "")
        super.init(frame: .zero)
        subtitleLabel.isHidden = subtitle?.isEmpty ?? true
        buildViewHierarchy(contentView: contentView)
    }

    required init?(coder: NSCoder) {
        titleLabel = NSTextField(labelWithString: "")
        subtitleLabel = NSTextField(labelWithString: "")
        super.init(coder: coder)
        buildViewHierarchy(contentView: NSView())
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: preferredLayoutHeight()
        )
    }

    override func layout() {
        super.layout()
        layer?.frame = bounds
        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: layer?.cornerRadius ?? 0,
            cornerHeight: layer?.cornerRadius ?? 0,
            transform: nil
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshStyle()
    }

    func updateTitleAccessory(_ text: String?) {
        titleAccessoryLabel.stringValue = text ?? ""
        titleAccessoryLabel.isHidden = text?.isEmpty ?? true
        invalidateIntrinsicContentSize()
    }

    func updateChrome(title: String, subtitle: String?) {
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.isHidden = subtitle?.isEmpty ?? true
        invalidateIntrinsicContentSize()
    }

    func preferredLayoutHeight() -> CGFloat {
        FlowSettingsLayoutMetrics.preferredStackHeight(stackView) + contentPadding.top + contentPadding.bottom
    }

    func applySettingsAppearance(_ appearance: NSAppearance) {
        targetAppearance = appearance
        refreshStyle()
    }

    func refreshStyle() {
        wantsLayer = true
        guard let layer else { return }
        let surface = FlowSettingsSurfaceToken(
            fill: .color(.rgb(
                light: FlowSettingsRGBColor(red: 0.965, green: 0.97, blue: 0.978, alpha: 1),
                dark: FlowSettingsRGBColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 0.96)
            )),
            borderColor: .rgb(
                light: FlowSettingsRGBColor(red: 0, green: 0, blue: 0, alpha: 0.14),
                dark: FlowSettingsRGBColor(red: 1, green: 1, blue: 1, alpha: 0.10)
            ),
            borderWidth: 1,
            cornerRadius: 12,
            shadow: targetAppearance.isFlowTabDarkInterface
                ? nil
                : FlowSettingsShadowToken(color: .absoluteBlack(alpha: 0.05), opacity: 1, radius: 6, offset: CGSize(width: 0, height: 2))
        )
        FlowSettingsStyleResolver.apply(surface: surface, to: layer, appearance: targetAppearance)
    }

    private func buildViewHierarchy(contentView: NSView) {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        titleLabel.font = FlowTypography.appKit(.cardTitle)
        subtitleLabel.font = FlowTypography.appKit(.cardSubtitle)
        subtitleLabel.textColor = .secondaryLabelColor
        titleAccessoryLabel.font = FlowTypography.appKit(.controlText)
        titleAccessoryLabel.textColor = .secondaryLabelColor

        titleRow.orientation = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = 12
        titleRow.detachesHiddenViews = true
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.addArrangedSubview(titleLabel)
        titleRow.addArrangedSubview(titleAccessoryLabel)

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.detachesHiddenViews = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        stackView.addArrangedSubview(titleRow)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(contentView)
        titleRow.widthAnchor.constraint(lessThanOrEqualTo: stackView.widthAnchor).isActive = true
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.setContentHuggingPriority(.required, for: .vertical)
        contentView.setContentCompressionResistancePriority(.required, for: .vertical)
        contentView.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentPadding.left),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: contentPadding.top),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentPadding.right),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -contentPadding.bottom)
        ])
        refreshStyle()
    }

}
