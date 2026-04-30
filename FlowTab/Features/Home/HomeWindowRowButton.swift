import AppKit
import SwiftUI

struct HomeWindowRowButton: NSViewRepresentable {
    let title: String
    let trailing: String
    let isSelected: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    func makeNSView(context _: Context) -> HomeWindowRowButtonControl {
        let button = HomeWindowRowButtonControl()
        button.onPress = action
        return button
    }

    func updateNSView(_ button: HomeWindowRowButtonControl, context _: Context) {
        button.onPress = action
        button.update(
            title: title,
            trailing: trailing,
            isSelected: isSelected,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }
}

final class HomeWindowRowButtonControl: NSButton {
    var onPress: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let trailingLabel = NSTextField(labelWithString: "")
    private var isSelectedRow = false
    private var isHovering = false
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 34)
    }

    override var isHighlighted: Bool {
        didSet { updateAppearance() }
    }

    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }

    override func accessibilityLabel() -> String? {
        titleLabel.stringValue
    }

    override func accessibilityValue() -> Any? {
        trailingLabel.stringValue
    }

    override func accessibilityChildren() -> [Any]? {
        []
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
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
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard isEnabled else { return }
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
        updateAppearance()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled, bounds.contains(point) else { return nil }
        return self
    }

    func update(
        title: String,
        trailing: String,
        isSelected: Bool,
        accessibilityIdentifier: String
    ) {
        titleLabel.stringValue = title
        trailingLabel.stringValue = trailing
        isSelectedRow = isSelected
        setAccessibilityIdentifier(accessibilityIdentifier)
        setAccessibilityLabel(title)
        setAccessibilityValue(trailing)
        updateAppearance()
    }

    private func buildViewHierarchy() {
        wantsLayer = true
        isBordered = false
        focusRingType = .none
        title = ""
        image = nil
        imagePosition = .noImage
        setButtonType(.momentaryPushIn)
        setAccessibilityElement(true)
        target = self
        action = #selector(handlePress(_:))

        configure(label: titleLabel)
        configure(label: trailingLabel)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        trailingLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        trailingLabel.alignment = .right
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        trailingLabel.setContentHuggingPriority(.required, for: .horizontal)
        trailingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(titleLabel)
        addSubview(trailingLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor,
                constant: 8
            ),
            trailingLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            trailingLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        layer?.cornerRadius = 9
        layer?.masksToBounds = true
        updateAppearance()
    }

    private func configure(label: NSTextField) {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setAccessibilityElement(false)
    }

    private func updateAppearance() {
        guard let layer else { return }
        let isDark = effectiveAppearance.isFlowTabDarkInterface

        let backgroundColor: NSColor
        if isHighlighted {
            backgroundColor = NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.24 : 0.18)
        } else if isSelectedRow {
            backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16)
        } else if isHovering && isEnabled {
            backgroundColor = NSColor.labelColor.withAlphaComponent(isDark ? 0.10 : 0.07)
        } else {
            backgroundColor = NSColor.labelColor.withAlphaComponent(isDark ? 0.08 : 0.04)
        }

        layer.backgroundColor = backgroundColor.cgColor
        titleLabel.textColor = isEnabled ? .labelColor : .secondaryLabelColor
        trailingLabel.textColor = .secondaryLabelColor
    }

    @objc private func handlePress(_: NSButton) {
        onPress?()
    }
}
