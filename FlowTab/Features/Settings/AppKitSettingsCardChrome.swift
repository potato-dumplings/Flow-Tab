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
        NSSize(width: NSView.noIntrinsicMetric, height: preferredLayoutHeight())
    }

    override func layout() {
        let needsSecondLayoutPass = updateDirectWrappingLabelWidths()
        super.layout()
        if needsSecondLayoutPass {
            super.layout()
        }
    }

    func preferredLayoutHeight() -> CGFloat {
        updateDirectWrappingLabelWidths()
        return FlowSettingsLayoutMetrics.preferredStackHeight(stackView)
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
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
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
        selectControl: FlowSettingsSelectControl,
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
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        let minimumConstraint = control.widthAnchor.constraint(
            greaterThanOrEqualToConstant: max(width, minimumWidth)
        )
        minimumConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([minimumConstraint])
    }

    static func selectItem(in selectControl: FlowSettingsSelectControl, rawValue: String) {
        selectControl.updateSelection(id: rawValue)
    }

    @discardableResult
    private func updateDirectWrappingLabelWidths() -> Bool {
        let availableWidth = stackView.bounds.width > 0 ? stackView.bounds.width : bounds.width
        guard availableWidth > 0 else { return false }

        var didUpdate = false
        for case let label as NSTextField in stackView.arrangedSubviews
            where label.maximumNumberOfLines != 1
        {
            let preferredWidth = floor(availableWidth)
            guard abs(label.preferredMaxLayoutWidth - preferredWidth) > 0.5 else { continue }
            label.preferredMaxLayoutWidth = preferredWidth
            label.invalidateIntrinsicContentSize()
            didUpdate = true
        }
        return didUpdate
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
        titleLabel.maximumNumberOfLines = 1
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
