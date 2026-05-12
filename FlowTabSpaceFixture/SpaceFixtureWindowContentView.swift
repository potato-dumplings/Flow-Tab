import AppKit

final class SpaceFixtureWindowContentView: NSView {
    private let plan: SpaceFixtureWindowPlan
    private let contentTopInset: CGFloat
    private let workflowReadyLabel = NSTextField(labelWithString: SpaceFixtureWorkflowStatus.launchingText)
    private let workflowSummaryLabel = NSTextField(labelWithString: "")

    init(plan: SpaceFixtureWindowPlan, contentTopInset: CGFloat = 32) {
        self.plan = plan
        self.contentTopInset = contentTopInset
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

        let arrangedViews: [NSView] = [
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
            )
        ] + tabViews() + [
            workflowReadyLabel,
            workflowSummaryLabel
        ]

        let stackView = NSStackView(views: arrangedViews)
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: contentTopInset),
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

    private func tabViews() -> [NSView] {
        guard plan.tabs.isEmpty == false else { return [] }

        let sectionLabel = makeLabel(
            text: "Tabs",
            font: .systemFont(ofSize: 12, weight: .semibold),
            textColor: .secondaryLabelColor,
            identifier: plan.tabStripAccessibilityIdentifier
        )

        let tabStrip = NSStackView()
        tabStrip.orientation = .horizontal
        tabStrip.alignment = .centerY
        tabStrip.spacing = 10
        tabStrip.translatesAutoresizingMaskIntoConstraints = false

        for (offset, tab) in plan.tabs.enumerated() {
            tabStrip.addArrangedSubview(makeTabLabel(tab, tabIndex: offset + 1))
        }

        if let selectedTabTitle = plan.selectedTabTitle {
            let selectedTabLabel = makeLabel(
                text: "Selected Tab: \(selectedTabTitle)",
                font: .systemFont(ofSize: 12, weight: .medium),
                textColor: .secondaryLabelColor,
                identifier: plan.selectedTabAccessibilityIdentifier
            )
            return [sectionLabel, tabStrip, selectedTabLabel]
        }

        return [sectionLabel, tabStrip]
    }

    private func makeTabLabel(
        _ tab: SpaceFixtureConfiguredTab,
        tabIndex: Int
    ) -> NSTextField {
        let label = NSTextField(labelWithString: tab.title)
        label.font = .systemFont(ofSize: 13, weight: tab.isSelected ? .semibold : .regular)
        label.textColor = tab.isSelected ? .labelColor : .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.identifier = NSUserInterfaceItemIdentifier(plan.tabAccessibilityIdentifier(for: tabIndex))
        label.setAccessibilityIdentifier(plan.tabAccessibilityIdentifier(for: tabIndex))
        label.setAccessibilityLabel(tab.title)
        label.setAccessibilityValue(tab.isSelected ? "Selected Tab" : "Background Tab")
        label.setAccessibilityElement(true)
        label.wantsLayer = true
        label.layer?.cornerRadius = 6
        label.layer?.backgroundColor = (tab.isSelected ? NSColor.white : NSColor.clear).cgColor
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
