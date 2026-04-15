import AppKit

final class SpaceFixtureWindowContentView: NSView {
    private let plan: SpaceFixtureWindowPlan
    private let workflowReadyLabel = NSTextField(labelWithString: SpaceFixtureWorkflowStatus.launchingText)
    private let workflowSummaryLabel = NSTextField(labelWithString: "")

    init(plan: SpaceFixtureWindowPlan) {
        self.plan = plan
        super.init(frame: .zero)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(
            calibratedRed: 0.93,
            green: 0.96,
            blue: 0.99,
            alpha: 1
        ).cgColor

        let stackView = NSStackView(views: [
            makeLabel(
                text: plan.title,
                font: .systemFont(ofSize: 30, weight: .semibold),
                textColor: .labelColor,
                identifier: plan.titleAccessibilityIdentifier
            ),
            makeLabel(
                text: plan.subtitleText,
                font: .systemFont(ofSize: 16, weight: .medium),
                textColor: .secondaryLabelColor,
                identifier: plan.subtitleAccessibilityIdentifier
            ),
            makeLabel(
                text: plan.modeText,
                font: .systemFont(ofSize: 16, weight: .bold),
                textColor: .labelColor,
                identifier: plan.modeAccessibilityIdentifier
            ),
            workflowReadyLabel,
            workflowSummaryLabel
        ])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 32),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -32)
        ])

        identifier = NSUserInterfaceItemIdentifier(plan.rootAccessibilityIdentifier)
        setAccessibilityIdentifier(plan.rootAccessibilityIdentifier)
        setAccessibilityElement(false)

        // XCTest does not reliably expose every NSWindow subtree once multiple
        // windows reorder or move into fullscreen Spaces, so mirror launch
        // readiness into shared labels that any visible fixture window can expose.
        configureWorkflowLabels()
    }

    private func makeLabel(
        text: String,
        font: NSFont,
        textColor: NSColor,
        identifier: String
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = textColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.identifier = NSUserInterfaceItemIdentifier(identifier)
        label.setAccessibilityIdentifier(identifier)
        label.setAccessibilityLabel(text)
        label.setAccessibilityValue(text)
        label.setAccessibilityElement(true)
        return label
    }

    func updateWorkflowReadiness(windowTitles: [String]) {
        applyText(SpaceFixtureWorkflowStatus.readyText, to: workflowReadyLabel)
        applyText(
            SpaceFixtureWorkflowStatus.summaryText(for: windowTitles),
            to: workflowSummaryLabel
        )
    }

    private func configureWorkflowLabels() {
        workflowReadyLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        workflowReadyLabel.textColor = .secondaryLabelColor
        workflowReadyLabel.identifier = NSUserInterfaceItemIdentifier(
            SpaceFixtureWorkflowStatus.readyAccessibilityIdentifier
        )
        workflowReadyLabel.setAccessibilityIdentifier(
            SpaceFixtureWorkflowStatus.readyAccessibilityIdentifier
        )
        workflowReadyLabel.setAccessibilityElement(true)
        applyText(SpaceFixtureWorkflowStatus.launchingText, to: workflowReadyLabel)

        workflowSummaryLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        workflowSummaryLabel.textColor = .secondaryLabelColor
        workflowSummaryLabel.lineBreakMode = .byTruncatingTail
        workflowSummaryLabel.maximumNumberOfLines = 1
        workflowSummaryLabel.identifier = NSUserInterfaceItemIdentifier(
            SpaceFixtureWorkflowStatus.summaryAccessibilityIdentifier
        )
        workflowSummaryLabel.setAccessibilityIdentifier(
            SpaceFixtureWorkflowStatus.summaryAccessibilityIdentifier
        )
        workflowSummaryLabel.setAccessibilityElement(true)
        applyText("", to: workflowSummaryLabel)
    }

    private func applyText(_ text: String, to label: NSTextField) {
        label.stringValue = text
        label.setAccessibilityLabel(text)
        label.setAccessibilityValue(text)
    }
}
