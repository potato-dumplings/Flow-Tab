import AppKit

extension NSView {
    func preferredFittingSize(forWidth width: CGFloat?) -> CGSize {
        let widthConstraint: NSLayoutConstraint?
        let normalizedWidth = width.flatMap { proposedWidth -> CGFloat? in
            guard proposedWidth.isFinite, proposedWidth > 0 else { return nil }
            return proposedWidth
        }

        if let normalizedWidth {
            // SwiftUI may pass `.infinity`/`nan` during measurement; AppKit crashes if that becomes a constraint constant.
            widthConstraint = widthAnchor.constraint(equalToConstant: normalizedWidth)
            widthConstraint?.priority = .defaultHigh
            widthConstraint?.isActive = true
        } else {
            widthConstraint = nil
        }

        layoutSubtreeIfNeeded()
        let fitted = fittingSize
        widthConstraint?.isActive = false
        return fitted
    }
}

final class FlowSoftTextField: NSView {
    let textField = NSTextField(string: "")

    private var isEditing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 72, height: 28)
    }

    override func layout() {
        super.layout()
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func setEditing(_ editing: Bool) {
        guard isEditing != editing else { return }
        isEditing = editing
        updateAppearance()
    }

    private func buildViewHierarchy() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        widthAnchor.constraint(equalToConstant: 72).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isBezeled = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.placeholderString = "0.75"
        textField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textField.alignment = .center
        textField.setContentHuggingPriority(.required, for: .vertical)
        textField.setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.heightAnchor.constraint(equalToConstant: 16)
        ])

        updateAppearance()
    }

    private func updateAppearance() {
        guard let layer else { return }

        let isDark = effectiveAppearance.isFlowTabDarkInterface
        let borderColor: NSColor
        let backgroundColor: NSColor

        if isEditing {
            borderColor = .controlAccentColor.withAlphaComponent(isDark ? 0.55 : 0.35)
            backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.10)
                : NSColor.white.withAlphaComponent(0.98)
            layer.shadowColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = 5
            layer.shadowOffset = .zero
        } else {
            borderColor = isDark
                ? NSColor.white.withAlphaComponent(0.10)
                : NSColor.black.withAlphaComponent(0.08)
            backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.05)
                : NSColor.white.withAlphaComponent(0.84)
            layer.shadowOpacity = 0
        }

        layer.cornerRadius = 9
        layer.borderWidth = 1
        layer.borderColor = borderColor.cgColor
        layer.backgroundColor = backgroundColor.cgColor
    }
}
