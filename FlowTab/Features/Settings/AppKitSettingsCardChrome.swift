import AppKit
import SwiftUI

protocol AppKitSettingsCardStateView: AnyObject {
    associatedtype CardState

    func update(with state: CardState)
}

protocol AppKitSettingsCardRepresentable: NSViewRepresentable
where NSViewType: NSView & AppKitSettingsCardStateView {
    func makeCardView(context: Context) -> NSViewType
    func updateCoordinator(_ coordinator: Coordinator)
    func connect(_ view: NSViewType, coordinator: Coordinator)
    func makeState() -> NSViewType.CardState
}

extension AppKitSettingsCardRepresentable {
    func makeNSView(context: Context) -> NSViewType {
        let view = makeCardView(context: context)
        connect(view, coordinator: context.coordinator)
        return view
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSViewType,
        context _: Context
    ) -> CGSize? {
        nsView.preferredFittingSize(forWidth: proposal.width)
    }

    func updateNSView(_ nsView: NSViewType, context: Context) {
        updateCoordinator(context.coordinator)
        connect(nsView, coordinator: context.coordinator)
        nsView.update(with: makeState())
    }
}

class AppKitSettingsCardBaseView: NSView {
    let stackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureRootStack()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureRootStack()
    }

    override var intrinsicContentSize: NSSize {
        layoutSubtreeIfNeeded()
        return NSSize(width: NSView.noIntrinsicMetric, height: stackView.fittingSize.height)
    }

    func addFullWidthArrangedSubview(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        stackView.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    private func configureRootStack() {
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.detachesHiddenViews = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.setContentHuggingPriority(.required, for: .vertical)
        stackView.setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    static func makeControlRow(title: String, control: NSView) -> AppKitSettingsControlRow {
        AppKitSettingsControlRow(title: title, control: control)
    }

    static func makeBodyLabel(fontSize: CGFloat = 11) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: fontSize)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    static func makeStatusLabel(fontSize: CGFloat = 12) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: fontSize)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    static func configure(
        selectControl: FlowFormSelectControl,
        options: [(id: String, title: String)],
        width: CGFloat
    ) {
        selectControl.configure(options: options)
        applyPreferredControlWidth(selectControl, width: width)
    }

    static func applyPreferredControlWidth(
        _ control: NSView,
        width: CGFloat,
        minimumWidth: CGFloat = 68
    ) {
        let maximumWidth = control.widthAnchor.constraint(lessThanOrEqualToConstant: width)
        let preferredWidth = control.widthAnchor.constraint(equalToConstant: width)
        let minimumWidth = control.widthAnchor.constraint(greaterThanOrEqualToConstant: minimumWidth)
        preferredWidth.priority = .defaultHigh
        minimumWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([maximumWidth, preferredWidth, minimumWidth])
    }

    static func selectItem(in selectControl: FlowFormSelectControl, rawValue: String) {
        selectControl.updateSelection(id: rawValue)
    }

}

final class AppKitSettingsControlRow: NSStackView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let spacer = NSView()

    init(title: String, control: NSView) {
        super.init(frame: .zero)
        buildViewHierarchy(control: control)
        updateTitle(title)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy(control: NSView())
    }

    func updateTitle(_ title: String) {
        titleLabel.stringValue = title
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy(control: NSView) {
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        orientation = .horizontal
        alignment = .centerY
        spacing = 10
        detachesHiddenViews = true
        translatesAutoresizingMaskIntoConstraints = false
        addArrangedSubview(titleLabel)
        addArrangedSubview(spacer)
        addArrangedSubview(control)
    }
}

extension NSAppearance {
    var isFlowTabDarkInterface: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

final class AppKitSectionCardView: NSView {
    private let stackView = NSStackView()
    private let titleRow = NSStackView()
    private let titleLabel: NSTextField
    private let subtitleLabel: NSTextField
    private let titleAccessoryLabel = NSTextField(labelWithString: "")
    private let verticalInset: CGFloat = 14

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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func layout() {
        super.layout()
        updateAppearance()
    }

    override var intrinsicContentSize: NSSize {
        layoutSubtreeIfNeeded()
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: stackView.fittingSize.height + verticalInset * 2
        )
    }

    private func buildViewHierarchy(contentView: NSView) {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        titleAccessoryLabel.font = .systemFont(ofSize: 13)
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
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: verticalInset),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -verticalInset)
        ])

        updateAppearance()
    }

    private func updateAppearance() {
        guard let layer else { return }
        if effectiveAppearance.isFlowTabDarkInterface {
            layer.backgroundColor = NSColor(
                red: 0.13,
                green: 0.13,
                blue: 0.15,
                alpha: 0.96
            ).cgColor
            layer.borderColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
            layer.shadowOpacity = 0
        } else {
            layer.backgroundColor = NSColor(
                red: 0.965,
                green: 0.97,
                blue: 0.978,
                alpha: 1
            ).cgColor
            layer.borderColor = NSColor.black.withAlphaComponent(0.14).cgColor
            layer.shadowColor = NSColor.black.withAlphaComponent(0.05).cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = 6
            layer.shadowOffset = CGSize(width: 0, height: 2)
        }
        layer.cornerRadius = 12
        layer.borderWidth = 1
    }
}
