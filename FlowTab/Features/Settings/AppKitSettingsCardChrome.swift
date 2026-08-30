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

    static func makeControlRow(
        title: String,
        control: NSView,
        validationIdentifier: String? = nil
    ) -> AppKitSettingsControlRow {
        AppKitSettingsControlRow(
            title: title,
            control: control,
            validationIdentifier: validationIdentifier
        )
    }

    static func makeBodyLabel(_ token: FlowTypography.Token = .cardSubtitle) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = FlowTypography.appKit(token)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    static func makeStatusLabel(_ token: FlowTypography.Token = .body) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = FlowTypography.appKit(token)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    static func configure(
        selectControl: FlowSettingsSelectControl,
        options: [(id: String, title: String)],
        placementPreference: FlowDropdownPlacementPreference = .defaultBelow
    ) {
        selectControl.configure(options: options, placementPreference: placementPreference)
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
    private let control: NSView
    private let controlRow = NSStackView()
    private let validationContainer = NSView()
    private let validationLabel = AppKitSettingsCardBaseView.makeStatusLabel(.micro)

    init(
        title: String,
        control: NSView,
        validationIdentifier: String? = nil
    ) {
        self.control = control
        super.init(frame: .zero)
        buildViewHierarchy(validationIdentifier: validationIdentifier)
        updateTitle(title)
    }

    required init?(coder: NSCoder) {
        control = NSView()
        super.init(coder: coder)
        buildViewHierarchy(validationIdentifier: nil)
    }

    func updateTitle(_ title: String) {
        guard titleLabel.stringValue != title else { return }
        titleLabel.stringValue = title
        invalidateIntrinsicContentSize()
    }

    func updateValidationMessage(_ message: String?) {
        let resolvedMessage = message.flatMap { $0.isEmpty ? nil : $0 }
        guard validationLabel.stringValue != (resolvedMessage ?? "")
            || validationLabel.isHidden != (resolvedMessage == nil)
        else {
            return
        }
        validationLabel.stringValue = resolvedMessage ?? ""
        validationLabel.isHidden = resolvedMessage == nil
        validationContainer.isHidden = resolvedMessage == nil
        control.setAccessibilityHelp(resolvedMessage)
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy(validationIdentifier: String?) {
        titleLabel.font = FlowTypography.appKit(.formLabel)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        controlRow.orientation = .horizontal
        controlRow.alignment = .centerY
        controlRow.spacing = 10
        controlRow.detachesHiddenViews = true
        controlRow.translatesAutoresizingMaskIntoConstraints = false
        controlRow.addArrangedSubview(titleLabel)
        controlRow.addArrangedSubview(spacer)
        controlRow.addArrangedSubview(control)

        validationLabel.textColor = .systemRed
        validationLabel.alignment = .center
        validationLabel.isHidden = true
        validationLabel.translatesAutoresizingMaskIntoConstraints = false
        if let validationIdentifier {
            validationLabel.setFlowTabTestingIdentifier(validationIdentifier)
        }
        validationContainer.isHidden = true
        validationContainer.translatesAutoresizingMaskIntoConstraints = false
        validationContainer.addSubview(validationLabel)

        orientation = .vertical
        alignment = .leading
        spacing = 4
        detachesHiddenViews = true
        translatesAutoresizingMaskIntoConstraints = false
        addArrangedSubview(controlRow)
        addArrangedSubview(validationContainer)

        NSLayoutConstraint.activate([
            controlRow.widthAnchor.constraint(equalTo: widthAnchor),
            validationContainer.widthAnchor.constraint(equalTo: widthAnchor),
            validationLabel.leadingAnchor.constraint(equalTo: control.leadingAnchor),
            validationLabel.trailingAnchor.constraint(equalTo: control.trailingAnchor),
            validationLabel.topAnchor.constraint(equalTo: validationContainer.topAnchor),
            validationLabel.bottomAnchor.constraint(equalTo: validationContainer.bottomAnchor)
        ])
    }
}

extension NSAppearance {
    var isFlowTabDarkInterface: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
