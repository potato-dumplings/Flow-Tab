import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HomeWindowRowButton: NSViewRepresentable {
    let title: String
    let subtitle: String
    let status: String
    let icon: NSImage?
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
            subtitle: subtitle,
            status: status,
            icon: icon,
            isSelected: isSelected,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }
}

final class HomeWindowRowButtonControl: NSButton {
    var onPress: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let statusPillView = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
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
        NSSize(width: NSView.noIntrinsicMetric, height: 44)
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
        "\(subtitleLabel.stringValue) \(statusLabel.stringValue)"
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
        subtitle: String,
        status: String,
        icon: NSImage?,
        isSelected: Bool,
        accessibilityIdentifier: String
    ) {
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        statusLabel.stringValue = status
        iconView.image = icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
        isSelectedRow = isSelected
        setAccessibilityIdentifier(accessibilityIdentifier)
        setAccessibilityLabel(title)
        setAccessibilityValue("\(subtitle) \(status)")
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

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 5
        iconView.layer?.masksToBounds = true
        iconView.setAccessibilityElement(false)

        configure(label: titleLabel)
        configure(label: subtitleLabel)
        configure(label: statusLabel)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.alignment = .center
        statusPillView.translatesAutoresizingMaskIntoConstraints = false
        statusPillView.wantsLayer = true
        statusPillView.setAccessibilityElement(false)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusPillView.setContentHuggingPriority(.required, for: .horizontal)
        statusPillView.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(statusPillView)
        statusPillView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusPillView.leadingAnchor, constant: -8),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusPillView.leadingAnchor, constant: -8),

            statusPillView.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor,
                constant: 8
            ),
            statusPillView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            statusPillView.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusPillView.heightAnchor.constraint(equalToConstant: 24),
            statusPillView.widthAnchor.constraint(greaterThanOrEqualToConstant: 58),

            statusLabel.leadingAnchor.constraint(equalTo: statusPillView.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: statusPillView.trailingAnchor, constant: -10),
            statusLabel.centerYAnchor.constraint(equalTo: statusPillView.centerYAnchor)
        ])

        layer?.cornerRadius = 8
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
        subtitleLabel.textColor = .secondaryLabelColor
        statusLabel.textColor = statusTextColor(isDark: isDark)
        statusPillView.layer?.backgroundColor = statusBackgroundColor(isDark: isDark).cgColor
        statusPillView.layer?.cornerRadius = 8
        statusPillView.layer?.masksToBounds = true
    }

    private func statusTextColor(isDark: Bool) -> NSColor {
        if isSelectedRow {
            return .white
        }
        return isDark ? .secondaryLabelColor : .labelColor.withAlphaComponent(0.68)
    }

    private func statusBackgroundColor(isDark: Bool) -> NSColor {
        if isSelectedRow {
            return NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.64 : 0.78)
        }
        return NSColor.labelColor.withAlphaComponent(isDark ? 0.12 : 0.07)
    }

    @objc private func handlePress(_: NSButton) {
        onPress?()
    }
}
